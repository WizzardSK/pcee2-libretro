#ifndef LIBRETRO_CORE_OPTIONS_H__
#define LIBRETRO_CORE_OPTIONS_H__

#include <stdlib.h>
#include <string.h>

#include "libretro.h"

#ifndef HAVE_NO_LANGEXTRA
#include "libretro_core_options_intl.h"
#endif

/*
 ********************************
 * VERSION: 2.0
 ********************************
 *
 * - 2.0: Add support for core options v2 interface
 * - 1.3: Move translations to libretro_core_options_intl.h
 *        - libretro_core_options_intl.h includes BOM and utf-8
 *          fix for MSVC 2010-2013
 *        - Added HAVE_NO_LANGEXTRA flag to disable translations
 *          on platforms/compilers without BOM support
 * - 1.2: Use core options v1 interface when
 *        RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION is >= 1
 *        (previously required RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION == 1)
 * - 1.1: Support generation of core options v0 retro_core_option_value
 *        arrays containing options with a single value
 * - 1.0: First commit
*/

#ifdef __cplusplus
extern "C" {
#endif

/*
 ********************************
 * Core Option Definitions
 ********************************
*/

/* RETRO_LANGUAGE_ENGLISH */

/* Default language:
 * - All other languages must include the same keys and values
 * - Will be used as a fallback in the event that frontend language
 *   is not available
 * - Will be used as a fallback for any missing entries in
 *   frontend language definition
 * - Translations live in libretro_core_options_intl.h, which is
 *   generated from Crowdin - edit only the English texts here
 */

struct retro_core_option_v2_category option_cats_us[] = {
	{"system", "System", "BIOS and boot behaviour."},
	{"memory_cards", "Memory Cards", "PS2 memory card slot settings."},
	{"graphics", "Graphics", "Renderer, resolution and image quality."},
	{"patches", "Patches", "Built-in game patches (widescreen, no-interlacing)."},
	{"performance", "Performance", "Speed hacks. May break games."},
	{"audio", "Audio", "Sound output and buffering."},
	{NULL, NULL, NULL},
};


struct retro_core_option_v2_definition option_defs_us[] = {
	// system
	{"pcsx2_bios", "BIOS", NULL, "BIOS image to use, from <system>/pcsx2/bios. Requires restart.", NULL,
		"system", {{NULL, NULL}}, "auto"},
	{"pcsx2_fast_boot", "Fast Boot", NULL, "Skip the BIOS boot animation. Requires restart.", NULL,
		"system", {{"enabled", NULL}, {"disabled", NULL}, {NULL, NULL}}, "enabled"},
	// graphics
	// Offering an API this build has no renderer for would leave GSCreateDevice
	// with nothing to construct (Android turns OpenGL off entirely), so the
	// list only carries what is actually compiled in.
	{"pcsx2_renderer", "Renderer", NULL,
		"Hardware renderer API, or the software renderer. Switching to or from Software applies "
		"on the fly; switching between hardware APIs takes effect when the content is restarted.",
		NULL, "graphics",
		{
#ifdef ENABLE_VULKAN
		{"vulkan", "Vulkan (Hardware)"},
#endif
#ifdef ENABLE_OPENGL
			{"opengl", "OpenGL (Hardware)"},
#endif
			{"software", "Software"}, {NULL, NULL}},
		"vulkan"},
	{"pcsx2_upscale_multiplier", "Internal Resolution", NULL,
		"Internal rendering resolution multiplier for the hardware renderer. Also scales the output framebuffer. Applies on the fly.",
		NULL, "graphics",
		{{"1", "1x Native (640x480)"}, {"2", "2x Native (1280x960)"}, {"3", "3x Native (1920x1440)"},
			{"4", "4x Native (2560x1920)"}, {NULL, NULL}},
		"1"},
	{"pcsx2_hw_download_mode", "Hardware Download Mode", NULL,
		"How GPU->CPU readbacks are handled when a game reads rendered data back (GT3 heat haze, "
		"photo modes...). Accurate stalls the whole pipeline on tiler GPUs; Unsynchronized returns "
		"stale data without stalling (big speedup, may glitch those effects); Disabled skips them.",
		NULL, "graphics",
		{{"accurate", "Accurate (Default)"}, {"unsynchronized", "Unsynchronized (Fast)"},
			{"disabled", "Disabled (Fastest)"}, {NULL, NULL}},
		"accurate"},
	{"pcsx2_blending_accuracy", "Blending Accuracy", NULL,
		"Higher levels emulate more PS2 blending effects correctly at a GPU cost.", NULL, "graphics",
		{{"minimum", "Minimum"}, {"basic", "Basic (Recommended)"}, {"medium", "Medium"}, {"high", "High"},
			{"full", "Full (Slow)"}, {"maximum", "Maximum (Very Slow)"}, {NULL, NULL}},
		"basic"},
	{"pcsx2_texture_filtering", "Texture Filtering", NULL,
		"Bilinear (PS2) replicates the console; forced modes smooth all textures.", NULL, "graphics",
		{{"nearest", "Nearest"}, {"bilinear_ps2", "Bilinear (PS2)"}, {"bilinear_forced", "Bilinear (Forced)"},
			{"bilinear_forced_sprite", "Bilinear (Forced excluding sprites)"}, {NULL, NULL}},
		"bilinear_ps2"},
	{"pcsx2_trilinear_filtering", "Trilinear Filtering", NULL, NULL, NULL, "graphics",
		{{"auto", "Automatic (Default)"}, {"off", "Off"}, {"ps2", "Trilinear (PS2)"}, {"forced", "Trilinear (Forced)"},
			{NULL, NULL}},
		"auto"},
	{"pcsx2_anisotropic_filtering", "Anisotropic Filtering", NULL,
		"Reduces texture aliasing at steep angles.", NULL, "graphics",
		{{"0", "Off"}, {"2", "2x"}, {"4", "4x"}, {"8", "8x"}, {"16", "16x"}, {NULL, NULL}}, "0"},
	{"pcsx2_dithering", "Dithering", NULL,
		"Unscaled (default) replicates PS2 dithering; Off can reduce banding artifacts at high resolutions.",
		NULL, "graphics",
		{{"0", "Off"}, {"1", "Scaled"}, {"2", "Unscaled (Default)"}, {NULL, NULL}}, "2"},
	{"pcsx2_mipmapping", "Hardware Mipmapping", NULL, NULL, NULL, "graphics",
		{{"enabled", NULL}, {"disabled", NULL}, {NULL, NULL}}, "enabled"},
	{"pcsx2_deinterlace_mode", "Deinterlacing", NULL,
		"Automatic uses the GameDB-recommended mode per game.", NULL, "graphics",
		{{"0", "Automatic (Default)"}, {"1", "Off"}, {"2", "Weave (TFF)"}, {"3", "Weave (BFF)"},
			{"4", "Bob (TFF)"}, {"5", "Bob (BFF)"}, {"6", "Blend (TFF)"}, {"7", "Blend (BFF)"},
			{"8", "Adaptive (TFF)"}, {"9", "Adaptive (BFF)"}, {NULL, NULL}},
		"0"},
	{"pcsx2_fxaa", "FXAA", NULL, "Cheap post-process anti-aliasing.", NULL, "graphics",
		{{"disabled", NULL}, {"enabled", NULL}, {NULL, NULL}}, "disabled"},
	{"pcsx2_cas_mode", "Contrast Adaptive Sharpening", NULL, NULL, NULL, "graphics",
		{{"disabled", NULL}, {"sharpen", "Sharpen Only"}, {NULL, NULL}}, "disabled"},
	{"pcsx2_audio_buffer_ms", "Audio Buffer", NULL,
		"How much audio the emulator keeps ahead of the frontend. More of it rides out a "
		"stall that would otherwise be heard as a break in the sound, at the cost of that "
		"much delay before you hear anything. PCSX2's own default is 50 ms, which assumes it "
		"is feeding an audio device directly rather than a frontend that pulls once a frame.",
		NULL, "audio",
		{{"50", "50 ms"}, {"75", "75 ms"}, {"100", "100 ms"}, {"150", "150 ms"}, {"200", "200 ms"},
			{NULL, NULL}}, "100"},
	{"pcsx2_frame_limiter", "Frame Limiter", NULL,
		"What holds the emulator to full speed. Frontend leaves the pacing to RetroArch, which "
		"throttles by making the core wait on the audio it hands over. Internal uses PCSX2's own "
		"limiter instead - for a device where that wait never happens, because the audio driver "
		"underruns rather than blocking, and the emulator's own speed variation then reaches the "
		"screen as uneven frame pacing.",
		NULL, "system",
		{{"frontend", "Frontend (RetroArch)"}, {"internal", "Internal (PCSX2)"}, {NULL, NULL}}, "frontend"},
	{"pcsx2_skip_duplicate_frames", "Skip Presenting Duplicate Frames", NULL,
		"Don't hand the frontend a frame the GS never redrew - a 30fps game then delivers 30 "
		"unique frames instead of 60 with every second one repeated. Turn this off if a frame "
		"generation or interpolation filter needs every frame delivered as its own.",
		NULL, "graphics",
		{{"enabled", NULL}, {"disabled", NULL}, {NULL, NULL}}, "enabled"},
	{"pcsx2_cas_sharpness", "CAS Sharpness", NULL, NULL, NULL, "graphics",
		{{"10", NULL}, {"20", NULL}, {"30", NULL}, {"40", NULL}, {"50", NULL}, {"60", NULL},
			{"70", NULL}, {"80", NULL}, {"90", NULL}, {"100", NULL}, {NULL, NULL}},
		"50"},
	{"pcsx2_aspect_ratio", "Aspect Ratio", NULL,
		"Automatic reports 16:9 when widescreen patches are enabled, 4:3 otherwise.", NULL, "graphics",
		{{"auto", "Automatic"}, {"4:3", NULL}, {"16:9", NULL}, {NULL, NULL}}, "auto"},
	// system (continued)
	{"pcsx2_multitap", "Multitap", NULL,
		"Enable the multitap adapter for up to 8 controllers. Player order follows the physical slots "
		"(port 1: 1A-1D, then port 2: 2A-2D). Restart recommended.",
		NULL, "system",
		{{"disabled", "Disabled (2 players)"}, {"port1", "Port 1 (5 players)"}, {"port2", "Port 2 (5 players)"},
			{"both", "Both Ports (8 players)"}, {NULL, NULL}},
		"disabled"},
	{"pcsx2_lightgun", "Lightgun (GunCon 2)", NULL,
		"Emulate a Namco GunCon 2 on a USB port, aimed with the frontend's lightgun (or mouse mapped as "
		"lightgun) on the matching controller port. Requires restart.",
		NULL, "system",
		{{"disabled", NULL}, {"usb1", "USB Port 1"}, {"usb2", "USB Port 2"}, {"both", "Both Ports"},
			{NULL, NULL}},
		"disabled"},
	{"pcsx2_rumble", "Rumble", NULL, "Forward DualShock 2 vibration to the frontend's rumble support.",
		NULL, "system", {{"enabled", NULL}, {"disabled", NULL}, {NULL, NULL}}, "enabled"},
	{"pcsx2_axis_scale", "Analog Axis Scale", NULL,
		"Scales stick input like a real DualShock 2 (PCSX2 default 133%). Lower if diagonals feel clamped.",
		NULL, "system",
		{{"100", "100%"}, {"115", "115%"}, {"133", "133% (Default)"}, {"150", "150%"}, {NULL, NULL}},
		"133"},
	{"pcsx2_axis_deadzone", "Analog Deadzone", NULL,
		"Stick deadzone applied inside the emulated controller, on top of any frontend deadzone.", NULL,
		"system",
		{{"0", "0% (Default)"}, {"5", "5%"}, {"10", "10%"}, {"15", "15%"}, {"20", "20%"}, {"30", "30%"},
			{NULL, NULL}},
		"0"},
	// patches
	{"pcsx2_widescreen_patches", "Widescreen Patches", NULL,
		"Enable built-in 16:9 widescreen patches where available. Best applied before starting a game.", NULL,
		"patches", {{"disabled", NULL}, {"enabled", NULL}, {NULL, NULL}}, "disabled"},
	{"pcsx2_no_interlacing_patches", "No-Interlacing Patches", NULL,
		"Enable built-in progressive-output patches where available. Best applied before starting a game.", NULL,
		"patches", {{"disabled", NULL}, {"enabled", NULL}, {NULL, NULL}}, "disabled"},
	// performance
	{"pcsx2_mtvu", "MTVU (Multi-Threaded VU1)", NULL,
		"Runs VU1 on its own thread. Large speedup on multi-core CPUs; a small number of games hang with it.",
		NULL, "performance",
		{{"enabled", NULL}, {"disabled", NULL}, {NULL, NULL}}, "enabled"},
	{"pcsx2_instant_vu1", "Instant VU1", NULL,
		"Runs VU1 to completion immediately (ignored while MTVU is enabled). Usually a speedup.",
		NULL, "performance",
		{{"enabled", NULL}, {"disabled", NULL}, {NULL, NULL}}, "enabled"},
	{"pcsx2_ee_cycle_rate", "EE Cycle Rate", NULL,
		"Underclock or overclock the emulated Emotion Engine. Default 100%. May break games.", NULL,
		"performance",
		{{"-3", "50% (Underclock)"}, {"-2", "60% (Underclock)"}, {"-1", "75% (Underclock)"},
			{"0", "100% (Default)"}, {"1", "130% (Overclock)"}, {"2", "180% (Overclock)"},
			{"3", "300% (Overclock)"}, {NULL, NULL}},
		"0"},
	{"pcsx2_ee_cycle_skip", "EE Cycle Skip", NULL,
		"Makes the EE skip cycles. Helps some games with high VU activity, breaks others.", NULL,
		"performance",
		{{"0", "Disabled (Default)"}, {"1", "Mild"}, {"2", "Moderate"}, {"3", "Maximum"}, {NULL, NULL}},
		"0"},
	{"pcsx2_cpu_recompiler", "CPU Recompiler (JIT)", NULL,
		"Diagnostic master switch. Enabled runs the EE, IOP and VU0/VU1 dynarecs (JIT, fast, default). "
		"Disabled forces every CPU to an interpreter, which is far slower but isolates JIT bugs: if a crash "
		"still happens with this off, the recompiler is not the cause. The four per-CPU switches below only "
		"take effect while this is Enabled. Requires restart.",
		NULL, "performance",
		{{"enabled", "Enabled (JIT, Default)"}, {"disabled", "Disabled (Interpreter)"}, {NULL, NULL}},
		"enabled"},
	{"pcsx2_rec_ee", "  - EE Recompiler", NULL,
		"Diagnostic. Disable just the Emotion Engine (EE) dynarec while leaving the others on, to bisect "
		"which recompiler causes a crash. Requires restart.",
		NULL, "performance",
		{{"enabled", "Enabled (Default)"}, {"disabled", "Disabled (Interpreter)"}, {NULL, NULL}},
		"enabled"},
	{"pcsx2_rec_iop", "  - IOP Recompiler", NULL,
		"Diagnostic. Disable just the IOP (R3000) dynarec while leaving the others on, to bisect which "
		"recompiler causes a crash. Requires restart.",
		NULL, "performance",
		{{"enabled", "Enabled (Default)"}, {"disabled", "Disabled (Interpreter)"}, {NULL, NULL}},
		"enabled"},
	{"pcsx2_rec_vu0", "  - VU0 Recompiler", NULL,
		"Diagnostic. Disable just the VU0 microVU dynarec while leaving the others on, to bisect which "
		"recompiler causes a crash. Requires restart.",
		NULL, "performance",
		{{"enabled", "Enabled (Default)"}, {"disabled", "Disabled (Interpreter)"}, {NULL, NULL}},
		"enabled"},
	{"pcsx2_rec_vu1", "  - VU1 Recompiler", NULL,
		"Diagnostic. Disable just the VU1 microVU dynarec while leaving the others on, to bisect which "
		"recompiler causes a crash. Requires restart.",
		NULL, "performance",
		{{"enabled", "Enabled (Default)"}, {"disabled", "Disabled (Interpreter)"}, {NULL, NULL}},
		"enabled"},
	// memory cards
	{"pcsx2_memcard_slot1_enable", "Slot 1 Enabled", NULL,
		"Enable the Slot 1 PS2 memory card. Changes apply immediately while content is running.",
		NULL, "memory_cards", {{"enabled", NULL}, {"disabled", NULL}, {NULL, NULL}}, "enabled"},
	{"pcsx2_memcard_slot2_enable", "Slot 2 Enabled", NULL,
		"Enable the Slot 2 PS2 memory card. Changes apply immediately while content is running.",
		NULL, "memory_cards", {{"enabled", NULL}, {"disabled", NULL}, {NULL, NULL}}, "enabled"},
	{"pcsx2_memcard_slot1_file", "Slot 1 Card", NULL,
		"Select an existing .ps2 card from <system>/pcsx2/memcards. Changes apply immediately while content is running.",
		NULL, "memory_cards", {{NULL, NULL}}, "Mcd001.ps2"},
	{"pcsx2_memcard_slot2_file", "Slot 2 Card", NULL,
		"Select an existing .ps2 card from <system>/pcsx2/memcards. Changes apply immediately while content is running.",
		NULL, "memory_cards", {{NULL, NULL}}, "Mcd002.ps2"},
	{NULL, NULL, NULL, NULL, NULL, NULL, {{NULL, NULL}}, NULL},
};

struct retro_core_options_v2 options_us = {
   option_cats_us,
   option_defs_us
};

/*
 ********************************
 * Language Mapping
 ********************************
*/

#ifndef HAVE_NO_LANGEXTRA
struct retro_core_options_v2 *options_intl[RETRO_LANGUAGE_LAST] = {
   &options_us,       /* RETRO_LANGUAGE_ENGLISH */
   &options_ja,       /* RETRO_LANGUAGE_JAPANESE */
   &options_fr,       /* RETRO_LANGUAGE_FRENCH */
   &options_es,       /* RETRO_LANGUAGE_SPANISH */
   &options_de,       /* RETRO_LANGUAGE_GERMAN */
   &options_it,       /* RETRO_LANGUAGE_ITALIAN */
   &options_nl,       /* RETRO_LANGUAGE_DUTCH */
   &options_pt_br,    /* RETRO_LANGUAGE_PORTUGUESE_BRAZIL */
   &options_pt_pt,    /* RETRO_LANGUAGE_PORTUGUESE_PORTUGAL */
   &options_ru,       /* RETRO_LANGUAGE_RUSSIAN */
   &options_ko,       /* RETRO_LANGUAGE_KOREAN */
   &options_cht,      /* RETRO_LANGUAGE_CHINESE_TRADITIONAL */
   &options_chs,      /* RETRO_LANGUAGE_CHINESE_SIMPLIFIED */
   &options_eo,       /* RETRO_LANGUAGE_ESPERANTO */
   &options_pl,       /* RETRO_LANGUAGE_POLISH */
   &options_vn,       /* RETRO_LANGUAGE_VIETNAMESE */
   &options_ar,       /* RETRO_LANGUAGE_ARABIC */
   &options_el,       /* RETRO_LANGUAGE_GREEK */
   &options_tr,       /* RETRO_LANGUAGE_TURKISH */
   &options_sk,       /* RETRO_LANGUAGE_SLOVAK */
   &options_fa,       /* RETRO_LANGUAGE_PERSIAN */
   &options_he,       /* RETRO_LANGUAGE_HEBREW */
   &options_ast,      /* RETRO_LANGUAGE_ASTURIAN */
   &options_fi,       /* RETRO_LANGUAGE_FINNISH */
   &options_id,       /* RETRO_LANGUAGE_INDONESIAN */
   &options_sv,       /* RETRO_LANGUAGE_SWEDISH */
   &options_uk,       /* RETRO_LANGUAGE_UKRAINIAN */
   &options_cs,       /* RETRO_LANGUAGE_CZECH */
   &options_val,      /* RETRO_LANGUAGE_CATALAN_VALENCIA */
   &options_ca,       /* RETRO_LANGUAGE_CATALAN */
   &options_en,       /* RETRO_LANGUAGE_BRITISH_ENGLISH */
   &options_hu,       /* RETRO_LANGUAGE_HUNGARIAN */
   &options_be,       /* RETRO_LANGUAGE_BELARUSIAN */
   &options_gl,       /* RETRO_LANGUAGE_GALICIAN */
   &options_no,       /* RETRO_LANGUAGE_NORWEGIAN */
   &options_ga,       /* RETRO_LANGUAGE_IRISH */
   &options_th,       /* RETRO_LANGUAGE_THAI */
};
#endif

/*
 ********************************
 * Functions
 ********************************
*/

/* Handles configuration/setting of core options.
 * Should be called as early as possible - ideally inside
 * retro_set_environment(), and no later than retro_load_game()
 * > We place the function body in the header to avoid the
 *   necessity of adding more .c files (i.e. want this to
 *   be as painless as possible for core devs)
 */

static inline void libretro_set_core_options(retro_environment_t environ_cb,
      bool *categories_supported)
{
   unsigned version  = 0;
#ifndef HAVE_NO_LANGEXTRA
   unsigned language = 0;
#endif

   if (!environ_cb || !categories_supported)
      return;

   *categories_supported = false;

   if (!environ_cb(RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION, &version))
      version = 0;

   if (version >= 2)
   {
#ifndef HAVE_NO_LANGEXTRA
      struct retro_core_options_v2_intl core_options_intl;

      core_options_intl.us    = &options_us;
      core_options_intl.local = NULL;

      if (environ_cb(RETRO_ENVIRONMENT_GET_LANGUAGE, &language) &&
          (language < RETRO_LANGUAGE_LAST) && (language != RETRO_LANGUAGE_ENGLISH))
         core_options_intl.local = options_intl[language];

      *categories_supported = environ_cb(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL,
            &core_options_intl);
#else
      *categories_supported = environ_cb(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2,
            &options_us);
#endif
   }
   else
   {
      size_t i, j;
      size_t option_index              = 0;
      size_t num_options               = 0;
      struct retro_core_option_definition
            *option_v1_defs_us         = NULL;
#ifndef HAVE_NO_LANGEXTRA
      size_t num_options_intl          = 0;
      struct retro_core_option_v2_definition
            *option_defs_intl          = NULL;
      struct retro_core_option_definition
            *option_v1_defs_intl       = NULL;
      struct retro_core_options_intl
            core_options_v1_intl;
#endif
      struct retro_variable *variables = NULL;
      char **values_buf                = NULL;

      /* Determine total number of options */
      while (true)
      {
         if (option_defs_us[num_options].key)
            num_options++;
         else
            break;
      }

      if (version >= 1)
      {
         /* Allocate US array */
         option_v1_defs_us = (struct retro_core_option_definition *)
               calloc(num_options + 1, sizeof(struct retro_core_option_definition));

         /* Copy parameters from option_defs_us array */
         for (i = 0; i < num_options; i++)
         {
            struct retro_core_option_v2_definition *option_def_us = &option_defs_us[i];
            struct retro_core_option_value *option_values         = option_def_us->values;
            struct retro_core_option_definition *option_v1_def_us = &option_v1_defs_us[i];
            struct retro_core_option_value *option_v1_values      = option_v1_def_us->values;

            option_v1_def_us->key           = option_def_us->key;
            option_v1_def_us->desc          = option_def_us->desc;
            option_v1_def_us->info          = option_def_us->info;
            option_v1_def_us->default_value = option_def_us->default_value;

            /* Values must be copied individually... */
            while (option_values->value)
            {
               option_v1_values->value = option_values->value;
               option_v1_values->label = option_values->label;

               option_values++;
               option_v1_values++;
            }
         }

#ifndef HAVE_NO_LANGEXTRA
         if (environ_cb(RETRO_ENVIRONMENT_GET_LANGUAGE, &language) &&
             (language < RETRO_LANGUAGE_LAST) && (language != RETRO_LANGUAGE_ENGLISH) &&
             options_intl[language])
            option_defs_intl = options_intl[language]->definitions;

         if (option_defs_intl)
         {
            /* Determine number of intl options */
            while (true)
            {
               if (option_defs_intl[num_options_intl].key)
                  num_options_intl++;
               else
                  break;
            }

            /* Allocate intl array */
            option_v1_defs_intl = (struct retro_core_option_definition *)
                  calloc(num_options_intl + 1, sizeof(struct retro_core_option_definition));

            /* Copy parameters from option_defs_intl array */
            for (i = 0; i < num_options_intl; i++)
            {
               struct retro_core_option_v2_definition *option_def_intl = &option_defs_intl[i];
               struct retro_core_option_value *option_values           = option_def_intl->values;
               struct retro_core_option_definition *option_v1_def_intl = &option_v1_defs_intl[i];
               struct retro_core_option_value *option_v1_values        = option_v1_def_intl->values;

               option_v1_def_intl->key           = option_def_intl->key;
               option_v1_def_intl->desc          = option_def_intl->desc;
               option_v1_def_intl->info          = option_def_intl->info;
               option_v1_def_intl->default_value = option_def_intl->default_value;

               /* Values must be copied individually... */
               while (option_values->value)
               {
                  option_v1_values->value = option_values->value;
                  option_v1_values->label = option_values->label;

                  option_values++;
                  option_v1_values++;
               }
            }
         }

         core_options_v1_intl.us    = option_v1_defs_us;
         core_options_v1_intl.local = option_v1_defs_intl;

         environ_cb(RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL, &core_options_v1_intl);
#else
         environ_cb(RETRO_ENVIRONMENT_SET_CORE_OPTIONS, option_v1_defs_us);
#endif
      }
      else
      {
         /* Allocate arrays */
         variables  = (struct retro_variable *)calloc(num_options + 1,
               sizeof(struct retro_variable));
         values_buf = (char **)calloc(num_options, sizeof(char *));

         if (!variables || !values_buf)
            goto error;

         /* Copy parameters from option_defs_us array */
         for (i = 0; i < num_options; i++)
         {
            const char *key                        = option_defs_us[i].key;
            const char *desc                       = option_defs_us[i].desc;
            const char *default_value              = option_defs_us[i].default_value;
            struct retro_core_option_value *values = option_defs_us[i].values;
            size_t buf_len                         = 3;
            size_t default_index                   = 0;

            values_buf[i] = NULL;

            if (desc)
            {
               size_t num_values = 0;

               /* Determine number of values */
               while (true)
               {
                  if (values[num_values].value)
                  {
                     /* Check if this is the default value */
                     if (default_value)
                        if (strcmp(values[num_values].value, default_value) == 0)
                           default_index = num_values;

                     buf_len += strlen(values[num_values].value);
                     num_values++;
                  }
                  else
                     break;
               }

               /* Build values string */
               if (num_values > 0)
               {
                  buf_len += num_values - 1;
                  buf_len += strlen(desc);

                  values_buf[i] = (char *)calloc(buf_len, sizeof(char));
                  if (!values_buf[i])
                     goto error;

                  strcpy(values_buf[i], desc);
                  strcat(values_buf[i], "; ");

                  /* Default value goes first */
                  strcat(values_buf[i], values[default_index].value);

                  /* Add remaining values */
                  for (j = 0; j < num_values; j++)
                  {
                     if (j != default_index)
                     {
                        strcat(values_buf[i], "|");
                        strcat(values_buf[i], values[j].value);
                     }
                  }
               }
            }

            variables[option_index].key   = key;
            variables[option_index].value = values_buf[i];
            option_index++;
         }

         /* Set variables */
         environ_cb(RETRO_ENVIRONMENT_SET_VARIABLES, variables);
      }

error:
      /* Clean up */

      if (option_v1_defs_us)
      {
         free(option_v1_defs_us);
         option_v1_defs_us = NULL;
      }

#ifndef HAVE_NO_LANGEXTRA
      if (option_v1_defs_intl)
      {
         free(option_v1_defs_intl);
         option_v1_defs_intl = NULL;
      }
#endif

      if (values_buf)
      {
         for (i = 0; i < num_options; i++)
         {
            if (values_buf[i])
            {
               free(values_buf[i]);
               values_buf[i] = NULL;
            }
         }

         free(values_buf);
         values_buf = NULL;
      }

      if (variables)
      {
         free(variables);
         variables = NULL;
      }
   }
}

#ifdef __cplusplus
}
#endif

#endif
