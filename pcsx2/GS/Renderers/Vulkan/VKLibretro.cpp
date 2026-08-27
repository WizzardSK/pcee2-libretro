// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#include "VKLibretro.h"

#include "common/Console.h"

#include <condition_variable>
#include <cstring>
#include <mutex>
#include <chrono>
#include <shared_mutex>
#include <vector>

// Only the retro_hw_render_interface_vulkan layout is needed here; pull it
// from the core frontend's bundled header.
#define VK_NO_PROTOTYPES
#include "libretro_vulkan.h"

namespace VKLibretro
{
	bool Active = false;
	InitInfo Init;

	// Written by the frontend thread (context_reset/context_destroy), read by
	// the GS thread on every queue submit. The lock keeps a submit that is
	// already inside the wrapper holding a valid interface: dropping it while
	// that submit runs left the GS thread calling through a freed vtable
	// (SIGSEGV at a null lock_queue) or releasing a queue lock it never took.
	static retro_hw_render_interface_vulkan* s_hw_render = nullptr;
	static std::shared_timed_mutex s_hw_render_mutex;

	static PFN_vkGetInstanceProcAddr s_vkGetInstanceProcAddr_org;
	static PFN_vkGetDeviceProcAddr s_vkGetDeviceProcAddr_org;
	static PFN_vkCreateDevice s_vkCreateDevice_org;
	static PFN_vkQueueSubmit s_vkQueueSubmit_org;

	static void AddNameUnique(std::vector<const char*>& list, const char* value)
	{
		for (const char* name : list)
		{
			if (!std::strcmp(value, name))
				return;
		}
		list.push_back(value);
	}

	// Merge the frontend's required device layers/extensions/features into
	// whatever GSDeviceVK asked for, and remember the created device so the
	// negotiation callback can return it to the frontend.
	static VKAPI_ATTR VkResult VKAPI_CALL vkCreateDevice_libretro(VkPhysicalDevice physicalDevice,
		const VkDeviceCreateInfo* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDevice* pDevice)
	{
		VkDeviceCreateInfo info = *pCreateInfo;
		std::vector<const char*> layers(info.ppEnabledLayerNames, info.ppEnabledLayerNames + info.enabledLayerCount);
		std::vector<const char*> exts(
			info.ppEnabledExtensionNames, info.ppEnabledExtensionNames + info.enabledExtensionCount);

		for (unsigned i = 0; i < Init.num_required_device_layers; i++)
			AddNameUnique(layers, Init.required_device_layers[i]);
		for (unsigned i = 0; i < Init.num_required_device_extensions; i++)
			AddNameUnique(exts, Init.required_device_extensions[i]);

		// pEnabledFeatures may be null when features come in through pNext
		// (VkPhysicalDeviceFeatures2); only merge the plain struct case.
		VkPhysicalDeviceFeatures features{};
		if (info.pEnabledFeatures)
			features = *info.pEnabledFeatures;
		if (Init.required_features)
		{
			for (unsigned i = 0; i < sizeof(VkPhysicalDeviceFeatures) / sizeof(VkBool32); i++)
			{
				if (reinterpret_cast<const VkBool32*>(Init.required_features)[i])
					reinterpret_cast<VkBool32*>(&features)[i] = VK_TRUE;
			}
		}

		info.enabledLayerCount = static_cast<uint32_t>(layers.size());
		info.ppEnabledLayerNames = info.enabledLayerCount ? layers.data() : nullptr;
		info.enabledExtensionCount = static_cast<uint32_t>(exts.size());
		info.ppEnabledExtensionNames = info.enabledExtensionCount ? exts.data() : nullptr;
		if (info.pEnabledFeatures || Init.required_features)
			info.pEnabledFeatures = &features;

		const VkResult res = s_vkCreateDevice_org(physicalDevice, &info, pAllocator, pDevice);
		if (res == VK_SUCCESS)
			Init.device = *pDevice;
		return res;
	}

	// The graphics queue is shared with the frontend; every submit must hold
	// its queue lock.
	static VKAPI_ATTR VkResult VKAPI_CALL vkQueueSubmit_libretro(
		VkQueue queue, uint32_t submitCount, const VkSubmitInfo* pSubmits, VkFence fence)
	{
		// One read for the whole critical section: the queue lock has to be
		// released through the same interface it was taken from, and holding
		// the shared lock stops context_destroy from retiring it underneath.
		std::shared_lock<std::shared_timed_mutex> iface_guard(s_hw_render_mutex);
		retro_hw_render_interface_vulkan* const iface = s_hw_render;
		if (iface)
			iface->lock_queue(iface->handle);
		const VkResult res = s_vkQueueSubmit_org(queue, submitCount, pSubmits, fence);
		if (iface)
			iface->unlock_queue(iface->handle);
		return res;
	}

	static VKAPI_ATTR PFN_vkVoidFunction Intercept(PFN_vkVoidFunction fptr, const char* pName);

	static VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr_libretro(VkDevice device, const char* pName)
	{
		PFN_vkVoidFunction fptr = s_vkGetDeviceProcAddr_org(device, pName);
		if (!fptr)
			return fptr;
		return Intercept(fptr, pName);
	}

	static VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr_libretro(
		VkInstance instance, const char* pName)
	{
		PFN_vkVoidFunction fptr = s_vkGetInstanceProcAddr_org(instance, pName);
		if (!fptr)
			return fptr;
		return Intercept(fptr, pName);
	}

	static VKAPI_ATTR PFN_vkVoidFunction Intercept(PFN_vkVoidFunction fptr, const char* pName)
	{
		if (!std::strcmp(pName, "vkGetDeviceProcAddr"))
		{
			s_vkGetDeviceProcAddr_org = reinterpret_cast<PFN_vkGetDeviceProcAddr>(fptr);
			return reinterpret_cast<PFN_vkVoidFunction>(vkGetDeviceProcAddr_libretro);
		}
		if (!std::strcmp(pName, "vkCreateDevice"))
		{
			s_vkCreateDevice_org = reinterpret_cast<PFN_vkCreateDevice>(fptr);
			return reinterpret_cast<PFN_vkVoidFunction>(vkCreateDevice_libretro);
		}
		if (!std::strcmp(pName, "vkQueueSubmit"))
		{
			s_vkQueueSubmit_org = reinterpret_cast<PFN_vkQueueSubmit>(fptr);
			return reinterpret_cast<PFN_vkVoidFunction>(vkQueueSubmit_libretro);
		}
		return fptr;
	}

	void InstallWraps()
	{
		// Idempotent: the loader entry points survive a session now (the
		// library is no longer unloaded under the frontend), so a second
		// retro_load_game() would otherwise capture our own wrapper as the
		// "original" and recurse into it forever.
		if (vkGetInstanceProcAddr == vkGetInstanceProcAddr_libretro)
			return;

		s_vkGetInstanceProcAddr_org = vkGetInstanceProcAddr;
		vkGetInstanceProcAddr = vkGetInstanceProcAddr_libretro;
	}

	void SetHWRenderInterface(void* iface)
	{
		// Waits out a submit that is already inside the wrapper, so once the
		// frontend's context_destroy returns from here nothing can still be
		// calling into the interface it is about to throw away.
		//
		// Bounded on purpose: that submit may itself be waiting on the
		// frontend's queue lock, and if the frontend happens to hold that lock
		// while retiring the interface, an unbounded wait here would deadlock
		// the two threads against each other. A rare torn hand-off beats a
		// hung emulator, so time out, say so, and go ahead.
		std::unique_lock<std::shared_timed_mutex> iface_guard(s_hw_render_mutex, std::defer_lock);
		if (!iface_guard.try_lock_for(std::chrono::milliseconds(500)))
			Console.Warning("VKLibretro: a queue submit is still in flight; retiring the render interface anyway.");
		s_hw_render = static_cast<retro_hw_render_interface_vulkan*>(iface);
	}

	void* GetHWRenderInterface()
	{
		std::shared_lock<std::shared_timed_mutex> iface_guard(s_hw_render_mutex);
		return s_hw_render;
	}

	static std::mutex s_frame_mutex;
	static std::condition_variable s_frame_consumed_cv;
	static Frame s_frame;
	static u64 s_frame_serial = 0;
	static u64 s_frame_consumed = 0;
	static bool s_pacing = false;

	void PublishFrame(const Frame& frame)
	{
		std::unique_lock<std::mutex> lock(s_frame_mutex);
		s_frame = frame;
		s_frame_serial++;
		// Block the GS thread until retro_run picks the frame up (or pacing
		// gets aborted for shutdown): one presented frame per retro_run.
		s_frame_consumed_cv.wait(
			lock, []() { return !s_pacing || s_frame_consumed == s_frame_serial; });
	}

	bool ConsumeFrame(Frame* out_frame)
	{
		std::lock_guard<std::mutex> lock(s_frame_mutex);
		if (s_frame_serial == s_frame_consumed || s_frame.image == VK_NULL_HANDLE)
			return false;
		s_frame_consumed = s_frame_serial;
		*out_frame = s_frame;
		s_frame_consumed_cv.notify_all();
		return true;
	}

	bool HasFrame()
	{
		std::lock_guard<std::mutex> lock(s_frame_mutex);
		return s_frame_serial != s_frame_consumed && s_frame.image != VK_NULL_HANDLE;
	}

	void SetPacing(bool enabled)
	{
		std::lock_guard<std::mutex> lock(s_frame_mutex);
		s_pacing = enabled;
		if (!enabled)
			s_frame_consumed_cv.notify_all();
	}

	void AbortPacing()
	{
		SetPacing(false);
	}

	void Shutdown()
	{
		Init = InitInfo();
		{
			std::unique_lock<std::shared_timed_mutex> iface_guard(s_hw_render_mutex);
			s_hw_render = nullptr;
		}
		std::lock_guard<std::mutex> lock(s_frame_mutex);
		s_frame = Frame();
		s_frame_serial = 0;
		s_frame_consumed = 0;
		s_pacing = false;
		s_frame_consumed_cv.notify_all();
	}
} // namespace VKLibretro
