// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

// The physical optical drive, on platforms that cannot have one.
//
// The Windows, Linux and Darwin implementations of this all talk to a real
// drive through that system's ioctl interface. iOS and tvOS have no drive and
// no interface to reach one with - IOKit's storage headers are macOS only - so
// the disc source reports no drives and refuses to open. Everything upstream of
// it already copes with that: it is the same answer a desktop gives when the
// tray is empty, and a libretro core is handed an image rather than a disc
// anyway.

#include "CDVD/CDVDdiscReader.h"

#include "common/Console.h"
#include "common/Error.h"

#include <vector>

IOCtlSrc::IOCtlSrc(std::string filename)
	: m_filename(std::move(filename))
{
}

IOCtlSrc::~IOCtlSrc() = default;

bool IOCtlSrc::Reopen(Error* error)
{
	Error::SetStringView(error, "This platform has no optical drive support.");
	return false;
}

bool IOCtlSrc::ReadDVDInfo()
{
	return false;
}

bool IOCtlSrc::ReadCDInfo()
{
	return false;
}

u32 IOCtlSrc::GetSectorCount() const
{
	return m_sectors;
}

const std::vector<toc_entry>& IOCtlSrc::ReadTOC() const
{
	return m_toc;
}

bool IOCtlSrc::ReadSectors2048(u32 sector, u32 count, u8* buffer) const
{
	return false;
}

bool IOCtlSrc::ReadSectors2352(u32 sector, u32 count, u8* buffer) const
{
	return false;
}

bool IOCtlSrc::ReadTrackSubQ(cdvdSubQ* subq) const
{
	return false;
}

u32 IOCtlSrc::GetLayerBreakAddress() const
{
	return m_layer_break;
}

s32 IOCtlSrc::GetMediaType() const
{
	return m_media_type;
}

void IOCtlSrc::SetSpindleSpeed(bool restore_defaults) const
{
}

bool IOCtlSrc::DiscReady()
{
	return false;
}
