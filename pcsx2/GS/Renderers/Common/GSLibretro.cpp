// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#include "GS/Renderers/Common/GSLibretro.h"

namespace GSLibretro
{
	bool Active = false;
	std::atomic<float> DisplayAspect{0.0f};
	std::atomic<u64> NativeSize{0};
} // namespace GSLibretro
