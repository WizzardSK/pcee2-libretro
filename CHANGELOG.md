# Changelog of the libretro core

What changed in the libretro core of this fork, newest first. Changes that come with a merge of upstream PCSX2 are in upstream's own history; a merge is noted here with the upstream version it brought in.

## October 2026

- Merged up to upstream PCSX2 v2.9.81-22. The core reports upstream's version, and logs it at start with the commit it was built from.
- Vulkan: context negotiation v2, with RetroArch's device wrapper.
- The frame is held while RetroArch's audio buffer is full, so sound no longer breaks up when the frontend falls behind.
- The translated core option texts compile again.

## September 2026

- Merged upstream PCSX2 v2.9.78.
- PCSX2's game patches are compiled into the core; no `patches.zip` is needed.
- The repository holds the core only: the Qt application, the updater, gsrunner, the unit tests, the developer scripts and the standalone's documents are removed.
- The core option texts are translated through libretro's Crowdin project.
- The GS is never built on a graphics API RetroArch did not give the core, the software renderer included.
- Audio is not handed to a frontend whose buffer is already full.
- The frame is handed over at the size the GS drew it, and the size stays steady between real frames.
- Cores for iOS, tvOS and webOS.
- The core's own releases stopped: it comes from libretro's buildbot.

## August 2026

- Merged upstream PCSX2 master of 19 August. The core reports upstream's version.
- OpenGL through RetroArch's own context instead of a copy through the CPU, surviving the context going away; the hardware renderer runs on OpenGL ES.
- Vulkan: the render interface is asked for every frame, so a context teardown no longer pulls it away; VK_KHR_push_descriptor is no longer required.
- The game database, the shaders and the fonts are built into the core; no resources directory is needed.
- Files are read through RetroArch's VFS.
- Cue sheets, and `.m3u` playlists with RetroArch's disc control.
- Skip Presenting Duplicate Frames as a core option.
- The audio buffer is as deep as a frontend needs, and the VM paces itself when the frontend does not.
- Android: the core builds, on libretro's buildbot too.
- Windows: the core builds with MinGW, with the C runtime linked statically.
- Linux x86_64: SDL3 and libjpeg are built into the core; libpcap is loaded at run time instead of linked.
- The from-source dependencies are built from CMake on every platform.

## July 2026

- Vulkan through RetroArch's hardware context, without a copy of every frame through system memory.
- ARM64: isztldav's dynarec advance, and a musl build fix.
- The core is no longer marked experimental.

## June 2026

- The core: Vulkan and OpenGL renderers, audio, pads, savestates, and core options for the renderer, internal resolution, BIOS and fast boot, later widened to the key graphics settings of the standalone.
- The core is named PCEE2.
- Rumble, analog axis scale and deadzone options, multitap for up to eight controllers, and GunCon 2 lightgun support.
- An aspect ratio option, with 16:9 reported for widescreen patches; the VM's real timing is reported (PAL 50 Hz, PSX mode 44.1 kHz).
- EE memory is exposed for achievements and cheats.
- A standalone `PCSX2.ini` is adopted when present.
- Logs go through RetroArch, and crash dumps stay out of its folder.
- The core survives content reloads and RetroArch's full deinit and init cycle.
- Dependencies are linked statically on Windows, macOS and Linux.
- ARM64: isztldav's EE, IOP and microVU dynarec, an interpreter mode option and per-CPU recompiler toggles, and a self-contained aarch64 build.
