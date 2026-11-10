/*
 * Compile-time ABI probe for the pinned whisper.cpp v1.8.2
 * `struct whisper_full_params` layout.
 *
 * This file is compiled by build_whisper_android.ps1 for each Android ABI.
 * It never runs on a device; a mismatch fails the build instead of producing
 * a library whose `language` field would land at the wrong offset.
 */

#include <stddef.h>

#include "whisper.h"

#if defined(__aarch64__)

_Static_assert(offsetof(struct whisper_full_params, language) == 104,
               "v1.8.2 arm64 language offset changed");
_Static_assert(offsetof(struct whisper_full_params, grammar_penalty) == 264,
               "v1.8.2 arm64 grammar_penalty offset changed");
_Static_assert(offsetof(struct whisper_full_params, vad_model_path) == 272,
               "v1.8.2 arm64 vad_model_path offset changed");
_Static_assert(sizeof(struct whisper_full_params) >= 304,
               "v1.8.2 arm64 whisper_full_params shrank");

#elif defined(__arm__)

_Static_assert(offsetof(struct whisper_full_params, language) == 84,
               "v1.8.2 armv7 language offset changed");
_Static_assert(offsetof(struct whisper_full_params, grammar_penalty) == 184,
               "v1.8.2 armv7 grammar_penalty offset changed");
_Static_assert(offsetof(struct whisper_full_params, vad_model_path) == 192,
               "v1.8.2 armv7 vad_model_path offset changed");
_Static_assert(sizeof(struct whisper_full_params) >= 220,
               "v1.8.2 armv7 whisper_full_params shrank");

#else

#error "whisper_layout_probe.c only supports arm64-v8a and armeabi-v7a"

#endif
