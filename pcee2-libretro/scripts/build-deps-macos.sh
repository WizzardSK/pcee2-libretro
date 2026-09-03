#!/usr/bin/env bash
# Builds the static dependencies for the PCEE2 libretro core into $1.
# Everything is static except MoltenVK (prebuilt, dlopen'd Vulkan
# driver), the only dylib — its release tarball is a universal binary, so it
# needs no slice of its own.
#
# The architecture follows $OSX_ARCH (default x86_64), which has to match the
# CMAKE_OSX_ARCHITECTURES the core is configured with: a static library of the
# wrong slice fails at link, not at configure.
set -e

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <install-prefix>"
	exit 1
fi

PREFIX=$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1")
mkdir -p "$PREFIX"
NPROCS="$(getconf _NPROCESSORS_ONLN)"
OSX_ARCH="${OSX_ARCH:-x86_64}"
export MACOSX_DEPLOYMENT_TARGET=11.0
echo "Building dependencies for $OSX_ARCH into $PREFIX"


# Revisions live in deps.versions, shared with the other platform scripts and
# with deps/CMakeLists.txt, so the paths cannot drift apart.
. "$(cd "$(dirname "$0")" && pwd)/deps.versions"

COMMON=(-DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$PREFIX" "-DCMAKE_PREFIX_PATH=$PREFIX"
	-DBUILD_SHARED_LIBS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "-DCMAKE_OSX_ARCHITECTURES=$OSX_ARCH" -G Ninja)

mkdir -p deps-build
cd deps-build

clone() {
	[ -d "$2" ] && return 0
	# See build-deps-linux.sh: a rate-limited anonymous fetch makes git ask for
	# a username, which on a runner is an immediate hard failure.
	local attempt
	for attempt in 1 2 3; do
		if GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true \
			git clone --depth 1 -b "$3" $4 "https://github.com/$1" "$2"; then
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
	local src="$1"; shift
	cmake -S "$src" -B "$src/b" "${COMMON[@]}" "$@"
	cmake --build "$src/b" --parallel "$NPROCS" --target install
}

clone pnggroup/libpng libpng "$LIBPNG"
build libpng -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_FRAMEWORK=OFF

clone libjpeg-turbo/libjpeg-turbo libjpeg-turbo "$JPEGTURBO"
build libjpeg-turbo -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_SIMD=OFF -DWITH_TURBOJPEG=OFF

clone webmproject/libwebp libwebp "$WEBP"
build libwebp -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
	-DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
	-DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF
# merge sharpyuv into libwebp so module-style find_package links cleanly
libtool -static -o "$PREFIX/lib/libwebp_merged.a" "$PREFIX/lib/libwebp.a" "$PREFIX/lib/libsharpyuv.a"
mv "$PREFIX/lib/libwebp_merged.a" "$PREFIX/lib/libwebp.a"

clone lz4/lz4 lz4 "$LZ4"
cmake -S lz4/build/cmake -B lz4/b "${COMMON[@]}" -DLZ4_BUILD_CLI=OFF -DLZ4_BUILD_LEGACY_LZ4C=OFF
cmake --build lz4/b --parallel "$NPROCS" --target install

clone facebook/zstd zstd "$ZSTD"
cmake -S zstd/build/cmake -B zstd/b "${COMMON[@]}" -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON \
	-DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF
cmake --build zstd/b --parallel "$NPROCS" --target install

clone freetype/freetype freetype "$FREETYPE"
build freetype -DFT_REQUIRE_ZLIB=TRUE -DFT_REQUIRE_PNG=TRUE -DFT_DISABLE_BZIP2=TRUE \
	-DFT_DISABLE_BROTLI=TRUE -DFT_DISABLE_HARFBUZZ=TRUE

clone libsdl-org/SDL SDL "$SDL"
build SDL -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF

clone sammycage/plutovg plutovg "$PLUTOVG"
build plutovg -DPLUTOVG_BUILD_EXAMPLES=OFF

clone sammycage/plutosvg plutosvg "$PLUTOSVG"
build plutosvg -DPLUTOSVG_ENABLE_FREETYPE=ON -DPLUTOSVG_BUILD_EXAMPLES=OFF

clone biojppm/rapidyaml rapidyaml "$RAPIDYAML" --recursive
build rapidyaml

# shaderc: static combined, linked straight into the core
clone google/shaderc shaderc "$SHADERC"
(cd shaderc && python3 utils/git-sync-deps)
# git-sync-deps has just put DEPS' revision in place; move it forward. The
# reason for the override is recorded in deps.versions.
if [ "$(git -C shaderc/third_party/glslang rev-parse HEAD)" != "$GLSLANG" ]; then
	git -C shaderc/third_party/glslang fetch --depth 1 origin "$GLSLANG"
	git -C shaderc/third_party/glslang checkout --detach FETCH_HEAD
fi
cmake -S shaderc -B shaderc/b -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$PREFIX" \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 "-DCMAKE_OSX_ARCHITECTURES=$OSX_ARCH" -G Ninja \
	-DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON
cmake --build shaderc/b --parallel "$NPROCS" --target shaderc_combined
mkdir -p "$PREFIX/lib" "$PREFIX/include"
cp shaderc/b/libshaderc/libshaderc_combined.a "$PREFIX/lib/"
cp -r shaderc/libshaderc/include/shaderc "$PREFIX/include/"

# MoltenVK: prebuilt release (dlopen'd Vulkan implementation)
curl -L -o moltenvk.tar "https://github.com/KhronosGroup/MoltenVK/releases/download/$MOLTENVK/MoltenVK-macos.tar"
tar xf moltenvk.tar
cp MoltenVK/MoltenVK/dylib/macOS/libMoltenVK.dylib "$PREFIX/lib/"

echo "Dependencies installed to $PREFIX"
