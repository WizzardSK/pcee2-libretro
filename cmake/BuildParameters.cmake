# Extra preprocessor definitions that will be added to all pcsx2 builds
set(PCSX2_DEFS "")

include(GNUInstallDirs)

#-------------------------------------------------------------------------------
# Misc option
#-------------------------------------------------------------------------------
option(ENABLE_TESTS "Enables building the unit tests" ON)
option(ENABLE_QT_UI "Enables building the PCSX2 Qt interface." ON)
option(ENABLE_GSRUNNER "Enables building the GSRunner by default.  It can still be built with `make pcsx2-gsrunner` otherwise." OFF)
option(ENABLE_LIBRETRO "Enables building the libretro core." OFF)
option(SHADERC_STATIC "Link shaderc statically (SHADERC_LIBRARY must point at shaderc_combined) instead of loading it at runtime." OFF)
option(LTO_PCSX2_CORE "Enable LTO/IPO/LTCG on the subset of pcsx2 that benefits most from it but not anything else")
option(USE_VTUNE "Plug VTUNE to profile GS JIT.")
option(PACKAGE_MODE "Use this option to ease packaging of PCSX2 (developer/distribution option)")
option(BUNDLE_EMOJI_FONT "Bundles Noto Color Emoji for systems whose system emoji font isn't usable by freetype" ON)
option(POSITION_INDEPENDENT_CODE "Generate position-independent code. It is recommended that you leave this on." ON)

# iOS and tvOS are Apple but not macOS, and the difference decides quite a lot
# below: no AppKit, no IOKit, no optical drive, no desktop session. CMake tells
# them apart by system name - APPLE is true for all of them.
if(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin")
	set(APPLE_EMBEDDED TRUE)
else()
	set(APPLE_EMBEDDED FALSE)
endif()

# webOS is a Linux and CMAKE_SYSTEM_NAME says so, but its buildroot is as bare
# as Android's: EGL and GLES, no desktop GL, and none of the desktop session
# libraries. What gives it away is the SDK's compiler triple
# (aarch64-webos-linux-gnu); -DWEBOS=ON also works for anyone driving the build
# by hand.
if(NOT WEBOS AND CMAKE_CXX_COMPILER MATCHES "webos")
	set(WEBOS TRUE)
endif()

#-------------------------------------------------------------------------------
# Graphical option
#-------------------------------------------------------------------------------
if(NOT (WIN32 AND ("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "arm64" OR "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "ARM64" OR "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "aarch64")))
	if(NOT APPLE)
		option(USE_OPENGL "Enable OpenGL GS renderer" ON)
	endif()
	option(USE_VULKAN "Enable Vulkan GS renderer" ON)
endif()

#-------------------------------------------------------------------------------
# Path and lib option
#-------------------------------------------------------------------------------
if(ANDROID OR WEBOS)
	# None of the desktop display or diagnostic stacks exist on either: no X
	# server, no Wayland compositor, no session bus, no libbacktrace.
	set(ENABLE_SETCAP OFF)
	set(X11_API OFF)
	set(WAYLAND_API OFF)
	set(USE_BACKTRACE OFF)
	if(ANDROID)
		# The core renders through the frontend's Vulkan context, so the GL
		# renderer - which would want an EGL surface of its own - is off as
		# well. webOS keeps it: there is no Vulkan loader on the device, and
		# GLES arrives through the frontend the same way.
		set(USE_OPENGL OFF)
	endif()
elseif(UNIX AND NOT APPLE)
	option(ENABLE_SETCAP "Enable networking capability for DEV9" OFF)
	option(X11_API "Enable X11 support" ON)
	option(WAYLAND_API "Enable Wayland support" ON)
	option(USE_BACKTRACE "Enable libbacktrace support" ON)
endif()

if(UNIX)
	option(USE_LINKED_FFMPEG "Links with ffmpeg instead of using dynamic loading" OFF)
endif()

if(APPLE)
	option(OSX_USE_DEFAULT_SEARCH_PATH "Don't prioritize system library paths" OFF)
	option(SKIP_POSTPROCESS_BUNDLE "Skip postprocessing bundle for redistributability" OFF)
endif()

#-------------------------------------------------------------------------------
# Compiler extra
#-------------------------------------------------------------------------------
option(USE_ASAN "Enable address sanitizer")

#-------------------------------------------------------------------------------
# if no build type is set, use Devel as default
# Note without the CMAKE_BUILD_TYPE options the value is still defined to ""
# Ensure that the value set by the User is correct to avoid some bad behavior later
#-------------------------------------------------------------------------------
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug|Devel|MinSizeRel|RelWithDebInfo|Release")
	set(CMAKE_BUILD_TYPE Devel)
	message(STATUS "BuildType set to ${CMAKE_BUILD_TYPE} by default")
endif()
# Add Devel build type
set(CMAKE_C_FLAGS_DEVEL "${CMAKE_C_FLAGS_RELWITHDEBINFO}"
	CACHE STRING "Flags used by the C compiler during development builds" FORCE)
set(CMAKE_CXX_FLAGS_DEVEL "${CMAKE_CXX_FLAGS_RELWITHDEBINFO}"
	CACHE STRING "Flags used by the C++ compiler during development builds" FORCE)
set(CMAKE_LINKER_FLAGS_DEVEL "${CMAKE_LINKER_FLAGS_RELWITHDEBINFO}"
	CACHE STRING "Flags used for linking binaries during development builds" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS_DEVEL "${CMAKE_SHARED_LINKER_FLAGS_RELWITHDEBINFO}"
	CACHE STRING "Flags used for linking shared libraries during development builds" FORCE)
set(CMAKE_EXE_LINKER_FLAGS_DEVEL "${CMAKE_EXE_LINKER_FLAGS_RELWITHDEBINFO}"
	CACHE STRING "Flags used for linking executables during development builds" FORCE)
# Exclude Debug from the configurations we can import from
set(CMAKE_MAP_IMPORTED_CONFIG_DEVEL "RelWithDebInfo" "Release" "MinSizeRel" "None" "NoConfig" ""
	CACHE STRING "Configurations used when importing packages for development builds" FORCE)
if(CMAKE_CONFIGURATION_TYPES)
	list(INSERT CMAKE_CONFIGURATION_TYPES 0 Devel)
endif()
mark_as_advanced(CMAKE_C_FLAGS_DEVEL CMAKE_CXX_FLAGS_DEVEL CMAKE_LINKER_FLAGS_DEVEL CMAKE_SHARED_LINKER_FLAGS_DEVEL CMAKE_EXE_LINKER_FLAGS_DEVEL CMAKE_MAP_IMPORTED_CONFIG_DEVEL)

#-------------------------------------------------------------------------------
# Select the architecture
#-------------------------------------------------------------------------------
# Every build but Android's is a native one, where the host processor is also
# the target. Android cross-compiles, so there the toolchain's target processor
# is what decides which recompiler gets built.
if(CMAKE_CROSSCOMPILING)
	set(PCSX2_TARGET_PROCESSOR "${CMAKE_SYSTEM_PROCESSOR}")
else()
	set(PCSX2_TARGET_PROCESSOR "${CMAKE_HOST_SYSTEM_PROCESSOR}")
endif()

if("${PCSX2_TARGET_PROCESSOR}" STREQUAL "x86_64" OR "${PCSX2_TARGET_PROCESSOR}" STREQUAL "amd64" OR
   "${PCSX2_TARGET_PROCESSOR}" STREQUAL "AMD64" OR "${CMAKE_OSX_ARCHITECTURES}" STREQUAL "x86_64")
	# Multi-ISA only exists on x86.
	option(DISABLE_ADVANCE_SIMD "Disable advance use of SIMD (SSE2+ & AVX)" OFF)

	list(APPEND PCSX2_DEFS _M_X86=1)
	set(ARCH_X86 TRUE)
	if(DISABLE_ADVANCE_SIMD)
		message(STATUS "Building for x86-64 (Multi-ISA).")
	else()
		message(STATUS "Building for x86-64.")
	endif()

	if(MSVC)
		# SSE4.1 is not set by MSVC, it uses _M_SSE instead.
		list(APPEND PCSX2_DEFS __SSE4_1__=1)

		if(USE_CLANG_CL)
			# clang-cl => need to explicitly enable SSE4.1.
			add_compile_options("-msse4.1")
		endif()
	else()
		# Multi-ISA => SSE4, otherwise native.
		if (DISABLE_ADVANCE_SIMD OR ANDROID)
			# -march=native means the build machine on a cross-compile, which is
			# not what an Android x86_64 core will run on.
			add_compile_options("-msse" "-msse2" "-msse4.1" "-mfxsr")
		else()
			# Can't use march=native on Apple Silicon.
			if(NOT APPLE OR "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "x86_64")
				add_compile_options("-march=native")
			endif()
		endif()
	endif()
elseif("${PCSX2_TARGET_PROCESSOR}" STREQUAL "arm64" OR "${PCSX2_TARGET_PROCESSOR}" STREQUAL "aarch64" OR
       "${CMAKE_OSX_ARCHITECTURES}" STREQUAL "arm64")
	message(STATUS "Building for ARM64.")
	set(ARCH_ARM64 TRUE)
	if(APPLE)
		# Min spec is an M1
		add_compile_options("-march=armv8.4-a" "-mcpu=apple-m1")
	elseif(ANDROID)
		# armv8.0 is the floor for arm64-v8a: phones without the 8.1 atomics
		# are still out there, and the compiler would otherwise emit LSE
		# instructions that fault on them.
		add_compile_options("-march=armv8-a+crc")
	else()
		# Require atomic rmw instructions
		add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX>:-march=armv8.1-a>")
	endif()

	# If we're running on Linux, we need to detect the page/cache line size.
	# It could be a virtual machine with 4K pages, or 16K with Asahi.
	if(LINUX)
		if(CMAKE_CROSSCOMPILING)
			# Cannot execute target binaries during a cross compile.
			set(HOST_PAGE_SIZE 4096)
			set(HOST_CACHE_LINE_SIZE 64)
		else()
			detect_page_size()
			detect_cache_line_size()
		endif()

		list(APPEND PCSX2_DEFS OVERRIDE_HOST_PAGE_SIZE=${HOST_PAGE_SIZE})
		list(APPEND PCSX2_DEFS OVERRIDE_HOST_CACHE_LINE_SIZE=${HOST_CACHE_LINE_SIZE})
	endif()
	
	# Windows page/cache line size seems to match x68-64
	if(WIN32)
		list(APPEND PCSX2_DEFS OVERRIDE_HOST_PAGE_SIZE=0x1000)
		# Value of std::hardware_destructive_interference_size for ARM64 on MSVC toolset 14.40.33807
		list(APPEND PCSX2_DEFS OVERRIDE_HOST_CACHE_LINE_SIZE=64)
	endif()

	# Android is cross-compiled, so the probes above cannot run - they execute
	# what they build. Cortex-A cores report 64 byte cache lines; the ARM64
	# default of 128 is Apple's, and using it here only means every device logs
	# "Cache line size mismatch" and pads its shared structures twice as far
	# apart as it needs to. The page size is deliberately left alone: 16K page
	# devices exist and VMManager copes with a host page smaller than the built
	# one, not the other way around.
	if(ANDROID)
		list(APPEND PCSX2_DEFS OVERRIDE_HOST_CACHE_LINE_SIZE=64)
	endif()
else()
	message(FATAL_ERROR "Unsupported architecture: ${PCSX2_TARGET_PROCESSOR}")
endif()

# Require C++20.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(WIN32 AND NOT MSVC)
	# -std=c++20 makes mingw-w64's headers emit their FORCEINLINE helpers
	# (GetCurrentFiber, TpInitializeCallbackEnviron, the _Interlocked* family...)
	# with __gnu_inline__ semantics, i.e. an external definition in every
	# translation unit, and the link then drowns in thousands of "multiple
	# definition" errors. -std=gnu++20 gives them C++ inline semantics.
	set(CMAKE_CXX_EXTENSIONS ON)
	# mingw's headers declare their small helpers - GetCurrentFiber(),
	# NtCurrentTeb(), InterlockedExchangeSubtract(), the Tp* and SH* families -
	# as FORCEINLINE, which resolves to Pcsx2Defs.h's __forceinline; that one
	# deliberately omits the inline keyword (__forceinline_odr is the variant
	# that has it), so every translation unit emitted an external definition.
	# Defining it here covers the files that reach windows.h without going
	# through RedtapeWindows.h first.
	# Set through the flags rather than add_compile_definitions() so that it is
	# carried into every subdirectory and both languages - the 3rdparty C
	# libraries (libzip, glad) hit the same problem.
	# mingw declares these helpers extern before defining them, so in C the
	# inline definition counts as an external one and lands in every object -
	# hence the duplicates. static is rejected for the same reason ("declared
	# extern and later static"), so the definitions are made weak instead and
	# the linker keeps one. The escaped space keeps it a single -D argument.
	# mingw declares its one-line helpers - GetCurrentFiber(), NtCurrentTeb(),
	# the Tp* and SH* families - extern and then defines them as FORCEINLINE,
	# which lands on Pcsx2Defs.h's __forceinline; that macro leaves out the
	# inline keyword deliberately, so in C the definition is an external one and
	# every object carries a copy. Redefining FORCEINLINE does settle it, but
	# neither storage class works: static conflicts with the extern declaration
	# that precedes it, and weak is ignored for the same reason. The copies are
	# identical by construction, so let the linker keep one.
	string(APPEND CMAKE_EXE_LINKER_FLAGS " -Wl,--allow-multiple-definition")
	string(APPEND CMAKE_SHARED_LINKER_FLAGS " -Wl,--allow-multiple-definition")
	string(APPEND CMAKE_MODULE_LINKER_FLAGS " -Wl,--allow-multiple-definition")
	message(STATUS "MinGW: --allow-multiple-definition, C++ extensions on")
endif()

if(MSVC AND NOT USE_CLANG_CL)
	add_compile_options(
		"$<$<COMPILE_LANGUAGE:CXX>:/Zc:externConstexpr>"
		"$<$<COMPILE_LANGUAGE:CXX>:/Zc:__cplusplus>"
		"$<$<COMPILE_LANGUAGE:CXX>:/permissive->"
		"$<$<COMPILE_LANGUAGE:CXX>:/Zc:preprocessor>"
		"/Zo"
		"/utf-8"
	)
endif()

if(MSVC)
	# Disable Exceptions
	string(REPLACE "/EHsc" "" CMAKE_CXX_FLAGS ${CMAKE_CXX_FLAGS})
else()
	add_compile_options(-pipe -fvisibility=hidden -pthread)
	add_compile_options(
		"$<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>"
	)
endif()

set(CONFIG_REL_NO_DEB $<OR:$<CONFIG:Release>,$<CONFIG:MinSizeRel>>)
set(CONFIG_ANY_REL $<OR:$<CONFIG:Release>,$<CONFIG:MinSizeRel>,$<CONFIG:RelWithDebInfo>>)

if(WIN32)
	add_compile_definitions(
		$<$<CONFIG:Debug>:_ITERATOR_DEBUG_LEVEL=2>
		$<$<CONFIG:Devel>:_ITERATOR_DEBUG_LEVEL=1>
		$<${CONFIG_ANY_REL}:_ITERATOR_DEBUG_LEVEL=0>
		_HAS_EXCEPTIONS=0
	)
	list(APPEND PCSX2_DEFS
		_CRT_NONSTDC_NO_WARNINGS
		_CRT_SECURE_NO_WARNINGS
		CRT_SECURE_NO_DEPRECATE
		_SCL_SECURE_NO_WARNINGS
		_UNICODE
		UNICODE
	)
else()
	# Assume everything else is POSIX.
	list(APPEND PCSX2_DEFS
		__POSIX__
	)
endif()

# Enable debug information in release builds for Linux.
# Makes the backtrace actually meaningful.
if(LINUX)
	add_compile_options($<$<CONFIG:Release>:-g1>)
endif()

if(MSVC)
	# Enable PDB generation in release builds
	add_compile_options(
		$<$<AND:${CONFIG_REL_NO_DEB},$<COMPILE_LANGUAGE:C,CXX,ASM_MASM>>:/Zi>
	)
	add_compile_options(
		$<$<AND:${CONFIG_REL_NO_DEB},$<COMPILE_LANGUAGE:ASM_MARMASM>>:-g>
	)
	add_link_options(
		$<${CONFIG_REL_NO_DEB}:/DEBUG>
		$<${CONFIG_REL_NO_DEB}:/OPT:REF>
		$<${CONFIG_REL_NO_DEB}:/OPT:ICF>
	)
endif()

if(PACKAGE_MODE)
	file(RELATIVE_PATH relative_datadir ${CMAKE_INSTALL_FULL_BINDIR} ${CMAKE_INSTALL_FULL_DATADIR}/PCSX2)

	# Compile all source codes with those defines
	list(APPEND PCSX2_DEFS
		PCSX2_APP_DATADIR="${relative_datadir}")
endif()


if(USE_VTUNE)
	list(APPEND PCSX2_DEFS ENABLE_VTUNE)
endif()

if(USE_OPENGL)
	list(APPEND PCSX2_DEFS ENABLE_OPENGL)
endif()

if(USE_VULKAN)
	list(APPEND PCSX2_DEFS ENABLE_VULKAN)
endif()

if(WEBOS)
	list(APPEND PCSX2_DEFS WEBOS)
endif()

if(X11_API)
	list(APPEND PCSX2_DEFS X11_API)
endif()

if(WAYLAND_API)
	list(APPEND PCSX2_DEFS WAYLAND_API)
endif()

# -Wno-attributes: "always_inline function might not be inlinable" <= real spam (thousand of warnings!!!)
# -Wno-missing-field-initializers: standard allow to init only the begin of struct/array in static init. Just a silly warning.
# -Wno-unused-function: warn for function not used in release build

if (MSVC)
	set(DEFAULT_WARNINGS)
else()
	set(DEFAULT_WARNINGS -Wall -Wextra -Wno-unused-function -Wno-unused-parameter -Wno-missing-field-initializers)
endif()
if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
	list(APPEND DEFAULT_WARNINGS -Wno-attributes)
endif()

if (USE_PGO_GENERATE OR USE_PGO_OPTIMIZE)
	add_compile_options("-fprofile-dir=${CMAKE_SOURCE_DIR}/profile")
endif()

if (USE_PGO_GENERATE)
	add_compile_options(-fprofile-generate)
endif()

if(USE_PGO_OPTIMIZE)
	add_compile_options(-fprofile-use)
endif()

list(APPEND PCSX2_DEFS
	"$<$<CONFIG:Debug>:PCSX2_DEVBUILD;PCSX2_DEBUG;_DEBUG>"
	"$<$<CONFIG:Devel>:PCSX2_DEVBUILD;_DEVEL>")

if (USE_ASAN)
	add_compile_options(-fsanitize=address)
	add_link_options(-fsanitize=address)
	list(APPEND PCSX2_DEFS ASAN_WORKAROUND)
endif()

if(USE_CLANG AND TIMETRACE)
	add_compile_options(-ftime-trace)
endif()

set(PCSX2_WARNINGS ${DEFAULT_WARNINGS})

if(POSITION_INDEPENDENT_CODE)
	# Make sure position-independent code is enabled properly.
	# Without this check, on some platforms (e.g. Fedora 43) the right flags
	# won't be passed to the linker, resulting in a broken build when link time
	# optimization is enabled (even with a cmake version >= 3.14).
	if(NOT MSVC)
		include(CheckPIESupported)
		check_pie_supported(OUTPUT_VARIABLE PIE_SUPPORTED_OUTPUT LANGUAGES C CXX)

		if((NOT CMAKE_C_LINK_PIE_SUPPORTED) OR (NOT CMAKE_CXX_LINK_PIE_SUPPORTED))
			message(WARNING
				"The POSITION_INDEPENDENT_CODE option is enabled but is not "
				"supported at link time:\n${PIE_SUPPORTED_OUTPUT}")
		endif()
	endif()

	set(CMAKE_POSITION_INDEPENDENT_CODE ON)
else()
	if(CMAKE_INTERPROCEDURAL_OPTIMIZATION)
		message(WARNING
			"The CMAKE_INTERPROCEDURAL_OPTIMIZATION option is enabled but the "
			"POSITION_INDEPENDENT_CODE option is disabled. This has been found "
			"to result in broken builds on certain platforms.")
	endif()

	set(CMAKE_POSITION_INDEPENDENT_CODE OFF)
endif()

#-------------------------------------------------------------------------------
# MacOS-specific things
#-------------------------------------------------------------------------------

if(NOT CMAKE_GENERATOR MATCHES "Xcode")
	# Assume Xcode builds aren't being used for distribution
	# Helpful because Xcode builds don't build multiple metallibs for different macOS versions
	# Also helpful because Xcode's interactive shader debugger requires apps be built for the latest macOS
	set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0)
endif()

# CMake defaults the suffix for modules to .so on macOS but wx tells us that the
# extension is .dylib (so that's what we search for)
if(APPLE)
	set(CMAKE_SHARED_MODULE_SUFFIX ".dylib")
endif()

if(CMAKE_SYSTEM_NAME MATCHES "Darwin")
	if(NOT OSX_USE_DEFAULT_SEARCH_PATH)
		# Hack up the path to prioritize the path to built-in OS libraries to
		# increase the chance of not depending on a bunch of copies of them
		# installed by MacPorts, Fink, Homebrew, etc, and ending up copying
		# them into the bundle.  Since we depend on libraries which are not
		# part of OS X (wx, etc.), however, don't remove the default path
		# entirely.  This is still kinda evil, since it defeats the user's
		# path settings...
		# See http://www.cmake.org/cmake/help/v3.0/command/find_program.html
		list(APPEND CMAKE_PREFIX_PATH "/usr")
	endif()

	add_link_options(-Wl,-dead_strip,-dead_strip_dylibs)
endif()
