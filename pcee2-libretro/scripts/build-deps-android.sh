#!/usr/bin/env bash
# Builds the dependencies of the PCEE2 libretro core for Android, static and
# PIC, into a local prefix. Everything comes from source here: unlike the Linux
# jobs there is no distribution behind the NDK to take zlib, png, jpeg and the
# rest from.
#
# Usage: build-deps-android.sh <install-prefix>
# Environment:
#   ANDROID_NDK / ANDROID_NDK_HOME / ANDROID_NDK_ROOT - the NDK to build with
#   ANDROID_ABI      - arm64-v8a (default) or x86_64
#   ANDROID_API      - minimum platform level, default 24

set -e

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <install-prefix>"
	exit 1
fi

PREFIX=$(realpath "$1")
NPROCS="$(getconf _NPROCESSORS_ONLN)"

NDK="${ANDROID_NDK:-${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}}"
if [ -z "$NDK" ] || [ ! -f "$NDK/build/cmake/android.toolchain.cmake" ]; then
	echo "No usable NDK: set ANDROID_NDK to one containing build/cmake/android.toolchain.cmake"
	exit 1
fi

ABI="${ANDROID_ABI:-arm64-v8a}"
API="${ANDROID_API:-24}"

# c++_static, because several of these libraries end up inside one .so and a
# shared STL would have to be shipped alongside the core.
TOOLCHAIN=(
	"-DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake"
	"-DANDROID_ABI=$ABI"
	"-DANDROID_PLATFORM=android-$API"
	"-DANDROID_STL=c++_static"
	"-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
	"-DCMAKE_INSTALL_PREFIX=$PREFIX"
	"-DCMAKE_PREFIX_PATH=$PREFIX"
	"-DCMAKE_FIND_ROOT_PATH=$PREFIX"
	"-DCMAKE_BUILD_TYPE=Release"
)

# Shared with the Linux recipe and with deps/CMakeLists.txt, so a revision is
# bumped in one place. The glslang override is explained there.
. "$(cd "$(dirname "$0")" && pwd)/deps.versions"

# The one revision this recipe does not share. Android has been built against
# zlib 1.3.1 with nothing recorded about why, so it stays there rather than
# moving as a side effect of picking up the shared list.
ZLIB=v1.3.1

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

build() {
	# build <source-dir> <build-dir> [extra cmake args...]
	local src="$1" bld="$2"
	shift 2
	cmake -S "$src" -B "$bld" -G Ninja "${TOOLCHAIN[@]}" "$@"
	cmake --build "$bld" --parallel "$NPROCS"
	cmake --install "$bld"
}

clone https://github.com/madler/zlib zlib "$ZLIB"
build zlib zlib/build -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON \
	-DZLIB_BUILD_TESTING=OFF -DZLIB_BUILD_MINIZIP=OFF -DZLIB_BUILD_EXAMPLES=OFF

# zlib installs its static archive under a name CMake's FindZLIB does not look
# for on some versions; give it the conventional one as well (see the Windows
# block in build-deps-linux.sh for the same problem).
if [ -f "$PREFIX/lib/libzs.a" ] && [ ! -f "$PREFIX/lib/libz.a" ]; then
	cp "$PREFIX/lib/libzs.a" "$PREFIX/lib/libz.a"
fi

clone https://github.com/pnggroup/libpng libpng "$LIBPNG"
build libpng libpng/build -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF \
	-DPNG_TOOLS=OFF -DPNG_FRAMEWORK=OFF

clone https://github.com/libjpeg-turbo/libjpeg-turbo libjpeg-turbo "$JPEGTURBO"
build libjpeg-turbo libjpeg-turbo/build -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
	-DWITH_TURBOJPEG=OFF

clone https://github.com/facebook/zstd zstd "$ZSTD"
build zstd/build/cmake zstd/b -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON \
	-DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF

clone https://github.com/lz4/lz4 lz4 "$LZ4"
build lz4/build/cmake lz4/b -DBUILD_SHARED_LIBS=OFF -DLZ4_BUILD_CLI=OFF \
	-DLZ4_BUILD_LEGACY_LZ4C=OFF

clone https://github.com/webmproject/libwebp libwebp "$WEBP"
build libwebp libwebp/build -DBUILD_SHARED_LIBS=OFF \
	-DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
	-DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
	-DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF

# SDL3 is only here for the input and audio sources the core compiles; nothing
# in a libretro core opens an SDL window, so its Java side never comes up.
clone https://github.com/libsdl-org/SDL sdl3 "$SDL"
build sdl3 sdl3/build -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF

clone https://github.com/freetype/freetype freetype "$FREETYPE"
build freetype freetype/build -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_HARFBUZZ=ON \
	-DFT_DISABLE_BROTLI=ON -DFT_DISABLE_PNG=ON -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON

clone https://github.com/sammycage/plutovg plutovg "$PLUTOVG"
build plutovg plutovg/build -DBUILD_SHARED_LIBS=OFF -DPLUTOVG_BUILD_EXAMPLES=OFF

clone https://github.com/sammycage/plutosvg plutosvg "$PLUTOSVG"
build plutosvg plutosvg/build -DBUILD_SHARED_LIBS=OFF -DPLUTOSVG_ENABLE_FREETYPE=ON \
	-DPLUTOSVG_BUILD_EXAMPLES=OFF

clone https://github.com/biojppm/rapidyaml rapidyaml "$RAPIDYAML"
build rapidyaml rapidyaml/build -DBUILD_SHARED_LIBS=OFF

# libpcap headers only: DEV9 compiles against them but loads the library at
# runtime, and no Android device has one to load.
clone https://github.com/the-tcpdump-group/libpcap libpcap libpcap-1.10.5
mkdir -p "$PREFIX/include/pcap"
cp libpcap/pcap.h libpcap/pcap-bpf.h libpcap/pcap-namedb.h "$PREFIX/include/"
cp libpcap/pcap/*.h "$PREFIX/include/pcap/"

clone https://github.com/google/shaderc shaderc "$SHADERC"
(cd shaderc && python3 utils/git-sync-deps)
if [ "$(git -C shaderc/third_party/glslang rev-parse HEAD)" != "$GLSLANG" ]; then
	git -C shaderc/third_party/glslang fetch --depth 1 origin "$GLSLANG"
	git -C shaderc/third_party/glslang checkout --detach FETCH_HEAD
fi
cmake -S shaderc -B shaderc/b -G Ninja "${TOOLCHAIN[@]}" \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON
cmake --build shaderc/b --parallel "$NPROCS" --target shaderc_combined
mkdir -p "$PREFIX/lib" "$PREFIX/include"
cp shaderc/b/libshaderc/libshaderc_combined.a "$PREFIX/lib/"
cp -r shaderc/libshaderc/include/shaderc "$PREFIX/include/"

echo "Android ($ABI, API $API) dependencies installed to $PREFIX"
