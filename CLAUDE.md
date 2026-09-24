# CLAUDE.md — pcee2 (PCSX2 as a libretro core)

pcee2 is PCSX2 built as a libretro core (`pcee2_libretro`) for RetroArch and
other libretro frontends. The emulator is upstream PCSX2, merged in regularly;
what is pcee2's own is the libretro frontend, the build and CI around it, and
the ARM64 recompilers.

The working branch is **`libretro`**. It is what the libretro buildbot builds
(`.gitlab-ci.yml`, mirrored to git.libretro.com) and what the GitHub Actions
matrix (`.github/workflows/libretro_builds.yml`) builds on every push. A push to
a `libretro-arm64-*` branch runs the same matrix without touching `libretro`.

## Layout

- `pcee2-libretro/` — the core itself.
  - `Libretro.cpp` — the libretro API, host glue, core options handling,
    video/audio/input.
  - `LibretroVFS.cpp/.h` — file access through the frontend's VFS, so content
    and system files work where plain `fopen` does not (Android SAF).
  - `libretro_core_options.h` — the core option definitions (English), in the
    layout libretro's Crowdin scripts read. `libretro_core_options_intl.h` is
    generated from Crowdin by `.github/workflows/crowdin_translation_sync.yml`;
    do not edit it by hand. Options found at run time (BIOS images, memory
    cards) are filled into `option_defs_us` in `RegisterCoreOptions()`.
  - `scripts/build-deps-*.{sh,bat}` — build the third-party dependencies into a
    prefix; `deps.versions` pins them.
  - `pcee2_libretro.info` — the core info file.
  - `upstream.version` — the upstream PCSX2 version and commit merged in. The
    core reports this version, not pcee2's own tags.
- `pcsx2/`, `common/`, `3rdparty/` — upstream PCSX2 (plus pcee2's changes).
- `pcsx2/arm64/` — the ARM64 recompilers. Their docs are in `arm64-port/`.
- `intl/` — libretro's Crowdin scripts for the core option translations.

## Building

Dependencies first, into a prefix (Linux shown; Windows, macOS and Android have
their own scripts):

```sh
pcee2-libretro/scripts/build-deps-linux.sh deps
```

Then the core, as CI configures it:

```sh
cmake -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DENABLE_QT_UI=OFF -DENABLE_TESTS=OFF -DENABLE_LIBRETRO=ON \
  -DCMAKE_PREFIX_PATH="$PWD/deps" \
  -DSHADERC_STATIC=ON -DSHADERC_LIBRARY="$PWD/deps/lib/libshaderc_combined.a" \
  -DDISABLE_ADVANCE_SIMD=ON
cmake --build build --target pcee2_libretro
```

The result is `build/pcee2_libretro.so`. Load it with
`retroarch -L build/pcee2_libretro.so <content>`. The BIOS goes in
`<system>/pcsx2/bios`.

## Merging upstream PCSX2

- Merge upstream (`github.com/PCSX2/pcsx2`) into `libretro`. Resolve conflicts
  hunk by hunk; never take a whole file with `checkout --theirs`, which drops
  pcee2's changes in it.
- Bump both lines of `pcee2-libretro/upstream.version`, and `display_version`
  in `pcee2_libretro.info`, with every merge.
- `AGENTS.md`, `GEMINI.md` and `.github/PULL_REQUEST_TEMPLATE.md` come from
  PCSX2 and were removed here; keep them removed when a merge brings them
  back.

## ARM64 recompilers

Work on the EE/IOP/VU recompilers for ARM64 follows `arm64-port/`:
`PROGRESS.md` (roadmap), `JOURNAL.md` (session log), `CONVENTIONS.md`
(register map, emission patterns), `DEBUGGING.md` (the `MVU_DIFF` harness).
Two rules from there hold for the whole tree:

1. **Never break the x86-64 build.** ARM64 code goes behind `#ifdef ARCH_ARM64`
   or into `pcsx2/arm64/`.
2. **Use `ARCH_ARM64` / `ARCH_X86`** (from `common/Pcsx2Defs.h`), not
   `_M_ARM64` / `_M_X86`. The `_M_*` macros are MSVC-only: under clang or GCC
   `#ifdef _M_ARM64` is silently dead and `#ifndef _M_X86` is true on x86 too.

The interpreter is the ground truth when a recompiler disagrees with it.
