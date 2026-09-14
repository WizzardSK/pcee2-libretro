#-------------------------------------------------------------------------------
#                       Search all libraries on the system
#-------------------------------------------------------------------------------
find_package(Git)

# Require threads on all OSes.
find_package(Threads REQUIRED)

# Dependency libraries.
# On macOS, Mono.framework contains an ancient version of libpng.  We don't want that.
# Avoid it by telling cmake to avoid finding frameworks while we search for libpng.
set(FIND_FRAMEWORK_BACKUP ${CMAKE_FIND_FRAMEWORK})
set(CMAKE_FIND_FRAMEWORK NEVER)
# Minimum libpng is 1.6.40 by default; the MinGW cross-build (libretro CI)
# only has MXE's 1.6.37, so PCSX2_PNG_MIN_VERSION lets that job relax it.
if(DEFINED ENV{PCSX2_PNG_MIN_VERSION})
	set(PCSX2_PNG_MIN_VERSION $ENV{PCSX2_PNG_MIN_VERSION})
else()
	set(PCSX2_PNG_MIN_VERSION 1.6.40)
endif()
find_package(PNG ${PCSX2_PNG_MIN_VERSION} REQUIRED)
find_package(JPEG REQUIRED) # No version because flatpak uses libjpeg-turbo.
find_package(ZLIB REQUIRED) # v1.3, but Mac uses the SDK version.
find_package(Zstd 1.5.5 REQUIRED)
find_package(LZ4 REQUIRED)
find_package(WebP REQUIRED) # v1.3.2, spews an error on Linux because no pkg-config.
# libwebp >= 1.3 splits SharpYUV into its own static library, which the config
# file does not carry, so a static webp has to be given it by hand. The MinGW
# cross-build and Android are known to link one, so there it has to be found;
# anywhere else it is only present when libwebp came from the deps tree rather
# than the distribution, whose shared libwebp carries SharpYUV itself.
if((WIN32 AND NOT MSVC) OR ANDROID)
	find_library(SHARPYUV_LIBRARY NAMES sharpyuv REQUIRED)
else()
	# Static archive only, and only if there is one: a distribution's shared
	# libwebp carries SharpYUV itself, and linking its shared companion would
	# just put another SONAME in the core for nothing.
	find_library(SHARPYUV_LIBRARY NAMES libsharpyuv.a sharpyuv.lib)

	# A cross-compile confines find_library to the sysroot, so it can miss the
	# deps tree even when the deps tree is exactly where libwebp came from
	# (webOS). Fall back to it -- but only when it is genuinely there, which is
	# only when this build put it there. PCEE2_BUILD_DEPS runs at configure
	# time, before this file, so by now the answer is settled.
	if(NOT SHARPYUV_LIBRARY AND EXISTS "${CMAKE_BINARY_DIR}/deps/lib/libsharpyuv.a")
		set(SHARPYUV_LIBRARY "${CMAKE_BINARY_DIR}/deps/lib/libsharpyuv.a")
	endif()
endif()
find_package(SDL3 3.2.6 REQUIRED)
find_package(Freetype 2.10 REQUIRED) # 2.10 is the first with COLRv0 support, which we need for rendering emoji
find_package(plutovg 1.1.0 REQUIRED)
find_package(plutosvg 0.0.7 REQUIRED)
find_package(ryml REQUIRED)
if (WIN32)
	find_package(DirectX-Headers 1.618.1 REQUIRED)
endif()

if(USE_VULKAN)
	find_package(Shaderc REQUIRED)
endif()

# Platform-specific dependencies.
if (WIN32)
	# D3D12MemAlloc needs a d3d12.h newer than the one MinGW ships (it uses
	# D3D12_HEAP_FLAG_HARDWARE_PROTECTED and friends), and WinPixEventRuntime is
	# an MSVC import library. The D3D renderers are skipped on MinGW anyway - see
	# PCSX2_DISABLE_D3D in pcsx2/CMakeLists.txt - so don't build either there.
	#
	# The d3d12memalloc directory is lowercase on disk; spelling it D3D12MemAlloc
	# only works on a case-insensitive filesystem (i.e. when building on Windows
	# itself), and the MinGW cross-build runs on Linux.
	if (MSVC)
		add_subdirectory(3rdparty/d3d12memalloc EXCLUDE_FROM_ALL)
		add_subdirectory(3rdparty/winpixeventruntime EXCLUDE_FROM_ALL)
	endif()
	add_subdirectory(3rdparty/winwil EXCLUDE_FROM_ALL)
	set(FFMPEG_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/ffmpeg/include")
	find_package(Vtune)
elseif(ANDROID OR APPLE_EMBEDDED)
	# Everything above comes from the prefix built by
	# pcee2-libretro/scripts/build-deps-android.sh, or build-deps-macos.sh with
	# APPLE_PLATFORM set to ios or tvos. What is missing here is missing from
	# the platform, and the two have the same list: no libcurl (the downloader
	# is compiled out), no libpcap (DEV9's network adapters use the headers
	# in-tree and load the library at runtime, which neither an Android device
	# nor an iPhone has), no fontconfig, X11, Wayland, dbus or udev, and no
	# VTune. macOS is not in here - its SDK carries curl and pcap, so it goes
	# through the branch below with everything else.
	#
	# FFmpeg is loaded at runtime everywhere but Windows, so only its headers
	# are needed to build; use the bundled ones.
	set(FFMPEG_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/ffmpeg/include")
	# DEV9 dlopen()s libpcap, so its headers are all that has to be present -
	# the deps prefix carries a copy of them.
	find_path(PCAP_INCLUDE_DIR NAMES pcap.h REQUIRED)
else()
	find_package(CURL REQUIRED)
	find_package(PCAP REQUIRED)
	find_package(Vtune)

	# Use bundled ffmpeg v4.x.x headers if we can't locate it in the system.
	# We'll try to load it dynamically at runtime.
	find_package(FFMPEG COMPONENTS avcodec avformat avutil swresample swscale)
	if(NOT FFMPEG_FOUND)
		message(WARNING "FFmpeg not found, using bundled headers.")
		set(FFMPEG_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/ffmpeg/include")
	endif()

	## Use CheckLib package to find module
	include(CheckLib)

	if(UNIX AND NOT APPLE)
		find_package(Fontconfig REQUIRED)
		if(LINUX)
			check_lib(LIBUDEV libudev libudev.h)
		endif()

		if(X11_API)
			find_package(X11 REQUIRED)
			if (NOT X11_Xrandr_FOUND)
				message(FATAL_ERROR "XRandR extension is required")
			endif()
		endif()

		if(WAYLAND_API)
			find_package(ECM REQUIRED NO_MODULE)
			list(APPEND CMAKE_MODULE_PATH "${ECM_MODULE_PATH}")
			find_package(Wayland REQUIRED Egl)
		endif()

		if(USE_BACKTRACE)
			find_package(Libbacktrace REQUIRED)
		endif()

		find_package(PkgConfig REQUIRED)
		pkg_check_modules(DBUS REQUIRED dbus-1)
	endif()
endif()

set(CMAKE_FIND_FRAMEWORK ${FIND_FRAMEWORK_BACKUP})

add_subdirectory(3rdparty/fast_float EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/lzma EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/libchdr EXCLUDE_FROM_ALL)
disable_compiler_warnings_for_target(libchdr)
add_subdirectory(3rdparty/soundtouch EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/simpleini EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/imgui EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/cpuinfo EXCLUDE_FROM_ALL)
disable_compiler_warnings_for_target(cpuinfo)
add_subdirectory(3rdparty/libzip EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/rcheevos EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/rapidjson EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/discord-rpc EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/freesurround EXCLUDE_FROM_ALL)

if(USE_OPENGL)
	add_subdirectory(3rdparty/glad EXCLUDE_FROM_ALL)
endif()

if(USE_VULKAN)
	add_subdirectory(3rdparty/vulkan EXCLUDE_FROM_ALL)
endif()

add_subdirectory(3rdparty/cubeb EXCLUDE_FROM_ALL)
disable_compiler_warnings_for_target(cubeb)
disable_compiler_warnings_for_target(speex)

# Find the Qt components that we need.
if(ENABLE_QT_UI)
	find_package(Qt6 6.10.1 COMPONENTS CoreTools Core GuiTools Gui WidgetsTools Widgets LinguistTools REQUIRED)

	if(NOT WIN32 AND NOT APPLE)
		if (Qt6_VERSION VERSION_GREATER_EQUAL 6.10.0)
			find_package(Qt6 COMPONENTS CorePrivate GuiPrivate WidgetsPrivate REQUIRED)
		endif()
	endif()

	# The docking system for the debugger.
	find_package(KDDockWidgets-qt6 2.3.0 REQUIRED)
endif()

if(WIN32)
	add_subdirectory(3rdparty/rainterface EXCLUDE_FROM_ALL)
endif()

# Demangler for the debugger.
add_subdirectory(3rdparty/demangler EXCLUDE_FROM_ALL)

# Symbol table parser.
add_subdirectory(3rdparty/ccc EXCLUDE_FROM_ALL)

# Architecture-specific.
if(ARCH_X86)
	add_subdirectory(3rdparty/zydis EXCLUDE_FROM_ALL)
elseif(ARCH_ARM64)
	add_subdirectory(3rdparty/vixl EXCLUDE_FROM_ALL)
endif()

# Prevent fmt from being built with exceptions, or being thrown at call sites.
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DFMT_USE_EXCEPTIONS=0 -DFMT_USE_RTTI=0")
add_subdirectory(3rdparty/fmt EXCLUDE_FROM_ALL)

# Deliberately at the end. We don't want to set the flag on third-party projects.
if(MSVC)
	# Don't warn about "deprecated" POSIX functions.
	add_definitions("-D_CRT_NONSTDC_NO_WARNINGS" "-D_CRT_SECURE_NO_WARNINGS" "-DCRT_SECURE_NO_DEPRECATE")
endif()
