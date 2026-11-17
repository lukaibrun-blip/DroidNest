/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * DroidNest's own core, written in Rust: src/droidnest-core, linked as
 * libdroidnest_core.a by scripts/build_droidnest_core.sh.
 *
 * Keep this file in step with src/droidnest-core/src/lib.rs -- the two are the
 * same interface, and droidnest_core_version() is what says so at run time.
 *
 * Only the DroidNest target links the library. Husk's target compiles the same
 * bridging header without it, which is harmless: these are declarations, and
 * nothing in Husk's Swift calls them.
 */
#ifndef DROIDNEST_CORE_H
#define DROIDNEST_CORE_H

#include <stddef.h>
#include <stdint.h>

/* "droidnest-core 1", NUL-terminated, static. */
const uint8_t *droidnest_core_version(void);

/* --- importing ------------------------------------------------------------ */

/* Whether a file should be copied in.
 *
 * name/name_len   the file's name as the picker gave it
 * head/head_len   its first bytes: NULL or 0 when they could not be read, which
 *                 is not a reason to refuse
 * bytes           its size
 * free_bytes      what the phone says can still be written, or 0 when unknown
 * installed       non-zero when a game with the same Android package is here
 * out/out_cap     receives the sentence to show (empty on 0); NUL-terminated
 *
 * Returns 0 accept, 1 accept with a note, 2 refuse, and the length written. */
enum { DROIDNEST_IMPORT_ACCEPT = 0, DROIDNEST_IMPORT_NOTE = 1, DROIDNEST_IMPORT_REFUSE = 2 };
int32_t droidnest_import_check(const uint8_t *name, size_t name_len,
                               const uint8_t *head, size_t head_len,
                               uint64_t bytes, uint64_t free_bytes, int32_t installed,
                               uint8_t *out, size_t out_cap);

/* --- why the last run stopped --------------------------------------------- */

/* 0 unknown, 1 a fatal signal, 2 the game could not start, 3 iOS ended the app
 * for memory. `log`/`len` is the previous run's log, as UTF-8. */
enum { DROIDNEST_CRASH_UNKNOWN = 0, DROIDNEST_CRASH_SIGNAL = 1,
       DROIDNEST_CRASH_START_FAILED = 2, DROIDNEST_CRASHOUT_OF_MEMORY = 3 };
int32_t droidnest_crash_code(const uint8_t *log, size_t len);
/* The signal behind code 1, or 0. */
int32_t droidnest_crash_signal(const uint8_t *log, size_t len);
/* The explanation as one piece of text: a title, a blank line, then the detail.
 * Returns the length written, not counting the NUL. */
int32_t droidnest_crash_describe(const uint8_t *log, size_t len, uint8_t *out, size_t out_cap);

#endif /* DROIDNEST_CORE_H */
