// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

/// Version number for GS and other shaders. Increment whenever any of the contents of the
/// shaders change, to invalidate the cache.
static constexpr u32 SHADER_CACHE_VERSION = 119; // Last changed merging upstream v2.9.81 (its own 118, PR 14987) into the GL ES shader port
