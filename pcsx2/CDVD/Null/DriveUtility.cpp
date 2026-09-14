// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

// Drive enumeration on platforms with no drives to enumerate. See the note in
// CDVD/Null/IOCtlSrc.cpp.

#include "CDVD/CDVDdiscReader.h"

#include <string>
#include <vector>

std::vector<std::string> GetOpticalDriveList()
{
	return {};
}

void GetValidDrive(std::string& drive)
{
	drive.clear();
}
