# Changelog of the libretro core

What changed in the libretro core of this fork, newest first. Changes that come with a merge of upstream PCSX2 are in upstream's own history; a merge is noted here with the upstream version it brought in.

## Unreleased

- New renderer paraLLEl-GS (Vulkan), from LRPS2: a compute-shader renderer of the GS that draws what the console would, with super sampling (up to 32x) and an experimental high-res scanout in place of upscaling. Its options are under Graphics. Chosen as the Renderer and used from the next start of the content; it needs RetroArch's Vulkan driver. A lightgun crosshair is not drawn with it.
- Windows: the OpenGL renderer starts. The GS thread's OpenGL context was never made current before its functions were loaded, so the GS device failed to open and the picture stayed black (Immersion95, issue #53).
- One frame less input lag, the same as standalone PCSX2: each frame is handed to RetroArch once the GS has drawn it. The core handed over the frame drawn before, one frame behind the input it was run with (Immersion95, issue #53). With the Software renderer it is two frames less: its frame was also read back one vsync late.
- The core names the DualShock 2's buttons and sticks to RetroArch (Cross, Circle, L1 and so on, on every controller port in use). Quick Menu > Controls lists and labels them, so a button can be remapped or left unbound (---) per game or per core; with Hide Unbound Core Input Descriptors on, that list was empty (cubatilles, #50).
- New option System > USB Mouse: PCSX2's USB mouse on USB port 1 or 2, moved and clicked with the frontend's mouse of the matching controller port, wheel included. For the games that take a mouse, as Police 24/7 for aiming (cubatilles, #50).
- OpenGL ES without dual-source blending (no `GL_EXT_blend_func_extended`, as on webOS and Mali): the hardware renderer runs, blending in the shader what needs a second colour output; it refused to start before (cscd98, #52).
- Frame Limiter on Frontend: the core hands RetroArch one frame's worth of sound per frame, and holds it back only when RetroArch's buffer is completely full. It handed over whatever was queued, in bursts, and held it back already at 90%, where RetroArch's macOS CoreAudio driver normally sits; its buffer swung between empty and full and the picture stuttered (spencersmitty, #46).
- Sound no longer stutters where a frame's samples fall on the next frame: the core padded a frame of silence into the running stream each time, meant only for the boot (in Ace Combat 04 some 23 times a second, about 37% silence on top of the game's sound), and the surplus kept RetroArch's buffer full so frames were held too. Now it pads only until the game's first sound (nobz226, #46).
- New option Patches > Cheats, off by default: the `.pnach` cheat files in `system/pcsx2/cheats/`, named after the game's serial and CRC as in standalone PCSX2, are applied. PCSX2 loaded them only with `EnableCheats` set by hand in `PCSX2.ini` (raidenii, issue #49).

## October 2026

- Frame Limiter on Frontend (RetroArch): a frame is held back only when the frontend's audio buffer is nearly full and the game is also ahead of the clock. The full buffer alone held frames on setups where it is small, which made games run slow with broken sound. The log has a line on the pacing for each 600 frames in which it had something to do. With low audio latencies the sound can still break up, from the frontend's buffer running empty: a higher Audio Latency in RetroArch and Audio Buffer in the core settle it (cubatilles, #48).
- New option System > Lightgun Crosshair: a crosshair drawn where the GunCon 2 is aiming, in a colour of your choice, with the software renderer too. Off by default (cubatilles, #47).
- GunCon 2: the calibration shot, which the calibration screen of the Time Crisis games waits for, is on Gun Trigger and Gun Reload held together, and on R3 of the gun's port. It was not on any input, so those screens could not be passed (cubatilles, #47).
- Windows: the core loads again where dxcompiler.dll is not installed. Since the merge of upstream v2.9.78 it needed that DLL just to load ("Failed to open libretro core", error 126), though only the Direct3D 12 renderer uses it; it is now looked for only when that renderer compiles a shader (cubatilles, #47).
- Linux: the core is built without the X11 and Wayland backends, which were for the standalone's own window, and no longer links libX11, libXrandr and libXi; it loads where X11 is not installed.
- Merged up to upstream PCSX2 v2.9.81-22. The core reports upstream's version, and logs it at start with the commit it was built from.
- Vulkan: context negotiation v2, with RetroArch's device wrapper.
- The frame is held while RetroArch's audio buffer is full.
- The translated core option texts compile again.

## September 2026

- Merged upstream PCSX2 v2.9.78.
- PCSX2's game patches are compiled into the core.
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
