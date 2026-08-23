# Setting it to a range tells it that it supports the features on the newer
# versions as well, avoiding setting policies.
cmake_minimum_required(VERSION 3.16...3.25)

# Enabling this cmake policy gets rid of warnings regarding LTO.
cmake_policy(SET CMP0069 NEW)
set(CMAKE_POLICY_DEFAULT_CMP0069 NEW)

if(${CMAKE_SOURCE_DIR} STREQUAL ${CMAKE_BINARY_DIR})
	message(FATAL_ERROR "PCSX2 does not support in-tree builds.  Please make a build directory that is not the PCSX2 source directory and generate your CMake project there using either `cmake -B build_directory` or by running cmake from the build directory.")
endif()

# Project Name
project(Pcsx2 C CXX)

# Variable to check that people use the good file
set(TOP_CMAKE_WAS_SOURCED TRUE)

# set module path
set(CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)

# detect if webOS compiler
if(CMAKE_CXX_COMPILER MATCHES "webos" OR
   CMAKE_CXX_COMPILER MATCHES "starfish")
	set(WEBOS ON)
endif()

# Write binaries to the bin directory under the build directory.
# This makes it simple to run development builds directly out of the build directory.
if (UNIX AND NOT APPLE)
	set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
	set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")
endif()

# include some generic functions to ensure correctness of the env
include(Pcsx2Utils)

check_no_parenthesis_in_path()
detect_operating_system()
detect_compiler()

#-------------------------------------------------------------------------------
# Include specific module
include(BuildParameters)

# The libretro core is a plugin dropped into someone else's RetroArch install,
# so it cannot assume the Visual C++ redistributable is present - a missing
# MSVCP140.dll/VCRUNTIME140_1.dll makes LoadLibrary fail with "The specified
# module could not be found" and RetroArch just reports a broken core. Link the
# CRT statically instead. Has to be set before any target is created, and the
# prebuilt dependencies have to match (see scripts/build-deps-windows.bat).
if(MSVC AND ENABLE_LIBRETRO)
	# CMAKE_MSVC_RUNTIME_LIBRARY is only honoured under CMP0091 NEW, and a
	# bundled library asking for an older CMake would otherwise reset that
	# policy for its own subdirectory and quietly stay on /MD.
	set(CMAKE_POLICY_DEFAULT_CMP0091 NEW)
	set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# Dependencies that the distribution does not package, or packages too old, can
# be built here rather than by running pcee2-libretro/scripts/build-deps-*.sh
# first (issue
# #17). Has to run before SearchForStuff, which is where find_package() looks
# for them.
option(PCEE2_BUILD_DEPS "Build the from-source dependencies as part of this configure" OFF)
option(PCEE2_SDL_STATIC "With PCEE2_BUILD_DEPS, link SDL3 statically into the core" ON)
option(PCEE2_BUILD_PNG_ZSTD "With PCEE2_BUILD_DEPS, build libpng and zstd too" OFF)
option(PCEE2_BUILD_JPEG "With PCEE2_BUILD_DEPS, build libjpeg-turbo too" OFF)
option(PCEE2_BUILD_LIBRETRO "With PCEE2_BUILD_LIBRETRO, build for libretro" ON)
if(PCEE2_BUILD_DEPS)
	include(BuildDependencies)
endif()

include(SearchForStuff)

# Must be done after SearchForStuff
get_git_version_info()
# pcee2: name the upstream PCSX2 release the emulation code is merged up to,
# not pcee2's own tag - that is the version whose bin/resources this core wants.
include(Pcee2UpstreamVersion)
apply_pcee2_upstream_version()
write_svnrev_h()

# make common
add_subdirectory(common)

# make pcsx2
add_subdirectory(pcsx2)

if(ENABLE_QT_UI)
	add_subdirectory(pcsx2-qt)
endif()

# Updater is Windows only for now.
if (WIN32)
	add_subdirectory(updater)
endif()

# tests
if(ENABLE_TESTS)
	add_subdirectory(3rdparty/googletest)
	add_subdirectory(tests/ctest)
endif()

# gsrunner
if(ENABLE_GSRUNNER)
	add_subdirectory(pcsx2-gsrunner)
else()
	add_subdirectory(pcsx2-gsrunner EXCLUDE_FROM_ALL)
endif()

# libretro core
if(ENABLE_LIBRETRO)
	add_subdirectory(pcee2-libretro)
endif()

#-------------------------------------------------------------------------------
if(NOT IS_SUPPORTED_COMPILER)
	message(WARNING "
*************** UNSUPPORTED CONFIGURATION ***************
You are not compiling PCSX2 with a supported compiler.
It may not even build successfully.
PCSX2 only supports the Clang and MSVC compilers.
No support will be provided, continue at your own risk.
*********************************************************")
endif()

if(ARCH_ARM64)
	message(WARNING "
*************** UNSUPPORTED CONFIGURATION ***************
Apple Silicon support in PCSX2 is INCOMPLETE. There are
currently no EE/VU/IOP recompilers, and games will run
VERY slow. There is no date for completion yet, you
should set -DCMAKE_OSX_ARCHITECTURES=x86_64 for now,
unless you want to work on the recompilers.
*********************************************************")
endif()
