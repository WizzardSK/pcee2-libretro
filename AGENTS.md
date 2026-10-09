# Rules for coding agents

These apply to any AI agent working in this repository (Claude Code reads them through `CLAUDE.md`, which also describes the layout, the build and the ARM64 recompilers). They came out of testing the libretro cores with their testers.

## Branches and history

- The `libretro` branch is never deleted, and nothing that rewrites its history is run on it: no force-push, no rebase, no amending of commits that are already pushed. It is what the libretro buildbot builds (through the git.libretro.com mirror, which a rewrite would break), so every push to it reaches users in the nightly builds.
- Risky or large changes - the recompilers, the renderers, bigger changes to the libretro frontend, an upstream merge with real conflicts - go on their own branch and into `libretro` only once their build is green and they are tested. ARM64 work uses `libretro-arm64-*` branches, which run the same CI matrix without touching `libretro`.
- Small, checked fixes (a typo, an obvious bug fix, option texts, CI) can go straight into `libretro`. Squashing is not required.

## Merging upstream PCSX2

- Only full merges of upstream (`github.com/PCSX2/pcsx2`) into `libretro`, no cherry-picked upstream commits. Resolve conflicts
  hunk by hunk; never take a whole file with `checkout --theirs`, which drops
  pcee2's changes in it.
- Bump both lines of `pcee2-libretro/upstream.version`, and `display_version`
  in `pcee2_libretro.info`, with every merge. The core reports that version, and
  a new release is built.
- This `AGENTS.md` replaces upstream PCSX2's own. When a merge conflicts on it,
  keep this one.
- What upstream has and pcee2 does not use was removed, and stays removed when
  a merge brings it back: the Qt application (`pcsx2-qt/`, its `crowdin.yml`),
  `updater/`, `pcsx2-gsrunner/`, the unit tests (`tests/`,
  `3rdparty/googletest/`), the developer scripts in `tools/` and `bin/utils/`,
  the standalone docs (`pcsx2/Docs/`, `bin/docs/`), the promptfont source
  (`3rdparty/promptfont/`; the built `.otf` in `bin/resources/fonts/` stays),
  `.codacy.yaml`, `.prettierrc.yaml`, `.gitmodules`, the MSBuild
  files (`*.vcxproj*`, `*.props`, `PCSX2_qt.slnx`, `common/vsprops/`),
  `GEMINI.md`, and
  everything in `.github` but pcee2's own five workflows (`libretro_builds`,
  `android_libretro`, `deps_cmake` and the two `crowdin_*`). Upstream changes
  to those files come back as "deleted by us" conflicts; resolve them all with
  `git status --porcelain | awk '/^DU/ {print $2}' | xargs git rm`.
- The CMake options `ENABLE_QT_UI`, `ENABLE_GSRUNNER` and `ENABLE_TESTS` went
  with them, as did the `source_groups_from_vcxproj_filters()` call in
  `pcsx2/CMakeLists.txt` (IDE grouping read from a file that is not here).
- `bin/docs/ThirdPartyLicenses.html` lives at `THIRD_PARTY_LICENSES.html`.
- `tools/shader_to_cpp.py` lives at `cmake/shader_to_cpp.py`, next to
  `cmake/ShaderToCpp.cmake`, the only thing that runs it (for
  `BAKE_SHADERS_IN_CPP`). Git follows the move, so an upstream change to the
  script still lands on it; a change to the path in `ShaderToCpp.cmake` keeps
  the `cmake/` one.

## These files

- Only the developer writes to or deletes `AGENTS.md` and `CLAUDE.md`. An agent does not change them on its own; it proposes the change to the developer instead.

## Code

- Keep comments true. When a change makes a comment describe behaviour that no longer exists, fix or remove the comment in the same commit.
- Look at the big picture, not just the function being changed. For example, resetting the content and closing it have to release the game's resources through the same path; a reset is an unload and a load.
- Stop the VM and its threads the way upstream PCSX2 does (`VMManager::Shutdown`), not with methods made up for the libretro port. Ad-hoc ones are what cause shutdown and reset bugs.
- Every core option has to be connected to something. Do not add an option the core does not read, and remove one that turns out to do nothing. Option defaults follow standalone PCSX2's defaults unless there is a reason, written down beside the option.
- The core's settings are core options (the `.opt` file), held in a `MemorySettingsInterface`; `PCSX2.ini` is not where they live.
- Never break the x86-64 build: ARM64 code goes behind `#ifdef ARCH_ARM64` or into `pcsx2/arm64/`. Use `ARCH_ARM64` / `ARCH_X86` (from `common/Pcsx2Defs.h`), not the MSVC-only `_M_ARM64` / `_M_X86`.

## Testing

- The core logs, at start, the upstream version and the commit of this repository it was built from. Ask testers for RetroArch's log, and check which commit a log came from before drawing conclusions from it.
- Compare with standalone PCSX2 at the same upstream version before calling something a core bug; when standalone fails the same way, it is upstream's.
- When a recompiler disagrees with the interpreter, the interpreter is the ground truth (`arm64-port/DEBUGGING.md`).

## Libretro pitfalls already hit in the other cores

Each of these was a bug in at least one of the cemu, rpcs3, vita3k or xenia cores. Check new code against them before asking testers.

- Audio: each retro_run hands the frontend exactly one frame's worth (sample rate / declared fps), never "whatever is queued". The game's audio thread waits once about 64 ms is queued; no bigger buffer on the core's side. Several streams (audio ports, clients, a music player) are mixed, not appended one after another, and each is taken in its own format and sample rate.
- Geometry: the size the frame is handed over at goes to the frontend: base geometry at load, SET_GEOMETRY when it changes, SET_SYSTEM_AV_INFO when it would exceed the max. The max has to cover the highest internal resolution.
- Pacing: the guest's vblank follows retro_run, and the core declares the guest's refresh rate; the frontend paces display and audio, the core does not sleep to pace itself.
- Files: everything the core writes goes under system/<core>/ (or saves/); nothing next to the RetroArch executable. The emulator's own log goes there too, and its warnings and errors also go to RetroArch's log.
- No window: the standalone's UI (on-screen keyboard, notifications, message boxes, profile dialogs) has no window in a core. Every path that reaches for the window or its UI thread needs a headless branch that answers the way the user most likely would.
- Unload: never end the process (no exit, no TerminateTitle-style shutdown). Stop and join every thread in upstream's order, and never wait without a timeout on a fence, event or thread the frontend has to drive. No vkQueueWaitIdle/vkDeviceWaitIdle while RetroArch holds its queue lock.
- Libraries that pin themselves (statically linked OpenSSL) keep the core loaded after dlclose; build them so they do not.
- No downloads at run time; data files ship with the core.
