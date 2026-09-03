// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

// State shared by every libretro present path, whichever graphics API is
// driving it. A libretro frontend never gives the core a window: the GS
// renders into a backbuffer this side sizes and hands over (a VkImage through
// set_image, a GL texture blitted into the frontend's FBO), so the parts of
// the present path that ask "is there a real window behind this?" need one
// answer that does not depend on which backend is loaded.

#pragma once

#include "common/Pcsx2Types.h"

#include <atomic>

namespace GSLibretro
{
	// True when a libretro frontend owns presentation. Set by the core before
	// the GS opens, cleared when the session ends.
	extern bool Active;

	// The display aspect ratio the GS would have corrected the frame to, had it
	// been drawing into a window. The canvas handed over is the merged frame at
	// the size the GS drew it, so the correction is the frontend's to make and
	// this is the number it needs. Zero until the first frame is presented.
	extern std::atomic<float> DisplayAspect;

	// The native, un-upscaled display resolution the GS is drawing, packed as
	// (width << 32) | height so a reader cannot catch one half of a video mode
	// change. The canvas handed over is the upscaled merged frame, and its size
	// moves with the internal-resolution setting and with every field/frame
	// merge; this does not, which is what the geometry reported to the frontend
	// needs, since that is what the frontend's integer scaling is computed
	// from. Zero until the first frame is presented.
	extern std::atomic<u64> NativeSize;

	// Largest output canvas the core will produce: 4x-upscaled PAL expanded to
	// 4:3. Advertised to the frontend as retro_game_geometry max_width/height
	// and enforced when the present path sizes the canvas to the merged frame.
	static constexpr u32 kMaxCanvasWidth = 2732;
	static constexpr u32 kMaxCanvasHeight = 2048;
} // namespace GSLibretro
