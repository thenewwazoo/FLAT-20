/* SPDX-License-Identifier: GPL-3.0-only */
/* Standalone CLI renderer for firmware/src/ms20.h (outputs 16-bit 44.1 kHz WAV).
 *   render OUT.wav SECONDS [setting ...] [@MS event ...]
 * Settings (and timed events after @MS):
 *   NAME=X          Knob value (0..10) or switch position (0..3 or name):
 *                   v1wave (tri saw pulse noise) v1pw v1scale (32 16 8 4) porta v2wave (saw sqr pulse ring) v2pitch
 *                   v2scale (16 8 4 2) tune mix1 mix2 fmmg fmeg hpcut hppeak hpmg hpeg lpcut lppeak lpmg lpeg mgwave
 *                   mgrate e1delay e1atk e1rel e2hold e2atk e2dec e2sus e2rel volume espcv esplevel esplow esphigh espthr
 *                   (v2pitch and tune center at 5)
 *   JACK:JACK       Patch cable between any two jacks ("-" for one end = dummy plug).
 *                   Outputs: kbdcv kbdtrig mgtri mgrect eg1 eg1rev eg2rev sh mvca white pink wheel button signal
 *                   phones espamp espbpf espfv espenv esptrig vco1 vco2
 *                   Inputs:  total freq vcocv vco2cv extin hpcut lpcut gain trig eg1trig shin shclock mvcain mvcactl espin
 *   on=NOTE  off    Gate control (MIDI note, fractional allowed; 48 = lowest C)   wheel=V (-5..5)   button=0/1
 * Full scale = ±5 V at SIGNAL OUT (or pass tap=SRC to record a specific output at ±15 V full scale). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms20.h"

static const char *const PN[MS_NPARAM] = {"v1wave", "v1pw", "v1scale", "porta", "v2wave", "v2pitch", "v2scale", "tune", "mix1",
    "mix2", "fmmg", "fmeg", "hpcut", "hppeak", "hpmg", "hpeg", "lpcut", "lppeak", "lpmg", "lpeg", "mgwave", "mgrate",
    "e1delay", "e1atk", "e1rel", "e2hold", "e2atk", "e2dec", "e2sus", "e2rel", "volume", "espcv", "esplevel", "esplow",
    "esphigh", "espthr"};
static const char *const SN[MS_NSRC] = {"-", "kbdcv", "kbdtrig", "mgtri", "mgrect", "eg1", "eg1rev", "eg2rev", "sh", "mvca",
    "white", "pink", "wheel", "button", "signal", "phones", "espamp", "espbpf", "espfv", "espenv", "esptrig", "vco1", "vco2"};
static const char *const DN[MS_NDST] = {"-", "total", "freq", "vcocv", "vco2cv", "extin", "hpcut", "lpcut", "gain", "trig",
    "eg1trig", "shin", "shclock", "mvcain", "mvcactl", "espin"};
static const char *const SW[4][4] = {{"tri", "saw", "pulse", "noise"}, {"32", "16", "8", "4"}, {"saw", "sqr", "pulse", "ring"},
    {"16", "8", "4", "2"}};

static ms20_t syn;
static ms20_ctl_t ctl;
static ms20_patch_t p;
static int tap, ncable;

static int find(const char *const *t, int n, const char *s, size_t len)
{
    int i;
    for (i = 0; i < n; i++)
        if (strlen(t[i]) == len && !strncmp(t[i], s, len))
            return i;
    return -1;
}
/* a jack by name: an output, an input, or "-" (nothing: 0); -1 if none */
static int jack(const char *s, size_t len)
{
    int k;
    if (len == 1 && s[0] == '-') return 0;
    if ((k = find(SN, MS_NSRC, s, len)) > 0) return MS_JACK_OUT(k);
    if ((k = find(DN, MS_NDST, s, len)) > 0) return MS_JACK_IN(k);
    return -1;
}

static void apply(const char *a)
{
    const char *eq = strchr(a, '='), *co = strchr(a, ':');
    int k;
    if (!strcmp(a, "off")) { ctl.gate = 0; return; }
    if (eq && !strncmp(a, "on=", 3)) { ctl.note = (int32_t)(atof(eq + 1) * 256.0 + 0.5); ctl.gate = 1; return; }
    if (eq && !strncmp(a, "wheel=", 6)) { ctl.wheel = (int32_t)(atof(eq + 1) * 25.4); return; }
    if (eq && !strncmp(a, "button=", 7)) { ctl.button = (uint32_t)atoi(eq + 1); return; }
    if (eq && !strncmp(a, "tap=", 4)) { tap = find(SN, MS_NSRC, eq + 1, strlen(eq + 1)); return; }
    if (eq && (k = find(PN, MS_NPARAM, a, (size_t)(eq - a))) >= 0) {
        int sw = k == P_V1WAVE ? 0 : k == P_V1SCALE ? 1 : k == P_V2WAVE ? 2 : k == P_V2SCALE ? 3 : -1;
        if (sw >= 0) {
            int v = find(SW[sw], 4, eq + 1, strlen(eq + 1));
            if (v < 0) v = atoi(eq + 1);
            p.p[k] = (uint8_t)(v * 32 + 16);
        } else {
            double v = atof(eq + 1) * 12.7 + 0.5;
            p.p[k] = (uint8_t)(v < 0 ? 0 : v > 127 ? 127 : v);
        }
        return;
    }
    if (co) {
        int ja = jack(a, (size_t)(co - a)), jb = jack(co + 1, strlen(co + 1));
        if (ja >= 0 && jb >= 0 && (ja || jb) && ncable < (int)MS_NCABLE) { p.cable[ncable][0] = (uint8_t)ja; p.cable[ncable++][1] = (uint8_t)jb; return; }
    }
    fprintf(stderr, "render: what is \"%s\"?\n", a);
    exit(2);
}

int main(int argc, char **argv)
{
    static float buf[64];
    uint32_t n, i, total, hdr[11] = {0x46464952, 0, 0x45564157, 0x20746d66, 16, 0x00010001, 44100, 88200, 0x00100002, 0x61746164, 0};
    int a = 3;
    float peak = 0;
    FILE *fp;
    if (argc < 3) { fprintf(stderr, "render OUT.wav SECONDS [setting ...] [@MS event ...]\n"); return 2; }
    memset(&p, 0, sizeof p);
    p.p[P_V1WAVE] = 48; p.p[P_V1SCALE] = 80; p.p[P_V2WAVE] = 16; p.p[P_V2PITCH] = 64; p.p[P_V2SCALE] = 48; p.p[P_TUNE] = 64;
    p.p[P_MIX1] = 127; p.p[P_LP_CUT] = 127; p.p[P_MG_WAVE] = 64; p.p[P_MG_RATE] = 64; p.p[P_E2_SUS] = 127; p.p[P_VOLUME] = 127;
    ctl.note = 60 * 256;
    for (; a < argc && argv[a][0] != '@'; a++)
        apply(argv[a]);
    ms20_init(&syn);
    total = (uint32_t)(atof(argv[2]) * 44100.0);
    fp = fopen(argv[1], "wb");
    if (!fp) return 1;
    hdr[1] = 36 + total * 2; hdr[10] = total * 2;
    fwrite(hdr, 4, 11, fp);
    for (n = 0; n < total; n += 32) {
        while (a < argc && argv[a][0] == '@' && (uint32_t)(atof(argv[a] + 1) * 44.1) <= n)
            for (a++; a < argc && argv[a][0] != '@'; a++)
                apply(argv[a]);
        if (tap > 0) {                               /* a patch panel output: one sample a block would alias, so 32 blocks of 1 */
            for (i = 0; i < 32; i++) {
                float d;
                ms20_render(&syn, &p, &ctl, &d, 1);
                buf[i] = syn.sv[tap] / 15.f / (MS_VFS / 5.f) / MS_VFS * MS_VFS;
            }
        } else {
            ms20_render(&syn, &p, &ctl, buf, 32);
        }
        for (i = 0; i < 32 && n + i < total; i++) {
            float x = buf[i] * (MS_VFS / 5.f) * 32767.f;
            int16_t v = (int16_t)(x > 32767.f ? 32767.f : x < -32767.f ? -32767.f : x);
            if (buf[i] > peak) peak = buf[i];
            if (-buf[i] > peak) peak = -buf[i];
            fwrite(&v, 2, 1, fp);
        }
    }
    fclose(fp);
    fprintf(stderr, "peak %.3f V\n", peak * (tap > 0 ? 15.f * (MS_VFS / 5.f) : MS_VFS));
    return 0;
}
