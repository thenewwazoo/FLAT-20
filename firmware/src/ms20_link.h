/* SPDX-License-Identifier: GPL-3.0-only */
/* FLAT-20's panel link: what the FM-1 tells a computer about itself over USB MIDI as SysEx, so a panel on the computer
 * (mac/) can show the patch; and the one thing the computer may send back, the cables. The FM-1 never waits for anyone:
 * it sends when something changes and once a second regardless, and a listener that starts late has everything within
 * a second.
 *
 *   F0 7D 46 32 30 VER TYPE ... F7          (7D: the non-commercial ID; "F20"; VER: LINK_VERSION)
 *
 *   TYPE 1, STATE   NPARAM NSRC NDST  p[NPARAM]  (jack jack) x NCABLE  preset flags octave+3  name[12]
 *                   a jack: 0 = nothing, 1 .. NSRC-1 the outputs (SRC_*), then the inputs (NSRC-1 + DST_*); a cable with
 *                   one end 0 is a dummy plug, both 0 no cable
 *                   flags: 1 = PLAY holds the key, 2 = edited since the preset was loaded or saved, 4 = this firmware
                 takes CABLES (a panel offers patching only then)
 *   TYPE 2, LIVE    gate note wheel_hi wheel_lo button lamps
 *                   gate: a key sounds (or PLAY holds it); note: 0..127, the key that counts (127 with gate 0 and
 *                   none played yet is "none"); wheel: (wheel + 127) as 14 bits, -127..127 = -5..+5 V; button: the
 *                   momentary switch; lamps: 1 = the MG's lamp, 2 = the trigger lamp (EG2's trigger),
 *                   4 = the ESP's TRIG lamp, 8 = the ESP's PEAK lamp
 *   TYPE 3, CABLES  (computer -> FM-1) NSRC NDST  (jack jack) x NCABLE: the whole patch panel, as the FM-1 should have
 *                   it. Taken only if every jack exists, no jack has two plugs and no cable has both ends in one jack;
 *                   the FM-1 then answers with a STATE
 *
 * Every byte after F0 is 7-bit already (knobs are 0..127, the name is ASCII). NPARAM / NSRC / NDST let a listener
 * built against another ms20.h see that it is out of date instead of drawing the wrong knobs. Bump LINK_VERSION
 * when the layout of a message changes. */
#ifndef MS20_LINK_H
#define MS20_LINK_H
#include <stdint.h>
#include "ms20.h"

#define LINK_VERSION 2u                             /* 2: a cable joins any two jacks (ms20.h's MS_JACK_*) */
#define LINK_STATE 1u
#define LINK_LIVE 2u
#define LINK_CABLES 3u
#define LINK_CABLES_LEN (7u + 2u + 2u * MS_NCABLE + 1u)
#define LINK_TAKES_CABLES 4u    /* (STATE's flag) */
#define LINK_STATE_LEN (7u + 3u + MS_NPARAM + 2u * MS_NCABLE + 3u + 12u + 1u)
#define LINK_LIVE_LEN (7u + 6u + 1u)
#define LINK_MAX LINK_STATE_LEN
/* An echo of these messages back into the FM-1 (a computer that sends every input to every output) reaches the
 * update code's frame decoder (ota.c), which wants the first decoded byte to be 0: the 7-bit unpacking makes that
 * byte's low 7 bits our first byte's, 0x7D. Never 0, so never taken for an update frame. */
#define LINK_ID 0x7Du
_Static_assert((LINK_ID & 0x7Fu) != 0u, "the first byte must not decode as an update frame");
_Static_assert(MS_NPARAM < 128u && MS_NJACK < 128u && MS_NSRC < 128u && MS_NDST < 128u, "counts are sent as 7-bit bytes");

typedef struct {
    uint8_t preset, flags, octave;                   /* octave: -3..3 as 0..6 */
} link_meta_t;

typedef struct {
    uint8_t gate, note, button, lamps;
    int32_t wheel;                                   /* -127..127 */
} link_live_t;

static uint32_t link_head(uint8_t *o, uint32_t type)
{
    o[0] = 0xF0u; o[1] = LINK_ID; o[2] = 0x46u; o[3] = 0x32u; o[4] = 0x30u; o[5] = (uint8_t)LINK_VERSION; o[6] = (uint8_t)type;
    return 7u;
}

/* the STATE message into o (LINK_STATE_LEN bytes); returns its length */
static uint32_t link_state(uint8_t *o, const ms20_patch_t *p, const link_meta_t *m)
{
    uint32_t n = link_head(o, LINK_STATE), i;
    o[n++] = (uint8_t)MS_NPARAM;
    o[n++] = (uint8_t)MS_NSRC;
    o[n++] = (uint8_t)MS_NDST;
    for (i = 0; i < MS_NPARAM; i++)
        o[n++] = p->p[i] & 0x7Fu;
    for (i = 0; i < MS_NCABLE; i++) {
        uint32_t a = p->cable[i][0], b = p->cable[i][1];
        o[n++] = (uint8_t)(a < MS_NJACK && b < MS_NJACK ? a : 0u);
        o[n++] = (uint8_t)(a < MS_NJACK && b < MS_NJACK ? b : 0u);
    }
    o[n++] = m->preset & 0x7Fu;
    o[n++] = m->flags & 0x7Fu;
    o[n++] = m->octave & 0x7Fu;
    for (i = 0; i < 12u; i++) {
        uint8_t c = i < sizeof p->name ? (uint8_t)p->name[i] : 0u;
        o[n++] = c < 0x20u || c > 0x7Eu ? 0u : c;
    }
    for (i = 0; i < 12u; i++)                        /* (a name ends at its first 0: nothing after it) */
        if (!o[n - 12u + i]) {
            for (; i < 12u; i++)
                o[n - 12u + i] = 0;
            break;
        }
    o[n++] = 0xF7u;
    return n;
}

/* a CABLES message (the bytes between F0 and F7) into c; 0 if it is one and it is sound, else -1 (c untouched) */
static int link_cables_take(const uint8_t *p, uint32_t n, uint8_t c[MS_NCABLE][2])
{
    uint8_t t[MS_NCABLE][2], used[MS_NJACK];
    uint32_t i;
    if (n != LINK_CABLES_LEN - 2u || p[0] != LINK_ID || p[1] != 0x46u || p[2] != 0x32u || p[3] != 0x30u ||
        p[4] != LINK_VERSION || p[5] != LINK_CABLES || p[6] != MS_NSRC || p[7] != MS_NDST)
        return -1;
    for (i = 0; i < MS_NJACK; i++)
        used[i] = 0;
    for (i = 0; i < MS_NCABLE; i++) {
        uint8_t a = p[8u + 2u * i], b = p[9u + 2u * i];
        if (a >= MS_NJACK || b >= MS_NJACK || (a && a == b))
            return -1;                               /* a jack that does not exist, or both ends in one jack */
        if ((a && used[a]++) || (b && used[b]++))
            return -1;                               /* two plugs in one jack */
        t[i][0] = a;
        t[i][1] = b;
    }
    for (i = 0; i < MS_NCABLE; i++) {
        c[i][0] = t[i][0];
        c[i][1] = t[i][1];
    }
    return 0;
}

/* the LIVE message into o (LINK_LIVE_LEN bytes); returns its length */
static uint32_t link_live(uint8_t *o, const link_live_t *l)
{
    uint32_t n = link_head(o, LINK_LIVE), w = (uint32_t)(l->wheel < -127 ? 0 : l->wheel > 127 ? 254 : l->wheel + 127);
    o[n++] = l->gate ? 1u : 0u;
    o[n++] = l->note & 0x7Fu;
    o[n++] = (uint8_t)(w >> 7);
    o[n++] = (uint8_t)(w & 0x7Fu);
    o[n++] = l->button ? 1u : 0u;
    o[n++] = l->lamps & 0x0Fu;
    o[n++] = 0xF7u;
    return n;
}
#endif
