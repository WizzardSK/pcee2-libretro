// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#pragma once

// paraLLEl-GS as GS.cpp and the libretro glue see it. No Granite or volk here: Granite's
// headers declare the plain Vulkan entry point names, which PCSX2's own Vulkan code maps
// onto its pcsx2_ ones (VKEntryPoints.h), and the two must not meet in one translation unit.

#include "common/Pcsx2Types.h"

struct freezeData;
struct retro_hw_render_interface_vulkan;
struct retro_hw_render_context_negotiation_interface;

namespace ParallelGSRenderer
{
	// The renderer, on the device the frontend made with it at negotiation
	bool Open(u8* basemem);
	void Close();
	bool IsOpen();

	void Reset(bool hardware_reset);
	void ReadFIFO(u8* mem, u32 size);
	void Transfer(const u8* mem, u32 size);
	void VSync(u32 field, bool registers_written);
	// mode as FreezeAction: 0 load, 1 save, 2 size
	int Freeze(int mode, freezeData* data);
	void UpdateConfig();
	void GetInternalResolution(int* width, int* height);

	// The libretro Vulkan context negotiation interface (v2) to hand the frontend: it creates
	// the instance and the device through it, Granite's context on top of them
	const retro_hw_render_context_negotiation_interface* NegotiationInterface();
	// The frontend's Vulkan interface, at context reset
	void SetHWRenderInterface(retro_hw_render_interface_vulkan* iface);
	// From retro_run: hands the newest frame the GS scanned out to the frontend (set_image)
	// and says its size. False when there is no new one since the last call.
	bool PresentFrame(retro_hw_render_interface_vulkan* vulkan, unsigned* width, unsigned* height);
} // namespace ParallelGSRenderer

// What the renderer needs of the libretro frontend glue (pcee2-libretro/Libretro.cpp)
namespace PGSLibretro
{
	// level is a retro_log_level
	void Log(int level, const char* text);
	// The core's Aspect Ratio option
	float AspectRatio();
	// The display aspect and the single-sampled size of the frame just scanned out
	void SetDisplay(float aspect, u32 width, u32 height);
} // namespace PGSLibretro
