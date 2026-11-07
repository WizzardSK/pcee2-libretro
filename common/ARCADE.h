/**
 * @file ARCADE.h
 * @author El_isra
 * @brief common definitions for arcade related stuff, generic constants and such
 * 
 */

#pragma once
#include <string>

enum ACMEDIATYPE {
    ACUNK = -1, //Unknown
    ACCD = 0,
    ACDVD,
    ACHDD,
};

#define ACMEDIATYPE_FROM_STRING(s) \
    ((s) == "CD"  ? ACMEDIATYPE::ACCD : \
    (s) == "DVD" ? ACMEDIATYPE::ACDVD : \
    (s) == "HDD" ? ACMEDIATYPE::ACHDD : \
    ACMEDIATYPE::ACUNK)

    

struct ArcadeBootParams {
	std::string cards[2];
	std::string mediapath;
	std::string elf_path;
	std::string sram_path;
	ACMEDIATYPE MediaType;
};