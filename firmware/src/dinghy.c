/* SPDX-License-Identifier: GPL-3.0-only */
/* FLAT-20: the Korg MS-20 for the M-VAVE FM-1. Built on Dinghy (zvenson), which is Felucca's platform (Leo Kuroshita)
 * as SLOOP / OberVave carry it. The sound is ms20.h (the MS-20's circuit, part for part); this file is the instrument
 * around it: the keys, the pages of knobs, the patch panel, the presets, MIDI.
 *
 *   SELECT       the page (VCO 1, VCO 2, MIXER / FM, HIGH PASS, LOW PASS, MG / EG 1, EG 2, MORE, EXT SIGNAL PROC,
 *                PATCH PANEL)
 *   ALGORITHM    the control wheel (the patch panel's wheel jack, -5 .. +5 V; it stays where you leave it)
 *   KNOB 1..4    the page's four controls. On PATCH PANEL: the cable, its output, its input, (turn left) unplug
 *   HOME FX ENV LFO EDIT   straight to the VCOs, the filters, the envelopes, the MG, the patch panel
 *   PRESETS      the preset (16); SAVE keeps the sound in it
 *   REC          the MS-20's momentary switch (a contact to ground: patch it to a TRIG IN)
 *   PLAY         hold: the key stays down after you let go (drones, patching with both hands)
 *   OCT- OCT+    the octave (the MS-20's own keyboard is C3 .. C6 at 8')
 *   MIDI in      notes, pitch bend (+-2), CC 1 = the wheel's upper half, CC 2 = the whole wheel (64 = centre), CC 16..51 = the knobs
 *
 * As on the MS-20: the highest key held sounds, and a new note while another is held does not start the envelopes again.
 * The main loop uses integers only; float lives in the audio interrupt (ms20.h says why). */
static void app_idle(void);
#define LCD_IDLE app_idle
#include <stdint.h>
static int app_sysex(const uint8_t *p, uint32_t n);
#define APP_SYSEX app_sysex          /* (platform.c: a SysEx from the computer, F0 and F7 left off) */
#define APP_NAME "FLAT-20"
#include "platform.c"
#include "ms20.h"
#include "ms20_link.h"

/* ---- the sound */
static ms20_t syn;
static ms20_patch_t patch;                      /* the sound being played and edited (bytes: the main loop writes, the ISR reads) */
static ms20_ctl_t ctl;
static volatile uint32_t cpu_peak;              /* the render's time for 256 frames, of 5800 us */
static uint8_t syn_ok;

static void app_audio(int32_t *out, uint32_t n)
{
    static float buf[256];
    uint32_t i;
#ifndef DINGHY_HOST
    uint32_t t0 = fm1_ticks(), us;
#endif
    if (n > 256u)
        n = 256u;
    if (!syn_ok) {
        ms20_init(&syn);
        syn_ok = 1;
    }
#ifndef DIAG_NOFLOAT
    ms20_render(&syn, &patch, &ctl, buf, n);
#endif
    for (i = 0; i < n; i++) {
#ifndef DIAG_NOFLOAT
        float x = buf[i] * 30000.f;               /* +-2.5 V at SIGNAL OUT: 0.92 of full scale */
        int32_t v = (int32_t)(x > 32767.f ? 32767.f : x < -32767.f ? -32767.f : x);
#else
        int32_t v = 0;
#endif
        out[2u * i] += v;
#ifdef DIAG_TONE                                /* a 1 kHz integer triangle on the right: is a glitch the engine's or the block's? */
        { static uint32_t tph; int32_t tv; tph += 97391549u; tv = (int32_t)tph >> 17; out[2u * i + 1u] += (tv < 0 ? -tv : tv) - 8192; }
#else
        out[2u * i + 1u] += v;
#endif
    }
#ifndef DINGHY_HOST
    {                                           /* (the platform asks for 32 frames at a time: 8 calls are a half buffer) */
        static uint32_t acc_us, acc_n;
        us = (fm1_ticks() - t0) / FM1_TICKS_PER_US;
        acc_us += us;
        acc_n += n;
        if (acc_n >= 256u) {
            if (acc_us > cpu_peak)
                cpu_peak = acc_us;
            acc_us = acc_n = 0;
        }
    }
#endif
}

/* ---- the controls: what the screen calls them and how it shows them */
enum { K_DIAL, K_BI, K_ENUM };                  /* 0.0 .. 10.0; -5.0 .. +5.0; one of four names */
typedef struct { const char *label; uint8_t kind; const char *const *names; } pinfo_t;
static const char *const N_W1[4] = {"TRI", "SAW", "PULSE", "NOISE"};
static const char *const N_W2[4] = {"SAW", "SQR", "PULSE", "RING"};
static const char *const N_S1[4] = {"32'", "16'", "8'", "4'"};
static const char *const N_S2[4] = {"16'", "8'", "4'", "2'"};
static const pinfo_t PINFO[MS_NPARAM] = {
    [P_V1WAVE] = {"WAVE", K_ENUM, N_W1}, [P_V1PW] = {"PW", K_DIAL, 0}, [P_V1SCALE] = {"SCALE", K_ENUM, N_S1},
    [P_PORTA] = {"PORTA", K_DIAL, 0}, [P_V2WAVE] = {"WAVE", K_ENUM, N_W2}, [P_V2PITCH] = {"PITCH", K_BI, 0},
    [P_V2SCALE] = {"SCALE", K_ENUM, N_S2}, [P_TUNE] = {"TUNE", K_BI, 0}, [P_MIX1] = {"VCO 1", K_DIAL, 0},
    [P_MIX2] = {"VCO 2", K_DIAL, 0}, [P_FM_MG] = {"FM MG", K_DIAL, 0}, [P_FM_EG] = {"FM EG1", K_DIAL, 0},
    [P_HP_CUT] = {"CUTOFF", K_DIAL, 0}, [P_HP_PEAK] = {"PEAK", K_DIAL, 0}, [P_HP_MG] = {"MG", K_DIAL, 0},
    [P_HP_EG] = {"EG2", K_DIAL, 0}, [P_LP_CUT] = {"CUTOFF", K_DIAL, 0}, [P_LP_PEAK] = {"PEAK", K_DIAL, 0},
    [P_LP_MG] = {"MG", K_DIAL, 0}, [P_LP_EG] = {"EG2", K_DIAL, 0}, [P_MG_WAVE] = {"MG WAVE", K_DIAL, 0},
    [P_MG_RATE] = {"MG RATE", K_DIAL, 0}, [P_E1_DELAY] = {"E1 DLY", K_DIAL, 0}, [P_E1_ATK] = {"E1 ATK", K_DIAL, 0},
    [P_E1_REL] = {"E1 REL", K_DIAL, 0}, [P_E2_HOLD] = {"E2 HOLD", K_DIAL, 0}, [P_E2_ATK] = {"ATTACK", K_DIAL, 0},
    [P_E2_DEC] = {"DECAY", K_DIAL, 0}, [P_E2_SUS] = {"SUSTAIN", K_DIAL, 0}, [P_E2_REL] = {"RELEASE", K_DIAL, 0},
    [P_VOLUME] = {"VOLUME", K_DIAL, 0}, [P_ESP_CV] = {"CV ADJ", K_BI, 0},
    [P_ESP_LEVEL] = {"LEVEL", K_DIAL, 0}, [P_ESP_LOW] = {"LOW CUT", K_DIAL, 0}, [P_ESP_HIGH] = {"HI CUT", K_DIAL, 0},
    [P_ESP_THR] = {"THRESH", K_DIAL, 0},
};
#define NPAGE 10u
#define PG_PATCH 9u
static const struct { const char *name; uint8_t p[4]; } PAGE[NPAGE] = {
    {"VCO 1", {P_V1WAVE, P_V1PW, P_V1SCALE, P_PORTA}},
    {"VCO 2", {P_V2WAVE, P_V2PITCH, P_V2SCALE, P_TUNE}},
    {"MIXER / FM", {P_MIX1, P_MIX2, P_FM_MG, P_FM_EG}},
    {"HIGH PASS", {P_HP_CUT, P_HP_PEAK, P_HP_MG, P_HP_EG}},
    {"LOW PASS", {P_LP_CUT, P_LP_PEAK, P_LP_MG, P_LP_EG}},
    {"MG / EG 1", {P_MG_WAVE, P_MG_RATE, P_E1_ATK, P_E1_REL}},
    {"EG 2", {P_E2_ATK, P_E2_DEC, P_E2_SUS, P_E2_REL}},
    {"MORE", {P_E1_DELAY, P_E2_HOLD, P_VOLUME, P_ESP_CV}},
    {"EXT SIGNAL PROC", {P_ESP_LEVEL, P_ESP_LOW, P_ESP_HIGH, P_ESP_THR}},
    {"PATCH PANEL", {0, 0, 0, 0}},
};
static const char *const SRC_NAME[MS_NSRC] = {"-", "KBD CV", "KBD TRIG", "MG TRI", "MG RECT", "EG1 OUT", "EG1 REV", "EG2 REV",
    "S&H OUT", "VCA OUT", "WHITE", "PINK", "WHEEL", "SWITCH", "SIGNAL", "PHONES", "ESP AMP", "ESP BPF", "ESP F-V", "ESP ENV",
    "ESP TRIG", "VCO 1 *", "VCO 2 *"};          /* (*: not a jack on an MS-20) */
static const char *const DST_NAME[MS_NDST] = {"-", "TOTAL", "FREQ", "VCO1+2 CV", "VCO2 CV", "EXT SIG", "HP CUTOFF", "LP CUTOFF",
    "INIT GAIN", "TRIG IN", "EG1 TRIG", "S&H IN", "S&H CLOCK", "VCA IN", "VCA CTRL", "ESP IN"};
static const char *jack_name(uint32_t j)
{
    return j == 0u || j >= MS_NJACK ? "-" : j < MS_NSRC ? SRC_NAME[j] : DST_NAME[j - (MS_NSRC - 1u)];
}

/* ---- presets: 16, the factory's until SAVE keeps another in its place (blob 0) */
#define NPRESET 16u
#define W(i) ((i) * 32 + 16)                    /* a four-way switch's position as a stored value */
#define K(x) ((uint8_t)((x) * 12.7f + 0.5f))    /* a knob as its scale reads, 0 .. 10 */
#define BASE [P_V1WAVE] = W(1), [P_V1SCALE] = W(2), [P_V2WAVE] = W(0), [P_V2PITCH] = 64, [P_V2SCALE] = W(1), [P_TUNE] = 64, \
    [P_MIX1] = K(10), [P_LP_CUT] = K(10), [P_MG_WAVE] = K(5), [P_MG_RATE] = K(3), [P_E2_DEC] = K(5), [P_E2_SUS] = K(10), \
    [P_E2_REL] = K(1.5), [P_VOLUME] = K(10), [P_ESP_CV] = K(6.5), [P_ESP_LEVEL] = K(0.2), [P_ESP_LOW] = K(2), \
    [P_ESP_HIGH] = K(4), [P_ESP_THR] = K(3)
static const ms20_patch_t FACTORY[NPRESET] = {
    {.name = "INIT", .p = {BASE}},
    /* The "Flat Beat" bass as GAK's KORG Sound Icons video sets it on an MS-20 mini: one square at 32', the low-pass
     * open with a little PEAK, EG2 with only a DECAY, and one cable: EG2's REV OUT into the low-pass's CUTOFF FREQ, its
     * EG2 / EXT at the top. The envelope upside down: the filter shuts as the note starts and opens as it dies away. */
    {.name = "FLAT BEAT", .p = {BASE, [P_V1WAVE] = W(2), [P_V1PW] = 0, [P_V1SCALE] = W(0), [P_MIX1] = K(9.5), [P_PORTA] = K(2),
        [P_HP_CUT] = K(0.3), [P_LP_PEAK] = K(4.5), [P_LP_EG] = K(10), [P_E2_DEC] = K(1.6), [P_E2_SUS] = 0, [P_E2_REL] = 0},
        .cable = {{MS_JACK_OUT(SRC_EG2_REV), MS_JACK_IN(DST_LP_CUT)}}},
    /* The "Da Funk" lead as the same series sets it: two sawtooths a fourth apart, both PEAKs at 8, and EG1's OUT
     * (0 V rising to +5 V) into the high-pass's CUTOFF FREQ: the high-pass sweeps up into every note. */
    {.name = "DA FUNK", .p = {BASE, [P_V2SCALE] = W(0), [P_V2PITCH] = 97, [P_MIX1] = K(9), [P_MIX2] = K(9), [P_PORTA] = K(2.3),
        [P_HP_CUT] = K(0.5), [P_HP_PEAK] = K(8), [P_HP_EG] = K(9), [P_LP_CUT] = K(9.5), [P_LP_PEAK] = K(8),
        [P_E1_ATK] = K(1.5), [P_E1_REL] = K(5), [P_E2_REL] = K(3)},
        .cable = {{MS_JACK_OUT(SRC_EG1), MS_JACK_IN(DST_HP_CUT)}}},
    /* both filters near singing, EG2 pulling the low-pass up from below (SUSTAIN at 6: the filters get EG2 less that) */
    {.name = "SCREAMER", .p = {BASE, [P_V2WAVE] = W(1), [P_V2PITCH] = 66, [P_MIX2] = K(10), [P_PORTA] = K(3), [P_HP_CUT] = K(3.5),
        [P_HP_PEAK] = K(7.5), [P_LP_CUT] = K(6.5), [P_LP_PEAK] = K(8), [P_LP_EG] = K(7), [P_E2_ATK] = K(0.5), [P_E2_DEC] = K(4),
        [P_E2_SUS] = K(6), [P_E2_REL] = K(3)}},
    /* the high-pass singing along (PEAK just past where it starts), swept by the MG */
    {.name = "HP SQUEAL", .p = {BASE, [P_V1SCALE] = W(1), [P_HP_CUT] = K(4.5), [P_HP_PEAK] = K(9), [P_HP_MG] = K(6),
        [P_MG_RATE] = K(0.8), [P_E2_REL] = K(3)}},
    {.name = "RING BELL", .p = {BASE, [P_V1WAVE] = W(2), [P_MIX1] = 0, [P_V2WAVE] = W(3), [P_V2PITCH] = 98, [P_MIX2] = K(10),
        [P_LP_CUT] = K(7.5), [P_LP_EG] = K(5), [P_E2_DEC] = K(5), [P_E2_SUS] = 0, [P_E2_REL] = K(5)}},
    /* The MS-20's "sample and hold" follows while its clock is high: the MG's rectangle, made narrow by WAVE FORM,
     * lets a moment of noise through and holds it. S&H OUT into TOTAL: the MG / T.EXT knobs now turn it up. */
    {.name = "S&H RANDOM", .p = {BASE, [P_V1WAVE] = W(2), [P_V1PW] = K(3), [P_FM_MG] = K(6.5), [P_LP_CUT] = K(6), [P_LP_PEAK] = K(6),
        [P_LP_MG] = K(5), [P_MG_RATE] = K(3.5), [P_MG_WAVE] = K(9.4)},
        .cable = {{MS_JACK_OUT(SRC_WHITE), MS_JACK_IN(DST_SH_IN)}, {MS_JACK_OUT(SRC_MG_RECT), MS_JACK_IN(DST_SH_CLOCK)}, {MS_JACK_OUT(SRC_SH), MS_JACK_IN(DST_TOTAL)}}},
    /* Vibrato that comes in late: the MG through the modulation VCA into TOTAL. With nothing in its CONTROL INPUT the
     * VCA is opened by EG1: DELAY and ATTACK are how late and how slowly. */
    {.name = "DELAY VIB", .p = {BASE, [P_FM_MG] = K(2.4), [P_MG_RATE] = K(3), [P_LP_CUT] = K(7.5), [P_E1_DELAY] = K(4),
        [P_E1_ATK] = K(4), [P_E1_REL] = K(2), [P_E2_REL] = K(3)},
        .cable = {{MS_JACK_OUT(SRC_MG_TRI), MS_JACK_IN(DST_MVCA_IN)}, {MS_JACK_OUT(SRC_MVCA), MS_JACK_IN(DST_TOTAL)}}},
    /* the headphone output back into EXT SIGNAL IN: the MS-20's own overdrive (VOLUME is how much) */
    {.name = "FEEDBACK", .p = {BASE, [P_V1SCALE] = W(1), [P_V2WAVE] = W(1), [P_V2SCALE] = W(0), [P_MIX1] = K(7), [P_MIX2] = K(7),
        [P_LP_CUT] = K(6), [P_LP_PEAK] = K(6), [P_LP_EG] = K(5), [P_E2_DEC] = K(4), [P_E2_SUS] = K(7), [P_VOLUME] = K(8.5)},
        .cable = {{MS_JACK_OUT(SRC_PHONES), MS_JACK_IN(DST_EXT_IN)}}},
    /* the MG's rectangle into TRIG IN: a trigger is a contact to ground, so the note sounds while the rectangle is low.
     * The keys only choose the pitch. */
    {.name = "AUTO TRIG", .p = {BASE, [P_V1WAVE] = W(2), [P_V1SCALE] = W(1), [P_LP_CUT] = K(4.5), [P_LP_PEAK] = K(6.5),
        [P_LP_EG] = K(7), [P_MG_RATE] = K(4), [P_E2_DEC] = K(2.2), [P_E2_SUS] = 0, [P_E2_REL] = K(1)},
        .cable = {{MS_JACK_OUT(SRC_MG_RECT), MS_JACK_IN(DST_TRIG)}}},
    /* no oscillator: the low-pass sings, EG2 throws its pitch down */
    {.name = "KICK", .p = {BASE, [P_MIX1] = 0, [P_LP_CUT] = K(1.7), [P_LP_PEAK] = K(10), [P_LP_EG] = K(6.5), [P_E2_DEC] = K(2.3),
        [P_E2_SUS] = 0, [P_E2_REL] = K(2.3)}},
    {.name = "WIND", .p = {BASE, [P_V1WAVE] = W(3), [P_HP_CUT] = K(4), [P_LP_CUT] = K(6), [P_LP_PEAK] = K(8.3), [P_LP_MG] = K(6.5),
        [P_MG_RATE] = K(0.2), [P_E2_ATK] = K(4.5), [P_E2_REL] = K(5.5)}},
    /* EG1 / EXT: the VCOs get EG1 as -5 V at rest, so the note climbs to its pitch and falls away after */
    {.name = "EG1 SWOOP", .p = {BASE, [P_V2WAVE] = W(1), [P_V2SCALE] = W(0), [P_MIX2] = K(8), [P_FM_EG] = K(5.5), [P_LP_CUT] = K(7),
        [P_E1_ATK] = K(2.5), [P_E1_REL] = K(3.5), [P_E2_REL] = K(4.5)}},
    /* a plug in VCO 2 CV IN takes VCO 2 off the keyboard: here the wheel is its pitch, in Hz / V (ALGORITHM) */
    {.name = "WHEEL>VCO2", .p = {BASE, [P_MIX1] = K(8.5), [P_MIX2] = K(8.5), [P_LP_CUT] = K(7.5), [P_LP_PEAK] = K(4)},
        .cable = {{MS_JACK_OUT(SRC_WHEEL), MS_JACK_IN(DST_VCO2_CV)}}},
    /* The external signal processor listening to the synthesizer itself: its frequency-to-voltage converter plays
     * VCO 2 from VCO 1's pitch (CV ADJUST tunes it), with the converter's lag. */
    {.name = "F-V TRACK", .p = {BASE, [P_V1WAVE] = W(0), [P_V2WAVE] = W(1), [P_MIX1] = K(7), [P_MIX2] = K(9), [P_LP_CUT] = K(7.5)},
        .cable = {{MS_JACK_OUT(SRC_VCO1), MS_JACK_IN(DST_ESP_IN)}, {MS_JACK_OUT(SRC_ESP_FV), MS_JACK_IN(DST_VCO2_CV)}}},
    {.name = "INIT 16", .p = {BASE}},
};
static ms20_patch_t bank[NPRESET];
static struct { uint8_t oct, preset; } set = {0, 1};

/* the bank in flash (blob 0): a format number, then the 16 presets. Format 2: a cable is two jacks. A bank saved by
 * format-1 firmware (no number, cables as output, input) is read and its cables converted. */
#define BANK_FORMAT 2u
static struct { uint32_t format; ms20_patch_t bank[NPRESET]; } store;
static int bank_load(void)
{
    uint32_t i, c;
    if (!blob_load(0, &store, sizeof store) && store.format == BANK_FORMAT) {
        memcpy(bank, store.bank, sizeof bank);
        return 0;
    }
    if (blob_load(0, bank, sizeof bank))
        return -1;
    for (i = 0; i < NPRESET; i++)
        for (c = 0; c < MS_NCABLE; c++) {
            uint32_t s0 = bank[i].cable[c][0], d0 = bank[i].cable[c][1];
            int ok = s0 && s0 < MS_NSRC && d0 && d0 < MS_NDST;
            bank[i].cable[c][0] = ok ? MS_JACK_OUT(s0) : 0u;
            bank[i].cable[c][1] = ok ? MS_JACK_IN(d0) : 0u;
        }
    return 0;
}
static void bank_save(void)
{
    store.format = BANK_FORMAT;
    memcpy(store.bank, bank, sizeof bank);
    blob_save(0, &store, sizeof store);
}

static void load_preset(uint32_t i)
{
    memcpy(&patch, &bank[i % NPRESET], sizeof patch);
}

/* ---- notes (main loop). The MS-20's keyboard is a chain of resistors read from its top end: the highest key held
 * is the one that counts, and its trigger is "a key is down", so playing legato does not start the envelopes again. */
#define NHELD 16u
static uint8_t held[NHELD], nheld, hold_on;
static int32_t bend;                            /* 1/256 semitone */
static uint32_t last_note = 255;

static void notes_update(void)
{
    uint32_t i;
    if (nheld) {
        last_note = held[0];
        for (i = 1; i < nheld; i++)
            if (held[i] > last_note)
                last_note = held[i];
        ctl.note = (int32_t)last_note * 256 + bend;
        ctl.gate = 1;
    } else {
        if (last_note < 128u)
            ctl.note = (int32_t)last_note * 256 + bend;
        if (!hold_on)
            ctl.gate = 0;
    }
}
static void play(uint32_t note)
{
    uint32_t i, j;
    if (note > 127u)
        return;
    for (i = j = 0; i < nheld; i++)             /* (the same key again: to the top) */
        if (held[i] != note)
            held[j++] = held[i];
    nheld = (uint8_t)j;
    if (nheld == NHELD) {
        for (i = 1; i < NHELD; i++)
            held[i - 1u] = held[i];
        nheld--;
    }
    held[nheld++] = (uint8_t)note;
    notes_update();
}
static void stop(uint32_t note)
{
    uint32_t i, j;
    for (i = j = 0; i < nheld; i++)
        if (held[i] != note)
            held[j++] = held[i];
    nheld = (uint8_t)j;
    notes_update();
}
static int quiet(void) { return !ctl.gate && !syn.e2_st; }

/* ---- the screen */
#define C_ACC RGB(255, 160, 40)
#define C_GRY RGB(110, 110, 110)
#define C_BAR RGB(70, 60, 50)
#define C_SEL RGB(60, 40, 10)

static char *put_s(char *p, const char *s) { while (*s) *p++ = *s++; return p; }
static char *put_u(char *p, uint32_t v)
{
    char t[10];
    uint32_t n = 0;
    do { t[n++] = (char)('0' + v % 10u); v /= 10u; } while (v);
    while (n) *p++ = t[--n];
    return p;
}

static void value_text(uint32_t pi, char *b)
{
    uint32_t v = patch.p[pi];
    const pinfo_t *f = &PINFO[pi];
    if (f->kind == K_ENUM) {
        *put_s(b, f->names[(v >> 5) & 3u]) = 0;
    } else if (f->kind == K_BI) {
        int32_t x = ((int32_t)v - 64) * 50 / 63;         /* -5.0 .. +5.0 */
        uint32_t a = (uint32_t)(x < 0 ? -x : x);
        *b++ = x < 0 ? '-' : '+';
        b = put_u(b, a / 10u);
        *b++ = '.';
        *put_u(b, a % 10u) = 0;
    } else {
        uint32_t x = (v * 100u + 63u) / 127u;            /* 0.0 .. 10.0 */
        b = put_u(b, x / 10u);
        *b++ = '.';
        *put_u(b, x % 10u) = 0;
    }
}

static void draw_head(uint32_t pg)
{
    char s[8], *p = s;
    cv_begin(240, 24, C_BLACK);
    cv_text(6, 4, &FONT_S, PAGE[pg].name, C_ACC);
    p = put_u(p, pg + 1u);
    *p++ = '/';
    *put_u(p, NPAGE) = 0;
    cv_text(234 - (int32_t)text_w(&FONT_S, s), 4, &FONT_S, s, C_GRY);
    cv_rect(0, 22, 240, 1, C_ACC);
    cv_blit(0, 0);
}

static void draw_knobs(uint32_t pg)             /* four columns: label, value, a bar */
{
    uint32_t k;
    cv_begin(240, 44, C_BLACK);
    for (k = 0; k < 4u; k++) {
        const char *l = PINFO[PAGE[pg].p[k]].label;
        char v[12];
        value_text(PAGE[pg].p[k], v);
        cv_text((int32_t)(k * 60u + 30u) - (int32_t)text_w(&FONT_S, l) / 2, 2, &FONT_S, l, C_GRY);
        cv_text((int32_t)(k * 60u + 30u) - (int32_t)text_w(&FONT_S, v) / 2, 24, &FONT_S, v, C_WHITE);
    }
    cv_blit(0, 34);
    cv_begin(240, 64, C_BLACK);
    for (k = 0; k < 4u; k++) {
        uint32_t pi = PAGE[pg].p[k], v = patch.p[pi];
        int32_t x = (int32_t)(k * 60u + 22u);
        cv_rect(x, 0, 16, 64, C_BAR);
        if (PINFO[pi].kind == K_ENUM) {
            cv_rect(x, (int32_t)(48u - ((v >> 5) & 3u) * 16u), 16, 16, C_ACC);
        } else if (PINFO[pi].kind == K_BI) {
            int32_t d = ((int32_t)v - 64) / 2;
            if (d >= 0) cv_rect(x, 32 - d, 16, d + 1, C_ACC);
            else cv_rect(x, 32, 16, -d, C_ACC);
        } else {
            int32_t h = (int32_t)(v / 2u);
            cv_rect(x, 64 - h, 16, h, C_ACC);
        }
    }
    cv_blit(0, 84);
    lcd_fill(0, 148, 240, 36, C_BLACK);
}

static void draw_cables(uint32_t sel)           /* the patch panel: eight cables, the chosen one lit */
{
    uint32_t half, r;
    for (half = 0; half < 2u; half++) {
        cv_begin(240, 64, C_BLACK);
        for (r = 0; r < 4u; r++) {
            uint32_t c = half * 4u + r, src = patch.cable[c][0], dst = patch.cable[c][1];   /* (its two ends: any jacks) */
            char n[3] = {(char)('1' + c), 0, 0};
            uint16_t col = c == sel ? C_WHITE : src && dst ? C_ACC : C_GRY;
            if (c == sel)
                cv_rect(0, (int32_t)(r * 16u), 240, 16, C_SEL);
            cv_text(6, (int32_t)(r * 16u), &FONT_S, n, C_GRY);
            cv_text(26, (int32_t)(r * 16u), &FONT_S, src || dst ? (src ? jack_name(src) : "(loose)") : "-", col);
            cv_text(116, (int32_t)(r * 16u), &FONT_S, ">", C_GRY);
            cv_text(136, (int32_t)(r * 16u), &FONT_S, src || dst ? (dst ? jack_name(dst) : "(loose)") : "-", col);
        }
        cv_blit(0, (int32_t)(34u + half * 64u));
    }
    draw_text_box(0, 166, 240, &FONT_S, "K1 cable K2 K3 its ends K4 pull", C_GRY, 1);
}

static void draw_foot(uint32_t dirty)
{
    char s[40], *p = s;
    uint32_t i;
    if (set.preset + 1u < 10u) *p++ = '0';
    p = put_u(p, set.preset + 1u);
    *p++ = ' ';
    for (i = 0; i < sizeof patch.name && patch.name[i]; i++) *p++ = patch.name[i];
    if (dirty) *p++ = '*';
    *p = 0;
    draw_text_box(0, 190, 240, &FONT_S, s, C_WHITE, 1);
}

static void draw_status(uint32_t pct)
{
    char s[40], *p = s;
    int32_t oct = (int8_t)set.oct;
    p = put_s(p, "OCT ");
    *p++ = oct < 0 ? '-' : '+';
    *p++ = (char)('0' + (oct < 0 ? -oct : oct));
    p = put_s(p, hold_on ? " HOLD" : "");
    if (ctl.wheel) {
        int32_t wv = ctl.wheel * 50 / 127;
        p = put_s(p, wv < 0 ? " WHL-" : " WHL+");
        p = put_u(p, (uint32_t)(wv < 0 ? -wv : wv) / 10u);
        *p++ = '.';
        p = put_u(p, (uint32_t)(wv < 0 ? -wv : wv) % 10u);
    }
    p = put_s(p, " CPU ");
    p = put_u(p, pct);
    *p++ = '%';
    *p = 0;
    draw_text_box(0, 214, 240, &FONT_S, s, C_GRY, 1);
}

/* ---- MIDI in */
static uint32_t idle_ok, edited, midi_edit;

static void midi_in(void)
{
    uint8_t st, d1, d2;
    while (midi_get(&st, &d1, &d2) != 0) {
        uint32_t ty = st & 0xF0u;
        if (st >= 0xF0u)
            continue;
        if (ty == 0x90u && d2) play(d1);
        else if (ty == 0x80u || ty == 0x90u) stop(d1);
        else if (ty == 0xE0u) {                  /* the bend: +-2 semitones */
            bend = ((int32_t)(d1 | (uint32_t)d2 << 7) - 8192) / 16;
            notes_update();
        } else if (ty == 0xB0u) {
            if (d1 == 1u) { ctl.wheel = d2; midi_edit |= 0x100u; }
            else if (d1 == 2u) { ctl.wheel = ((int32_t)d2 - 64) * 2; midi_edit |= 0x100u; }   /* CC 2: the whole wheel, 64 = 0 V */
            else if (d1 == 64u) ctl.button = d2 >= 64u;
            else if (d1 >= 16u && d1 < 16u + MS_NPARAM) { patch.p[d1 - 16u] = d2 & 127u; midi_edit = (midi_edit & 0x100u) | 1u; }
            else if (d1 == 123u) { nheld = 0; hold_on = 0; notes_update(); }
        } else if (ty == 0xC0u && d1 < NPRESET) {
            midi_edit = (midi_edit & 0x100u) | (2u + d1);   /* a program change: the preset */
        }
    }
}
/* the panel on the computer patching: a whole new set of cables (ms20_link.h); as a knob moved over MIDI would be */
static int app_sysex(const uint8_t *p, uint32_t n)
{
    if (n < 6u || p[0] != LINK_ID || p[5] != LINK_CABLES)
        return 0;                               /* not ours: the update code's, or nobody's */
    if (!link_cables_take(p, n, patch.cable))
        midi_edit = (midi_edit & 0x100u) | 1u;  /* (the main loop redraws and marks the sound edited) */
    return 1;
}
static void app_idle(void)
{
    if (idle_ok)
        midi_in();
}

static void turn(uint32_t pi, int32_t e)        /* a knob: e detents */
{
    int32_t v = patch.p[pi];
    if (PINFO[pi].kind == K_ENUM) {
        v = (v >> 5) + e;
        v = v < 0 ? 0 : v > 3 ? 3 : v;
        v = W(v);
    } else {
        v += e * (e > 2 || e < -2 ? 4 : 2);     /* a fast turn goes further */
        v = v < 0 ? 0 : v > 127 ? 127 : v;
    }
    patch.p[pi] = (uint8_t)v;
}

/* ---- the panel link (ms20_link.h): the patch to a computer, one way. STATE when something changes (at most every
 * 30 ms while a knob turns) and every second; LIVE (the key, the wheel, the switch, the lamps) when it changes, at most
 * every 33 ms, and every second. A message the USB cannot take now is tried again on the next pass. */
static void link_service(uint32_t now)
{
    static ms20_patch_t sent;
    static link_meta_t sent_m;
    static link_live_t sent_l;
    static uint32_t t_state, t_live, beat_state, beat_live, primed;
    uint8_t b[LINK_MAX];
    link_meta_t m;
    link_live_t l;
    m.preset = set.preset;
    m.flags = (uint8_t)((hold_on ? 1u : 0u) | (edited ? 2u : 0u) | LINK_TAKES_CABLES);
    m.octave = (uint8_t)((int8_t)set.oct + 3);
    l.gate = (uint8_t)(ctl.gate != 0u);
    l.note = (uint8_t)(last_note < 128u ? last_note : 127u);
    l.wheel = ctl.wheel;
    l.button = (uint8_t)(ctl.button != 0u);
    l.lamps = syn.lamp;
    if (!primed || memcmp(&sent, &patch, sizeof patch) || memcmp(&sent_m, &m, sizeof m)) {
        if ((!primed || now - t_state >= 30u) && !sysex_send(b, link_state(b, &patch, &m))) {
            memcpy(&sent, &patch, sizeof patch);
            sent_m = m;
            t_state = beat_state = now;
            primed = 1;
        }
    } else if (now - beat_state >= 1000u && !sysex_send(b, link_state(b, &patch, &m))) {
        beat_state = now;
    }
    if (memcmp(&sent_l, &l, sizeof l)) {
        if (now - t_live >= 33u && !sysex_send(b, link_live(b, &l))) {
            sent_l = l;
            t_live = beat_live = now;
        }
    } else if (now - beat_live >= 1000u && !sysex_send(b, link_live(b, &l))) {
        beat_live = now;
    }
}

/* the patch page's KNOB 2 / KNOB 3: one end of the chosen cable to the next jack (any jack, or none: a loose end). A jack
 * takes one plug, so one already in it comes out (that cable keeps its other end, loose) */
static void plug_end(uint32_t c, uint32_t end, int32_t e)
{
    uint32_t j = (uint32_t)((int32_t)patch.cable[c][end] + e + 4 * (int32_t)MS_NJACK) % MS_NJACK, k, m;
    if (j && j == patch.cable[c][end ^ 1u])          /* (not both ends in one jack: step past it) */
        j = (uint32_t)((int32_t)j + (e > 0 ? 1 : -1) + (int32_t)MS_NJACK) % MS_NJACK;
    patch.cable[c][end] = (uint8_t)j;
    for (k = 0; k < MS_NCABLE; k++)
        for (m = 0; m < 2u; m++)
            if (j && (k != c || m != end) && patch.cable[k][m] == j)
                patch.cable[k][m] = 0;
}

#define KEY0 53u                                /* key 0 = F3 */
static void app_main(void)
{
    uint32_t prev = 0, k, page = 4, sel = 0, redraw = 7, t_change = 0, set_dirty = 0, bank_dirty = 0, t_cpu = 0, pct_drawn = ~0u;
    uint32_t rec_midi = 0;
    uint8_t key_note[27] = {0};
    if (settings_load(&set, sizeof set) || (int8_t)set.oct < -3 || (int8_t)set.oct > 3 || set.preset >= NPRESET)
        set.oct = 0, set.preset = 1;
    if (bank_load())
        memcpy(bank, FACTORY, sizeof bank);
    load_preset(set.preset);
    lcd_fill(0, 0, 240, 240, C_BLACK);

    for (;;) {
        uint32_t keys, down, up, rel, b;
        int32_t oct = (int8_t)set.oct, e;
        uint32_t base = (uint32_t)((int32_t)KEY0 + 12 * oct);
        platform_poll();

        keys = fm1_in.notes;
        down = keys & ~prev;
        up = prev & ~keys;
        prev = keys;
        for (k = 0; k < 27u; k++) {
            if (down >> k & 1u) { key_note[k] = (uint8_t)(base + k); play(key_note[k]); midi_send(0x90u, key_note[k], 100); }
            if (up >> k & 1u) { stop(key_note[k]); midi_send(0x80u, key_note[k], 0); }
        }

        b = fm1_input_edges(&rel);
        if (b & (1u << BTN_OCT_DOWN) && oct > -3) { set.oct = (uint8_t)(oct - 1); set_dirty = 1; t_change = fm1_ms; redraw |= 4u; }
        if (b & (1u << BTN_OCT_UP) && oct < 3) { set.oct = (uint8_t)(oct + 1); set_dirty = 1; t_change = fm1_ms; redraw |= 4u; }
        if (b & (1u << BTN_HOME)) { page = page == 0u ? 1u : page == 1u ? 2u : 0u; redraw |= 3u; }
        if (b & (1u << BTN_FX)) { page = page == 4u ? 3u : 4u; redraw |= 3u; }
        if (b & (1u << BTN_ENV)) { page = page == 6u ? 7u : 6u; redraw |= 3u; }
        if (b & (1u << BTN_LFO)) { page = 5u; redraw |= 3u; }
        if (b & (1u << BTN_EDIT)) { page = page == PG_PATCH ? 8u : PG_PATCH; redraw |= 3u; }
        if (b & (1u << BTN_PLAY)) { hold_on = !hold_on; notes_update(); redraw |= 4u; }
        if (b & (1u << BTN_SAVE)) {
            memcpy(&bank[set.preset], &patch, sizeof patch);
            bank_dirty = 1;
            edited = 0;
            t_change = fm1_ms;
            redraw |= 4u;
        }
        if ((b | rel) & (1u << BTN_REC))        /* (CC 64 does the same from outside) */
            ctl.button = (fm1_in.buttons >> BTN_REC) & 1u;
        (void)rec_midi;

        if ((e = fm1_enc_take(ENC_SELECT)) != 0) {
            page = (uint32_t)((int32_t)page + e + 4 * (int32_t)NPAGE) % NPAGE;
            redraw |= 3u;
        }
        e = fm1_enc_take(ENC_PRESETS);
        if ((midi_edit & 0xFFu) >= 2u) {         /* a program change */
            e = (int32_t)((midi_edit & 0xFFu) - 2u) - (int32_t)set.preset;
            if (!e) { load_preset(set.preset); edited = 0; redraw |= 6u; }
            midi_edit &= 0x100u;
        }
        if (e != 0) {
            int32_t p = (int32_t)set.preset + e;
            set.preset = (uint8_t)(p < 0 ? 0 : p >= (int32_t)NPRESET ? (int32_t)NPRESET - 1 : p);
            load_preset(set.preset);
            edited = 0;
            set_dirty = 1;
            t_change = fm1_ms;
            redraw |= 6u;
        }
        if ((e = fm1_enc_take(ENC_ALGORITHM)) != 0) {   /* the wheel: -5 .. +5 V */
            int32_t wv = ctl.wheel + e * (e > 1 || e < -1 ? 8 : 4);   /* 32 detents each way; a fast turn goes further */
            ctl.wheel = wv < -127 ? -127 : wv > 127 ? 127 : wv;
            redraw |= 4u;
        }
        for (k = 0; k < 4u; k++) {
            if ((e = fm1_enc_take(ENC_KNOB1 + k)) == 0)
                continue;
            if (page != PG_PATCH) {
                turn(PAGE[page].p[k], e);
            } else if (k == 0u) {
                sel = (uint32_t)((int32_t)sel + e + 64) % MS_NCABLE;
                redraw |= 2u;
                continue;
            } else if (k == 1u) {
                plug_end(sel, 0u, e);
            } else if (k == 2u) {
                plug_end(sel, 1u, e);
            } else if (e < 0) {
                patch.cable[sel][0] = patch.cable[sel][1] = 0;
            } else {
                continue;
            }
            if (!edited) redraw |= 4u;
            edited = 1;
            redraw |= 2u;
        }

        midi_in();
        if (midi_edit & 0x100u) { midi_edit &= ~0x100u; redraw |= 4u; }
        if (midi_edit == 1u) {                   /* a CC moved a knob */
            midi_edit = 0;
            if (!edited) redraw |= 4u;
            edited = 1;
            redraw |= 2u;
        }

        for (k = 0; k < 27u; k++)
            fm1_led_key(KEY_LED(k), ctl.gate && last_note == base + k);
        fm1_led_key(BTN_OCT_DOWN, oct < 0);
        fm1_led_key(BTN_OCT_UP, oct > 0);
        fm1_led_key(BTN_HOME, page < 3u);
        fm1_led_key(BTN_FX, page == 3u || page == 4u);
        fm1_led_key(BTN_LFO, page == 5u);
        fm1_led_key(BTN_ENV, page == 6u || page == 7u);
        fm1_led_key(BTN_EDIT, page >= 8u);
        fm1_led_key(BTN_PLAY, hold_on);
        fm1_led_key(BTN_REC, ctl.button);
        fm1_led_key(BTN_SAVE, edited);

        link_service(fm1_ms);
        idle_ok = 1;
        if (redraw & 1u) { lcd_fill(0, 24, 240, 166, C_BLACK); draw_head(page); }
        if (redraw & 2u) { if (page == PG_PATCH) draw_cables(sel); else draw_knobs(page); }
        if (redraw & 4u) { draw_foot(edited); pct_drawn = ~0u; }
        redraw = 0;
        if (fm1_ms - t_cpu > 500u || pct_drawn == ~0u) {   /* the render's worst time in the last half second, of its 5.8 ms */
            uint32_t pct = cpu_peak / 58u;
            if (fm1_ms - t_cpu > 500u) { cpu_peak = 0; t_cpu = fm1_ms; }
            if (pct != pct_drawn) { pct_drawn = pct; draw_status(pct); }
        }
        idle_ok = 0;

        if ((set_dirty || bank_dirty) && quiet() && fm1_ms - t_change > 2000u) {   /* when silent: an erase stalls the sound */
            if (set_dirty) settings_save(&set, sizeof set);
            if (bank_dirty) bank_save();
            set_dirty = bank_dirty = 0;
        }
    }
}
