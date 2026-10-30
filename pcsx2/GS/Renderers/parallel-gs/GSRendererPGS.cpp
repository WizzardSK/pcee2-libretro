// SPDX-FileCopyrightText: 2024 Hans-Kristian Arntzen
// SPDX-License-Identifier: LGPL-3.0+

#include "GSRendererPGS.h"
#include "GSParallelGS.h"

#include <string.h>
#include <mutex>
#include <utility>
#include <vector>
#include "thread_id.hpp"
#include "common/Pcsx2Defs.h"
#include "common/Console.h"
#include "GS/GSState.h"
#include "GS.h"
#include "PerformanceMetrics.h"
#ifdef ENABLE_PCSX2_PROFILER
#include "Profiler.h"
#else
#define PROFILE_SCOPE(z) do {} while (0)
#endif
#include "logging.hpp"
#include <stdarg.h>
#include <atomic>
// TEMP lag probe (Libretro.cpp)
extern std::atomic<u64> s_probe_vm_frames, g_probe_publish_vm;

using namespace Vulkan;
using namespace ParallelGS;
using namespace Granite;

static retro_hw_render_interface_vulkan *hw_render_iface;
static std::unique_ptr<Vulkan::Context> vulkan_ctx;

#define PGS_THREAD_INDEX_COUNT 4

/* The handover of a scanned-out frame to the frontend.
 *
 * The GS runs on its own thread here, and set_image, wait_sync_index and
 * the video callback are the frontend's to be called from retro_run only.
 * So VSync publishes the frame and retro_run hands it over
 * (ParallelGSRenderer::PresentFrame). The images themselves stay on the GS
 * thread: the frontend side only ever sees the raw handles and serials.
 *
 * The frontend reads the image it was handed on its own schedule: on a
 * threaded video path that is a frame or more after set_image(), and under
 * fast-forward many frames after. The libretro Vulkan interface's sync index
 * is the answer to that: the frontend says which of its slots this frame goes
 * into, wait_sync_index() returns once it has finished reading whatever that
 * slot held before, and only then is that image let go - reported back to the
 * GS thread, which offers it to the next scanout. Nothing is copied. */
struct PublishedFrame
{
	u64 serial = 0;
	VkImage image = VK_NULL_HANDLE;
	VkImageView view = VK_NULL_HANDLE;
	unsigned width = 0;
	unsigned height = 0;
};
static std::mutex present_mutex;
static PublishedFrame published;          // newest frame, under present_mutex
static u64 consumed_serial = 0;           // newest serial retro_run took, under present_mutex
static std::vector<u64> released_serials; // done with on the frontend side, under present_mutex
/* GS thread only: the images published and not released yet, by serial. */
static std::vector<std::pair<u64, ImageHandle>> held_images;
static u64 next_serial = 0;
/* retro_run only: the serial each frontend slot holds, and the descriptor
 * it was pointed at - the frontend keeps the pointer (a cached-frame replay
 * dereferences it again), so it stays valid while the slot holds the image. */
static u64 slot_serials[32];
static retro_vulkan_image vsync_descs[32];
/* Images the frontend has finished with, offered back to the renderer
 * for the next frame's scanout instead of a fresh one each frame. */
static std::vector<ImageHandle> spare_vsync_images;
/* TEMP lag probe: the serial retro_run handed over last, and the newest one */
u64 g_pgs_probe_presented_serial = 0, g_pgs_probe_newest_serial = 0;

static void pgs_recycle_released_images();

static void pgs_release_vsync_images()
{
	std::lock_guard<std::mutex> lock(present_mutex);
	published = {};
	consumed_serial = 0;
	released_serials.clear();
	held_images.clear();
	memset(slot_serials, 0, sizeof(slot_serials));
	memset(vsync_descs, 0, sizeof(vsync_descs));
	spare_vsync_images.clear();
}

struct LibretroLog final : Util::LoggingInterface
{
	bool log(const char *tag, const char *fmt, va_list va) override
	{

		/* Logs from any of Granite's threads: short lines on the stack,
		 * longer ones on the heap. */
		char small[512];
		char* buf = small;
		va_list again;
		va_copy(again, va);
		const int len = vsnprintf(small, sizeof(small), fmt, va);
		if (len >= (int)sizeof(small) && (buf = (char*)malloc((size_t)len + 1)) != nullptr)
			vsnprintf(buf, (size_t)len + 1, fmt, again);
		else if (!buf)
			buf = small;
		va_end(again);

		retro_log_level level = RETRO_LOG_DUMMY;
		if (strcmp(tag, "[ERROR]: ") == 0)
			level = RETRO_LOG_ERROR;
		else if (strcmp(tag, "[INFO]: ") == 0)
			level = RETRO_LOG_INFO;
		else if (strcmp(tag, "[WARN]: ") == 0)
			level = RETRO_LOG_WARN;

		PGSLibretro::Log(level, buf);
		if (buf != small)
			free(buf);
		return true;
	}
};
static LibretroLog logging_iface;

void pgs_set_hwrender_interface(retro_hw_render_interface_vulkan *iface)
{
	hw_render_iface = iface;
	Util::set_thread_logging_interface(&logging_iface);
}

const VkApplicationInfo *pgs_get_application_info()
{
	static VkApplicationInfo app =
	{
		VK_STRUCTURE_TYPE_APPLICATION_INFO, nullptr,
		"PCSX2", VK_MAKE_VERSION(1, 7, 0),
		"Granite", 0,
		VK_API_VERSION_1_2
	};

	return &app;
}

bool pgs_create_device(retro_vulkan_context *context,
	VkInstance instance, VkPhysicalDevice gpu, VkSurfaceKHR surface,
	PFN_vkGetInstanceProcAddr get_instance_proc_addr,
	const char **required_device_extensions, unsigned num_required_device_extensions,
	const char **required_device_layers, unsigned num_required_device_layers,
	const VkPhysicalDeviceFeatures *required_features)
{
	// We only expect v2 interface.
	return false;
}

void pgs_destroy_device()
{
	pgs_release_vsync_images();
	vulkan_ctx.reset();
	hw_render_iface = nullptr;
}

VkInstance pgs_create_instance(PFN_vkGetInstanceProcAddr get_instance_proc_addr,
	const VkApplicationInfo *app,
	retro_vulkan_create_instance_wrapper_t create_instance_wrapper,
	void *opaque)
{
	Util::set_thread_logging_interface(&logging_iface);
	vulkan_ctx.reset();

	// Always force the reload, since the other backends may clobber the volk pointers.
	if (!Context::init_loader(get_instance_proc_addr, true))
		return VK_NULL_HANDLE;

	vulkan_ctx = std::make_unique<Context>();
	Context::SystemHandles handles = {};
	vulkan_ctx->set_system_handles(handles);
	/* One command pool per recording thread per frame: the GS thread
	 * (index 0, registered by Device::set_context) and whichever other
	 * thread records - the EE/VM thread on a readback, say. The pools
	 * are small, and a thread past this count would share pool 0 with
	 * the GS thread, which Vulkan forbids. Compile threads register 0
	 * themselves and never record. */
	vulkan_ctx->set_num_thread_indices(PGS_THREAD_INDEX_COUNT);
	Util::set_thread_index_count(PGS_THREAD_INDEX_COUNT);
	vulkan_ctx->set_application_info(app);

	struct Factory final : Vulkan::InstanceFactory
	{
		VkInstance create_instance(const VkInstanceCreateInfo *info) override
		{
			return wrapper(opaque, info);
		}

		retro_vulkan_create_instance_wrapper_t wrapper = nullptr;
		void *opaque = nullptr;
	} factory;

	factory.wrapper = create_instance_wrapper;
	factory.opaque = opaque;
	vulkan_ctx->set_instance_factory(&factory);

	if (!vulkan_ctx->init_instance(nullptr, 0))
	{
		vulkan_ctx.reset();
		return VK_NULL_HANDLE;
	}

	vulkan_ctx->release_instance();
	return vulkan_ctx->get_instance();
}

bool pgs_create_device2(
	struct retro_vulkan_context *context,
	VkInstance instance,
	VkPhysicalDevice gpu,
	VkSurfaceKHR surface,
	PFN_vkGetInstanceProcAddr get_instance_proc_addr,
	retro_vulkan_create_device_wrapper_t create_device_wrapper,
	void *opaque)
{
	// We are guaranteed that create_instance has been called here.
	if (!vulkan_ctx)
		return false;

	// Sanity check inputs.
	if (vulkan_ctx->get_instance() != instance)
		return false;
	if (Vulkan::Context::get_instance_proc_addr() != get_instance_proc_addr)
		return false;

	struct Factory final : Vulkan::DeviceFactory
	{
		VkDevice create_device(VkPhysicalDevice gpu, const VkDeviceCreateInfo *info) override
		{
			return wrapper(gpu, opaque, info);
		}

		retro_vulkan_create_device_wrapper_t wrapper = nullptr;
		void *opaque = nullptr;
	} factory;

	factory.wrapper = create_device_wrapper;
	factory.opaque = opaque;
	vulkan_ctx->set_device_factory(&factory);

	if (!vulkan_ctx->init_device(gpu, surface, nullptr, 0, Vulkan::CONTEXT_CREATION_ENABLE_PUSH_DESCRIPTOR_BIT))
		return false;

	vulkan_ctx->release_device();
	context->gpu = vulkan_ctx->get_gpu();
	context->device = vulkan_ctx->get_device();
	context->presentation_queue = vulkan_ctx->get_queue_info().queues[Vulkan::QUEUE_INDEX_GRAPHICS];
	context->presentation_queue_family_index = vulkan_ctx->get_queue_info().family_indices[Vulkan::QUEUE_INDEX_GRAPHICS];
	context->queue = vulkan_ctx->get_queue_info().queues[Vulkan::QUEUE_INDEX_GRAPHICS];
	context->queue_family_index = vulkan_ctx->get_queue_info().family_indices[Vulkan::QUEUE_INDEX_GRAPHICS];
	return true;
}

GSRendererPGS::GSRendererPGS(u8 *basemem)
	: priv(reinterpret_cast<PrivRegisterState *>(basemem))
{
}

u8 *GSRendererPGS::GetRegsMem()
{
	return reinterpret_cast<u8 *>(priv);
}

GSRendererPGS::~GSRendererPGS()
{
	pgs_release_vsync_images();
}

struct ParsedSuperSampling
{
	SuperSampling super_sampling;
	bool ordered;
};

static ParsedSuperSampling parse_super_sampling_options(u8 super_sampling)
{
	ParsedSuperSampling parsed = {};

	if (super_sampling > 7)
		super_sampling = 7;

	// Setting 6 is the ordered 16x grid: the only layout that resolves
	// two position bits per axis, which the 4x high-res scanout needs.
	// Setting 7 is the ordered 4x8 grid, with a third row bit for the
	// full-field-height scanout of field-rendered games.
	if (super_sampling >= 6)
	{
		parsed.ordered = true;
		parsed.super_sampling = super_sampling == 7 ? SuperSampling::X32 : SuperSampling::X16;
		return parsed;
	}

	parsed.ordered = super_sampling == 3;

	if (super_sampling >= 3)
		super_sampling--;
	parsed.super_sampling = SuperSampling(1u << super_sampling);

	return parsed;
}

bool GSRendererPGS::Init()
{
	/* Granite's log goes through a per-thread interface: this is the GS
	 * thread, not the frontend's that made the context. */
	Util::set_thread_logging_interface(&logging_iface);
	if (!vulkan_ctx)
	{
		Console.Error("paraLLEl-GS: no Vulkan context; the frontend did not create the device through paraLLEl-GS.");
		return false;
	}

	dev.set_context(*vulkan_ctx);
	// We'll cycle through a lot of these.
	dev.init_frame_contexts(12);
	dev.set_queue_lock([]() {
	                     if (hw_render_iface)
		                     hw_render_iface->lock_queue(hw_render_iface->handle);
	                   },
	                   []() {
	                     if (hw_render_iface)
		                     hw_render_iface->unlock_queue(hw_render_iface->handle);
	                   });

	GSOptions opts = {};
	opts.vram_size = GSLocalMemory::m_vmsize;

	auto parsed                 = parse_super_sampling_options(GSConfig.PGSSuperSampling);
	opts.super_sampling         = parsed.super_sampling;
	opts.ordered_super_sampling = parsed.ordered;
	opts.dynamic_super_sampling = true;
	opts.super_sampled_textures = GSConfig.PGSSuperSampleTextures != 0;
	if (!iface.init(&dev, opts))
	{
		Console.Error("paraLLEl-GS: the renderer did not start on this GPU (see the requirements above).");
		return false;
	}

	current_super_sampling         = opts.super_sampling;
	current_ordered_super_sampling = opts.ordered_super_sampling;

	Hacks hacks;
	hacks.disable_mipmaps = GSConfig.PGSDisableMipmaps;
	hacks.backbuffer_promotion = GSConfig.PGSSharpBackbuffer != 0;
	/* Honor the unsynchronized-readback download mode for parallel-GS,
	 * mirroring how the other renderers treat HWDownloadMode. Without
	 * this, every GS->host transfer (e.g. memory-card save images)
	 * forces a full GPU flush + wait_timeline stall in init_transfer,
	 * which serialises the GS and EE threads via WaitGS and tanks the
	 * frame rate on readback-heavy screens. */
	hacks.unsynced_readbacks =
		(GSConfig.HWDownloadMode >= GSHardwareDownloadMode::Unsynchronized);
	iface.set_hacks(hacks);

	return true;
}

void GSRendererPGS::Reset(bool /*hardware_reset*/)
{
	iface.reset_context_state();
}

void GSRendererPGS::UpdateConfig()
{
	auto parsed = parse_super_sampling_options(GSConfig.PGSSuperSampling);

	if (parsed.super_sampling != current_super_sampling || parsed.ordered != current_ordered_super_sampling ||
	    current_super_sample_textures != bool(GSConfig.PGSSuperSampleTextures))
	{
		iface.set_super_sampling_rate(parsed.super_sampling, parsed.ordered, GSConfig.PGSSuperSampleTextures != 0);
		current_super_sampling = parsed.super_sampling;
		current_ordered_super_sampling = parsed.ordered;
		current_super_sample_textures = bool(GSConfig.PGSSuperSampleTextures);
	}

	Hacks hacks;
	hacks.disable_mipmaps = GSConfig.PGSDisableMipmaps != 0;
	hacks.backbuffer_promotion = GSConfig.PGSSharpBackbuffer != 0;
	hacks.unsynced_readbacks =
		(GSConfig.HWDownloadMode >= GSHardwareDownloadMode::Unsynchronized);
	iface.set_hacks(hacks);
}

int GSRendererPGS::GetSaveStateSize()
{
	return GSState::GetCurrentSaveStateSize();
}

static void write_data(u8*& dst, const void* src, size_t size)
{
	memcpy(dst, src, size);
	dst += size;
}

template <typename T>
static void write_reg(u8*& data, T t)
{
	write_data(data, &t, sizeof(t));
}

static void read_data(const u8*& src, void* dst, size_t size)
{
	memcpy(dst, src, size);
	src += size;
}

template <typename T>
static void read_reg(const u8*& src, T &t)
{
	read_data(src, &t, sizeof(t));
}

int GSRendererPGS::Freeze(freezeData* data, bool sizeonly)
{
	if (sizeonly)
	{
		data->size = GetSaveStateSize();
		return 0;
	}

	if (!data->data || data->size < GetSaveStateSize())
		return -1;

	const void *vram = iface.map_vram_read(0, GSLocalMemory::m_vmsize);
	auto &regs = iface.get_register_state();

	u8 *ptr = data->data;

	write_reg(ptr, GSState::STATE_VERSION);
	write_reg(ptr, regs.prim);
	write_reg(ptr, regs.prmodecont);
	write_reg(ptr, regs.texclut);
	write_reg(ptr, regs.scanmsk);
	write_reg(ptr, regs.texa);
	write_reg(ptr, regs.fogcol);
	write_reg(ptr, regs.dimx);
	write_reg(ptr, regs.dthe);
	write_reg(ptr, regs.colclamp);
	write_reg(ptr, regs.pabe);
	write_reg(ptr, regs.bitbltbuf);
	write_reg(ptr, regs.trxdir);
	write_reg(ptr, regs.trxpos);
	write_reg(ptr, regs.trxreg);
	write_reg(ptr, regs.trxreg); // Dummy value

	for (const auto &ctx : regs.ctx)
	{
		write_reg(ptr, ctx.xyoffset);
		write_reg(ptr, ctx.tex0);
		write_reg(ptr, ctx.tex1);
		write_reg(ptr, ctx.clamp);
		write_reg(ptr, ctx.miptbl_1_3);
		write_reg(ptr, ctx.miptbl_4_6);
		write_reg(ptr, ctx.scissor);
		write_reg(ptr, ctx.alpha);
		write_reg(ptr, ctx.test);
		write_reg(ptr, ctx.fba);
		write_reg(ptr, ctx.frame);
		write_reg(ptr, ctx.zbuf);
	}

	write_reg(ptr, regs.rgbaq);
	write_reg(ptr, regs.st);
	write_reg(ptr, regs.uv.words[0]);
	write_reg(ptr, regs.fog.words[0]);
	// XYZ register, fill with dummy.
	write_reg(ptr, Reg64<XYZBits>{0});

	write_reg(ptr, UINT32_MAX); // Dummy GIFReg
	write_reg(ptr, UINT32_MAX);

	// Dummy transfer X/Y
	write_reg(ptr, uint32_t(0));
	write_reg(ptr, uint32_t(0));

	write_data(ptr, vram, GSLocalMemory::m_vmsize);

	// 4 GIF paths
	for (int i = 0; i < 4; i++)
	{
		auto gif_path = iface.get_gif_path(i);
		gif_path.tag.NLOOP -= gif_path.loop;
		write_data(ptr, &gif_path.tag, sizeof(gif_path.tag));
		write_reg(ptr, gif_path.reg);
	}

	// internal_Q
	write_reg(ptr, regs.internal_q);
	return 0;
}

int GSRendererPGS::Defrost(freezeData* data)
{
	if (!data || !data->data || data->size == 0)
		return -1;

	if (data->size < GetSaveStateSize())
		return -1;

	const u8* ptr = data->data;
	auto &regs = iface.get_register_state();

	u32 version;
	read_reg(ptr, version);

	if (version != GSState::STATE_VERSION)
	{
		Console.Error("GS: Savestate version is incompatible.  Load aborted.");
		return -1;
	}

	read_reg(ptr, regs.prim);
	read_reg(ptr, regs.prmodecont);
	read_reg(ptr, regs.texclut);
	read_reg(ptr, regs.scanmsk);
	read_reg(ptr, regs.texa);
	read_reg(ptr, regs.fogcol);
	read_reg(ptr, regs.dimx);
	read_reg(ptr, regs.dthe);
	read_reg(ptr, regs.colclamp);
	read_reg(ptr, regs.pabe);
	read_reg(ptr, regs.bitbltbuf);
	read_reg(ptr, regs.trxdir);
	read_reg(ptr, regs.trxpos);
	read_reg(ptr, regs.trxreg);
	// Dummy value
	ptr += sizeof(uint64_t);

	for (auto &ctx : regs.ctx)
	{
		read_reg(ptr, ctx.xyoffset);
		read_reg(ptr, ctx.tex0);
		read_reg(ptr, ctx.tex1);
		read_reg(ptr, ctx.clamp);
		read_reg(ptr, ctx.miptbl_1_3);
		read_reg(ptr, ctx.miptbl_4_6);
		read_reg(ptr, ctx.scissor);
		read_reg(ptr, ctx.alpha);
		read_reg(ptr, ctx.test);
		read_reg(ptr, ctx.fba);
		read_reg(ptr, ctx.frame);
		read_reg(ptr, ctx.zbuf);
	}

	read_reg(ptr, regs.rgbaq);
	read_reg(ptr, regs.st);
	read_reg(ptr, regs.uv.words[0]);
	read_reg(ptr, regs.fog.words[0]);
	// XYZ register, fill with dummy.
	ptr += sizeof(uint64_t);

	// Dummy GIFReg
	ptr += 2 * sizeof(uint32_t);

	// Dummy transfer X/Y
	ptr += 2 * sizeof(uint32_t);

	void *vram = iface.map_vram_write(0, GSLocalMemory::m_vmsize);
	read_data(ptr, vram, GSLocalMemory::m_vmsize);
	iface.end_vram_write(0, GSLocalMemory::m_vmsize);

	// 4 GIF paths: the tag as Freeze wrote it, NLOOP counting what was
	// left of the packet, so the path resumes with none of it done.
	for (int i = 0; i < 4; i++)
	{
		auto &gif_path = iface.get_gif_path(i);
		read_data(ptr, &gif_path.tag, sizeof(gif_path.tag));
		gif_path.loop = 0;
		read_reg(ptr, gif_path.reg);
	}

	// internal_Q
	read_reg(ptr, iface.get_register_state().internal_q);

	iface.clobber_register_state();
	return 0;
}


void GSRendererPGS::VSync(u32 field, bool registers_written)
{
	iface.flush();
	iface.get_priv_register_state() = *priv;

	VSyncInfo info = {};

	info.phase = field;

	// Apparently this is needed for game-fixes.
	if (GSConfig.InterlaceMode != GSInterlaceMode::Automatic)
		info.phase ^= (static_cast<int>(GSConfig.InterlaceMode) - 2) & 1;

	info.anti_blur = GSConfig.PCRTCAntiBlur;
	info.force_progressive = true;
	info.overscan = GSConfig.PCRTCOverscan;
	info.crtc_offsets = GSConfig.PCRTCOffsets;
	info.dst_access = VK_ACCESS_2_SHADER_SAMPLED_READ_BIT;
	info.dst_stage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
	info.dst_layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
	// The scaling blur is technically a blur ...
	info.adapt_to_internal_horizontal_resolution = GSConfig.PCRTCAntiBlur;
	info.raw_circuit_scanout                     = true;
	pgs_recycle_released_images();
	info.recycle                                 = &spare_vsync_images;
	// Config values: 0 = off, 1 = 2x, 2 = 4x point-sampled,
	// 3 = 4x with the tent reconstruction filter, 4 = 4x with a
	// field-rendered game at its full field height, 5 = both.
	info.high_resolution_scanout                 = GSConfig.PGSHighResScanout >= 3 ? 2 : GSConfig.PGSHighResScanout;
	info.high_res_scanout_filtered               = GSConfig.PGSHighResScanout == 3 || GSConfig.PGSHighResScanout == 5;
	info.high_res_scanout_full_field             = GSConfig.PGSHighResScanout >= 4;
	auto vsync                                   = iface.vsync(info);

	if (vsync.image)
	{
		const uint32_t new_base_width  = vsync.image->get_width();
		const uint32_t new_base_height = vsync.image->get_height();

		dev.flush_frame();

		// The core's Aspect Ratio option (4:3, or 16:9 with widescreen patches),
		// corrected for the part of the mode that was scanned out
		float aspect = PGSLibretro::AspectRatio();
		const float horizontal_scanout_ratio = float(vsync.internal_width) / float(vsync.mode_width);
		const float vertical_scanout_ratio = float(vsync.internal_height) / float(vsync.mode_height);
		aspect *= horizontal_scanout_ratio / vertical_scanout_ratio;
		// The size the frontend scales by is the single-sampled one, not the
		// high-resolution scanout's
		PGSLibretro::SetDisplay(aspect, new_base_width >> vsync.high_resolution_scanout,
			new_base_height >> vsync.high_resolution_scanout);

		const u64 serial = ++next_serial;
		g_pgs_probe_newest_serial = serial;
		{
			std::lock_guard<std::mutex> lock(present_mutex);
			g_probe_publish_vm.store(s_probe_vm_frames.load());
			// A frame retro_run never took will not be taken any more
			if (published.serial && published.serial != consumed_serial)
				released_serials.push_back(published.serial);
			published.serial = serial;
			published.image  = vsync.image->get_image();
			published.view   = vsync.image->get_view().get_unorm_view().view;
			published.width  = new_base_width;
			published.height = new_base_height;
		}
		held_images.emplace_back(serial, vsync.image);
		last_base_width  = new_base_width;
		last_base_height = new_base_height;
	}
	/* vsync() ended with a flush that already moved the device to its
	 * next frame context; nothing was submitted since. */
}

/* GS thread: the images the frontend is done with become spares. One per
 * slot is enough; past that the list is only holding sizes the mode has
 * moved away from. */
static void pgs_recycle_released_images()
{
	std::vector<u64> released;
	{
		std::lock_guard<std::mutex> lock(present_mutex);
		released.swap(released_serials);
	}
	for (u64 serial : released)
	{
		for (auto it = held_images.begin(); it != held_images.end(); ++it)
		{
			if (it->first != serial)
				continue;
			if (spare_vsync_images.size() >= 4)
				spare_vsync_images.erase(spare_vsync_images.begin());
			spare_vsync_images.push_back(std::move(it->second));
			held_images.erase(it);
			break;
		}
	}
}

void GSRendererPGS::GetInternalResolution(int* width, int* height)
{
	*width  = static_cast<int>(last_base_width);
	*height = static_cast<int>(last_base_height);
}

void GSRendererPGS::Transfer(const u8* mem, u32 size)
{
	size *= 16;
	iface.gif_transfer(3, mem, size);
}

void GSRendererPGS::ReadFIFO(u8 *mem, u32 size)
{
	iface.read_transfer_fifo(mem, size);
}

/* --- GSParallelGS.h: the renderer behind GS.cpp's entry points ---------- */
static std::unique_ptr<GSRendererPGS> s_pgs;

bool ParallelGSRenderer::Open(u8* basemem)
{
	s_pgs = std::make_unique<GSRendererPGS>(basemem);
	if (s_pgs->Init())
		return true;
	s_pgs.reset();
	return false;
}

void ParallelGSRenderer::Close()                                  { s_pgs.reset(); }
bool ParallelGSRenderer::IsOpen()                                 { return s_pgs != nullptr; }
void ParallelGSRenderer::Reset(bool hardware_reset)               { s_pgs->Reset(hardware_reset); }
void ParallelGSRenderer::ReadFIFO(u8* mem, u32 size)              { s_pgs->ReadFIFO(mem, size); }
void ParallelGSRenderer::Transfer(const u8* mem, u32 size)        { s_pgs->Transfer(mem, size); }
void ParallelGSRenderer::VSync(u32 field, bool registers_written) { s_pgs->VSync(field, registers_written); }
void ParallelGSRenderer::UpdateConfig()                           { s_pgs->UpdateConfig(); }
void ParallelGSRenderer::GetInternalResolution(int* width, int* height) { s_pgs->GetInternalResolution(width, height); }

int ParallelGSRenderer::Freeze(int mode, freezeData* data)
{
	switch (static_cast<FreezeAction>(mode))
	{
		case FreezeAction::Save: return s_pgs->Freeze(data, false);
		case FreezeAction::Size: return s_pgs->Freeze(data, true);
		default:                 return s_pgs->Defrost(data);
	}
}

const retro_hw_render_context_negotiation_interface* ParallelGSRenderer::NegotiationInterface()
{
	static retro_hw_render_context_negotiation_interface_vulkan iface = {};
	iface.interface_type = RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN;
	iface.interface_version = 2;
	iface.get_application_info = pgs_get_application_info;
	iface.create_device = pgs_create_device;
	// No destroy_device: RetroArch calls it after it has unloaded the core,
	// where on Windows there is no code left to answer and the frontend
	// crashed on Close Content (KamiLordus, #51). The context is released at
	// retro_deinit instead (ReleaseContext); the device and the instance are
	// the frontend's, which it destroys itself without one.
	iface.destroy_device = nullptr;
	iface.create_instance = pgs_create_instance;
	iface.create_device2 = pgs_create_device2;
	return reinterpret_cast<const retro_hw_render_context_negotiation_interface*>(&iface);
}

void ParallelGSRenderer::ReleaseContext()
{
	pgs_destroy_device();
}

void ParallelGSRenderer::SetHWRenderInterface(retro_hw_render_interface_vulkan* iface)
{
	pgs_set_hwrender_interface(iface);
}

bool ParallelGSRenderer::PresentFrame(retro_hw_render_interface_vulkan* vulkan, unsigned* width, unsigned* height)
{
	PublishedFrame frame;
	{
		std::lock_guard<std::mutex> lock(present_mutex);
		if (!published.serial || published.serial == consumed_serial)
			return false;
		frame = published;
		consumed_serial = frame.serial;
		g_pgs_probe_presented_serial = frame.serial;
	}

	/* The frontend's slot for this frame, and the wait that says it is done
	 * with what the slot held before. A mask, not a count: bit i set means
	 * index i can be returned, so the slots are one past the highest set bit. */
	uint32_t sync_index = vulkan->get_sync_index(vulkan->handle);
	uint32_t sync_mask  = vulkan->get_sync_index_mask(vulkan->handle);
	uint32_t sync_slots = 0;
	while (sync_mask)
	{
		sync_slots++;
		sync_mask >>= 1;
	}
	if (sync_slots < 1)
		sync_slots = 1;
	if (sync_slots > 32)
		sync_slots = 32;
	if (sync_index >= sync_slots)
		sync_index = 0;
	vulkan->wait_sync_index(vulkan->handle);

	retro_vulkan_image& vkimage = vsync_descs[sync_index];
	vkimage = {};
	vkimage.image_view = frame.view;
	vkimage.image_layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
	vkimage.create_info = {
		VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, nullptr, 0,
		frame.image, VK_IMAGE_VIEW_TYPE_2D, VK_FORMAT_R8G8B8A8_UNORM,
		{ VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY },
		{ VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 }
	};
	vulkan->set_image(vulkan->handle, &vkimage, 0, nullptr, vulkan->queue_index);

	/* What this slot held before is the frontend's no longer: the wait
	 * above said so. The one just handed over stays until the slot comes
	 * round again. */
	{
		std::lock_guard<std::mutex> lock(present_mutex);
		if (slot_serials[sync_index])
			released_serials.push_back(slot_serials[sync_index]);
	}
	slot_serials[sync_index] = frame.serial;

	*width  = frame.width;
	*height = frame.height;
	return true;
}
