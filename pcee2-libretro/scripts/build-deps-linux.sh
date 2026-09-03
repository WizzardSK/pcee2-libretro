#!/usr/bin/env bash
# Builds the dependencies that aren't packaged by Ubuntu into a local prefix
# (static, PIC), for building the PCEE2 libretro core.
# Usage: build-deps-linux.sh <install-prefix>

set -e

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <install-prefix>"
	exit 1
fi

PREFIX=$(realpath "$1")
NPROCS="$(getconf _NPROCESSORS_ONLN)"

# Allow a cross-compiling CMake wrapper (e.g. the MXE x86_64-w64-mingw32.static-cmake
# used by the libretro Windows job) to be substituted for the host cmake. HOST is
# the autoconf target triple for the non-CMake deps (libbacktrace); empty = native.
CMAKE="${CMAKE:-cmake}"
HOST="${HOST:-}"

# Revisions live next door, so deps/CMakeLists.txt can build the same ones.
. "$(cd "$(dirname "$0")" && pwd)/deps.versions"

mkdir -p deps-build
cd deps-build

clone() {
	[ -d "$2" ] && return 0
	# GitHub answers a rate-limited anonymous fetch with something that is not a
	# git response, and git then falls back to asking for a username - on a
	# runner that is "could not read Username ... No such device or address" and
	# the build stops before it has fetched anything (buildbot, 2 Sep 2026).
	# Never prompt, and give it a couple of tries before calling it a failure.
	local attempt
	for attempt in 1 2 3; do
		if GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true \
			git clone --depth 1 --branch "$3" --recursive "$1" "$2"; then
			return 0
		fi
		rm -rf "$2"
		echo "clone of $1 failed (attempt $attempt), retrying in $((attempt * 15))s" >&2
		sleep $((attempt * 15))
	done
	echo "FATAL: could not clone $1" >&2
	return 1
}

# Set PCEE2_SDL_STATIC=1 to build SDL3 as a static lib instead of shared. With a
# static-only install, SDL3's CMake config makes SDL3::SDL3 (what the core links)
# resolve to the static archive, so the resulting core is self-contained and needs
# no libSDL3.so.0 at runtime — useful for minimal/uncommon ARM distros.
if [ "${PCEE2_SDL_STATIC:-0}" = "1" ]; then
	SDL_LIB_FLAGS="-DSDL_SHARED=OFF -DSDL_STATIC=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON"
else
	SDL_LIB_FLAGS="-DSDL_SHARED=ON -DSDL_STATIC=OFF"
fi
clone https://github.com/libsdl-org/SDL sdl3 "$SDL"
"$CMAKE" -S sdl3 -B sdl3/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" $SDL_LIB_FLAGS \
	-DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
"$CMAKE" --build sdl3/build --parallel "$NPROCS"
"$CMAKE" --install sdl3/build

# FreeType: the libretro build image ships an old FreeType (e.g. 2.8.1), but
# pcee2 needs >= 2.10 (COLRv0 emoji) and plutosvg's FreeType integration needs
# the OT-SVG API from >= 2.12. Build a current one into the prefix so both
# plutosvg and the core find it (via CMAKE_PREFIX_PATH=$CI_PROJECT_DIR/deps).
clone https://github.com/freetype/freetype freetype "$FREETYPE"
"$CMAKE" -S freetype -B freetype/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON \
	-DFT_DISABLE_PNG=ON -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON
"$CMAKE" --build freetype/build --parallel "$NPROCS"
"$CMAKE" --install freetype/build

clone https://github.com/sammycage/plutovg plutovg "$PLUTOVG"
"$CMAKE" -S plutovg -B plutovg/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DBUILD_SHARED_LIBS=OFF -DPLUTOVG_BUILD_EXAMPLES=OFF
"$CMAKE" --build plutovg/build --parallel "$NPROCS"
"$CMAKE" --install plutovg/build

clone https://github.com/sammycage/plutosvg plutosvg "$PLUTOSVG"
"$CMAKE" -S plutosvg -B plutosvg/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" \
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF \
	-DPLUTOSVG_ENABLE_FREETYPE=ON -DPLUTOSVG_BUILD_EXAMPLES=OFF
"$CMAKE" --build plutosvg/build --parallel "$NPROCS"
"$CMAKE" --install plutosvg/build

clone https://github.com/biojppm/rapidyaml rapidyaml "$RAPIDYAML"
"$CMAKE" -S rapidyaml -B rapidyaml/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DBUILD_SHARED_LIBS=OFF
"$CMAKE" --build rapidyaml/build --parallel "$NPROCS"
"$CMAKE" --install rapidyaml/build

clone https://github.com/ianlancetaylor/libbacktrace libbacktrace "$LIBBACKTRACE"
(cd libbacktrace && ./configure --prefix="$PREFIX" --with-pic ${HOST:+--host="$HOST"} && make -j"$NPROCS" && make install)

# shaderc: static combined, linked straight into the core. Distro
# libshaderc_combined.a packages aren't actually self-contained (Ubuntu's
# expects the system glslang), so build the real thing from source. The glslang
# override that goes with it is explained in deps.versions.
clone https://github.com/google/shaderc shaderc "$SHADERC"
(cd shaderc && python3 utils/git-sync-deps)
# git-sync-deps has just put DEPS' revision in place; move it forward. Fetching
# the bare commit keeps this pinned rather than tracking whatever main is today.
if [ "$(git -C shaderc/third_party/glslang rev-parse HEAD)" != "$GLSLANG" ]; then
	git -C shaderc/third_party/glslang fetch --depth 1 origin "$GLSLANG"
	git -C shaderc/third_party/glslang checkout --detach FETCH_HEAD
fi
"$CMAKE" -S shaderc -B shaderc/b -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON
"$CMAKE" --build shaderc/b --parallel "$NPROCS" --target shaderc_combined
mkdir -p "$PREFIX/lib" "$PREFIX/include"
cp shaderc/b/libshaderc/libshaderc_combined.a "$PREFIX/lib/"
cp -r shaderc/libshaderc/include/shaderc "$PREFIX/include/"

# Some distros (notably Debian Bookworm, the glibc target for Raspberry Pi OS)
# ship libpng / libzstd a hair older than PCSX2's find_package() minimums
# (PNG >= 1.6.40, Zstd >= 1.5.5). Bookworm has 1.6.39 / 1.5.4. Build newer ones
# static into the prefix so they're found before the system copies and get
# embedded into the core (no runtime dependency on the Pi's older .so either).
# Set PCEE2_BUILD_PNG_ZSTD=1 to enable; off by default so the Ubuntu jobs, whose
# system libs already satisfy the minimums, keep using those.
if [ "${PCEE2_BUILD_PNG_ZSTD:-0}" = "1" ]; then
	clone https://github.com/pnggroup/libpng libpng "$LIBPNG_OPTIONAL"
	"$CMAKE" -S libpng -B libpng/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF
	"$CMAKE" --build libpng/build --parallel "$NPROCS"
	"$CMAKE" --install libpng/build

	clone https://github.com/facebook/zstd zstd "$ZSTD"
	"$CMAKE" -S zstd/build/cmake -B zstd/b -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON \
		-DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF
	"$CMAKE" --build zstd/b --parallel "$NPROCS"
	"$CMAKE" --install zstd/b
fi

# Ubuntu's libjpeg-turbo8-dev gives an SONAME of libjpeg.so.8, which only exists
# on Ubuntu and the Arch-family distros; Debian ships libjpeg62-turbo, i.e.
# libjpeg.so.62, and the core then fails to load outright. Build libjpeg-turbo
# static into the prefix so it ends up inside the core and no SONAME is baked in
# at all. Set PCEE2_BUILD_JPEG=1 to enable.
#The Windows cross build gets its libjpeg-turbo from the HOST block below, which
#has to build one regardless because MXE ships none, so skip this one there.
if [ "${PCEE2_BUILD_JPEG:-0}" = "1" ] && [ -z "$HOST" ]; then
	clone https://github.com/libjpeg-turbo/libjpeg-turbo libjpeg-turbo "$JPEGTURBO"
	"$CMAKE" -S libjpeg-turbo -B libjpeg-turbo/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF
	"$CMAKE" --build libjpeg-turbo/build --parallel "$NPROCS"
	"$CMAKE" --install libjpeg-turbo/build
fi

# Windows (MinGW) only: the libretro MXE image lacks the system libraries that
# the Linux jobs get from Ubuntu apt. ZLIB and PNG were assumed to come from MXE,
# but the cross-build's CMake configure fails with "Could NOT find ZLIB" and
# "Could NOT find PNG (Required is at least version 1.6.40)", so build those from
# source as well - same as build-deps-windows.bat does for the MSVC job.
# Guarded by HOST, which is only set for the Windows cross job, so the Linux
# x64/aarch64 jobs keep using their apt copies and don't pay for these builds.
if [ -n "$HOST" ]; then
	clone https://github.com/madler/zlib zlib "$ZLIB"
	"$CMAKE" -S zlib -B zlib/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON \
		-DZLIB_BUILD_TESTING=OFF -DZLIB_BUILD_MINIZIP=OFF
	"$CMAKE" --build zlib/build --parallel "$NPROCS"
	"$CMAKE" --install zlib/build

	# zlib 1.3.2 installs its static archive as libzs.a, but CMake's FindZLIB
	# only looks for z/zlib/zlibstatic - it then reports "Could NOT find ZLIB
	# (missing: ZLIB_LIBRARY) (found version 1.3.2)", and FindPNG fails with it
	# because it requires ZLIB. Provide the conventional name as well.
	if [ -f "$PREFIX/lib/libzs.a" ] && [ ! -f "$PREFIX/lib/libz.a" ]; then
		cp "$PREFIX/lib/libzs.a" "$PREFIX/lib/libz.a"
	fi

	# libpng needs the zlib we just installed, hence CMAKE_PREFIX_PATH.
	clone https://github.com/pnggroup/libpng libpng "$LIBPNG"
	"$CMAKE" -S libpng -B libpng/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" \
		-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF \
		-DPNG_FRAMEWORK=OFF
	"$CMAKE" --build libpng/build --parallel "$NPROCS"
	"$CMAKE" --install libpng/build

	# SearchForStuff.cmake does find_package(DirectX-Headers 1.618.1 REQUIRED)
	# on Windows targets; MXE does not ship it either.
	clone https://github.com/microsoft/DirectX-Headers DirectX-Headers "$DXHEADERS"
	"$CMAKE" -S DirectX-Headers -B DirectX-Headers/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DBUILD_SHARED_LIBS=OFF -DDXHEADERS_BUILD_TEST=OFF \
		-DDXHEADERS_BUILD_GOOGLE_TEST=OFF -DDXHEADERS_INSTALL=ON
	"$CMAKE" --build DirectX-Headers/build --parallel "$NPROCS"
	"$CMAKE" --install DirectX-Headers/build

	clone https://github.com/libjpeg-turbo/libjpeg-turbo libjpeg-turbo "$JPEGTURBO"
	"$CMAKE" -S libjpeg-turbo -B libjpeg-turbo/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_SIMD=OFF
	"$CMAKE" --build libjpeg-turbo/build --parallel "$NPROCS"
	"$CMAKE" --install libjpeg-turbo/build

	clone https://github.com/facebook/zstd zstd "$ZSTD"
	"$CMAKE" -S zstd/build/cmake -B zstd/build/cmake/b -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_PROGRAMS=OFF
	"$CMAKE" --build zstd/build/cmake/b --parallel "$NPROCS"
	"$CMAKE" --install zstd/build/cmake/b

	clone https://github.com/lz4/lz4 lz4 "$LZ4"
	"$CMAKE" -S lz4/build/cmake -B lz4/build/cmake/b -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DBUILD_SHARED_LIBS=OFF -DLZ4_BUILD_CLI=OFF -DLZ4_BUILD_LEGACY_LZ4C=OFF
	"$CMAKE" --build lz4/build/cmake/b --parallel "$NPROCS"
	"$CMAKE" --install lz4/build/cmake/b

	clone https://github.com/webmproject/libwebp libwebp "$WEBP"
	"$CMAKE" -S libwebp -B libwebp/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DBUILD_SHARED_LIBS=OFF \
		-DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
		-DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
		-DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF
	"$CMAKE" --build libwebp/build --parallel "$NPROCS"
	"$CMAKE" --install libwebp/build
fi

echo "Dependencies installed to $PREFIX"
