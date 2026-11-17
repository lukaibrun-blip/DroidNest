/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * The DroidNest target's bridging header: everything Husk's app sees, plus its own Rust core.
 *
 * It exists so Husk's target keeps HuskBridge.h exactly as it was. Declaring the core's functions in Husk's own bridging
 * header would compile them into a target that does not link libdroidnest_core.a -- declarations are free, but a single
 * accidental call from shared code would then fail at link time instead of at compile time.
 */
#ifndef DROIDNEST_BRIDGE_H
#define DROIDNEST_BRIDGE_H

/* Husk's own view of QEMU and the display: the same file its target uses. */
#include "../Husk/HuskBridge.h"

/* DroidNest's own decisions, in Rust (src/droidnest-core). Next to this file, so the quoted include finds it. */
#include "DroidNestCore.h"

#endif /* DROIDNEST_BRIDGE_H */
