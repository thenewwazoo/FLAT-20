/* SPDX-License-Identifier: GPL-3.0-only */
/* The engine (firmware/src/ms20.h) against what the MS-20's circuit does: pitch in Hz / V, the trigger inputs, the
 * filters' slopes and where they sing, the envelopes' voltages and times, the patch panel's quirks, and that nothing
 * blows up whatever the knobs and cables.
 *   cc -O2 -Wall -Ifirmware/src -o build/host/ms20_test tests/ms20_test.c -lm && build/host/ms20_test */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms20.h"

#define W(i) ((i) * 32 + 16)
#define K(x) ((uint8_t)((x) * 12.7f + 0.5f))
static int fails, checks;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static ms20_t syn;
static ms20_ctl_t ctl;
static float buf[1 << 19], tap[1 << 19];
static int tap_src;
static uint32_t blk = 32;                        /* frames a call (1: a jack's voltage sample by sample; slow) */

static ms20_patch_t init_patch(void)             /* one sawtooth at 8', everything open, EG2 an organ's */
{
    ms20_patch_t p;
    memset(&p, 0, sizeof p);
    p.p[P_V1WAVE] = W(1); p.p[P_V1SCALE] = W(2); p.p[P_V2PITCH] = 64; p.p[P_V2SCALE] = W(1); p.p[P_TUNE] = 64;
    p.p[P_MIX1] = 127; p.p[P_LP_CUT] = 127; p.p[P_MG_WAVE] = 64; p.p[P_MG_RATE] = 64; p.p[P_E2_SUS] = 127; p.p[P_VOLUME] = 127;
    return p;
}
static void cable(ms20_patch_t *p, int i, int src, int dst) { p->cable[i][0] = MS_JACK_OUT(src); p->cable[i][1] = MS_JACK_IN(dst); }
static void join(ms20_patch_t *p, int i, int a, int b) { p->cable[i][0] = (uint8_t)a; p->cable[i][1] = (uint8_t)b; }   /* any two jacks; 0: a loose end */
/* what a jack joined to a source settles at: the source behind rs, the input's own termination (ms20.h's MS_TERM) */
static double loaded(double v, double rs, int dst) { double g = 1 / rs, gt = 1 / MS_TERM[dst][1]; return (v * g + MS_TERM[dst][0] * gt) / (g + gt); }
static void fresh(void) { ms20_init(&syn); memset(&ctl, 0, sizeof ctl); ctl.note = 60 * 256; tap_src = 0; blk = 32; }
static void render(const ms20_patch_t *p, uint32_t n)   /* into buf (SIGNAL OUT, volts) and tap (a jack's volts) */
{
    uint32_t i, k;
    for (i = 0; i < n; i += blk) {
        ms20_render(&syn, p, &ctl, buf + i, blk);
        for (k = 0; k < blk; k++) { buf[i + k] *= MS_VFS; tap[i + k] = syn.sv[tap_src]; }
    }
}
static void run(const ms20_patch_t *p, double s) { render(p, (uint32_t)(s * MS_OUT_FS) & ~31u); }
#define N(s) ((uint32_t)((s) * MS_OUT_FS) & ~31u)

static double pitch(const float *x, uint32_t n)  /* rising zero crossings, interpolated */
{
    double first = -1, last = 0, mean = 0;
    uint32_t i, c = 0;
    for (i = 0; i < n; i++) mean += x[i];
    mean /= n;
    for (i = 1; i < n; i++)
        if (x[i - 1] - mean < 0 && x[i] - mean >= 0) {
            double t = i - 1 + (mean - x[i - 1]) / (x[i] - x[i - 1]);
            if (first < 0) first = t;
            last = t;
            c++;
        }
    return c > 1 ? MS_OUT_FS * (c - 1) / (last - first) : 0;
}
static double rms(const float *x, uint32_t n)
{
    double a = 0;
    uint32_t i;
    for (i = 0; i < n; i++) a += (double)x[i] * x[i];
    return sqrt(a / n);
}
static double level_at(const float *x, uint32_t n, double f)   /* the amplitude of one frequency */
{
    double re = 0, im = 0;
    uint32_t i;
    for (i = 0; i < n; i++) {
        double w = 0.5 - 0.5 * cos(2 * M_PI * i / n);
        re += x[i] * w * cos(2 * M_PI * f * i / MS_OUT_FS);
        im += x[i] * w * sin(2 * M_PI * f * i / MS_OUT_FS);
    }
    return 4 * sqrt(re * re + im * im) / n;
}
static double dB(double a) { return 20 * log10(a + 1e-12); }
static double cents(double f, double ref) { return 1200 * log2(f / ref); }
static double peak(const float *x, uint32_t n) { double m = 0; uint32_t i; for (i = 0; i < n; i++) if (fabs(x[i]) > m) m = fabs(x[i]); return m; }

static void test_pitch(void)
{
    ms20_patch_t p = init_patch();
    static const int note[] = {48, 57, 69, 84};
    static const double hz[] = {130.8128, 220.0, 440.0, 1046.502};
    int i;
    for (i = 0; i < 4; i++) {
        fresh(); ctl.note = note[i] * 256; ctl.gate = 1;
        run(&p, 0.8);
        CHECK(fabs(cents(pitch(buf + N(0.3), N(0.5)), hz[i])) < 1.5, "8', note %d: %.2f Hz, not %.2f", note[i], pitch(buf + N(0.3), N(0.5)), hz[i]);
    }
    for (i = 0; i < 4; i++) {                      /* SCALE: an octave a step, 32' two below 8' */
        fresh(); ctl.note = 69 * 256; ctl.gate = 1; p.p[P_V1SCALE] = (uint8_t)W(i);
        run(&p, 0.8);
        CHECK(fabs(cents(pitch(buf + N(0.3), N(0.5)), 110.0 * (1 << i))) < 1.5, "VCO 1 scale %d: %.2f Hz", i, pitch(buf + N(0.3), N(0.5)));
    }
    p = init_patch(); p.p[P_MIX1] = 0; p.p[P_MIX2] = 127;
    for (i = 0; i < 4; i++) {                      /* VCO 2: 16' 8' 4' 2' */
        fresh(); ctl.note = 57 * 256; ctl.gate = 1; p.p[P_V2SCALE] = (uint8_t)W(i);
        run(&p, 0.8);
        CHECK(fabs(cents(pitch(buf + N(0.3), N(0.5)), 110.0 * (1 << i))) < 1.5, "VCO 2 scale %d: %.2f Hz", i, pitch(buf + N(0.3), N(0.5)));
    }
    /* PITCH: +-1.115 octave (R55 75 k onto R47 100 at 18 mV an octave); MASTER TUNE: +-0.177 */
    fresh(); ctl.note = 57 * 256; ctl.gate = 1; p.p[P_V2SCALE] = W(1); p.p[P_V2PITCH] = 127;
    run(&p, 0.8);
    CHECK(fabs(cents(pitch(buf + N(0.3), N(0.5)), 220.0) - 1200 * 1.115 * 63 / 63.5) < 15, "PITCH at +5: %+.0f cents", cents(pitch(buf + N(0.3), N(0.5)), 220.0));
    p = init_patch(); p.p[P_TUNE] = 127;
    fresh(); ctl.note = 69 * 256; ctl.gate = 1;
    run(&p, 0.8);
    CHECK(fabs(cents(pitch(buf + N(0.3), N(0.5)), 440.0) - 210.5) < 4, "MASTER TUNE at +5: %+.0f cents", cents(pitch(buf + N(0.3), N(0.5)), 440.0));
}

static void test_hz_per_volt(void)
{
    /* VCO 1 + 2 CV IN is linear: the wheel's volts are the frequency. 130.81 Hz a volt at 8'; at 0 V and below, silence */
    ms20_patch_t p = init_patch();
    cable(&p, 0, SRC_WHEEL, DST_VCO_CV);
    fresh(); ctl.gate = 1; ctl.wheel = 51;           /* 2.008 V */
    run(&p, 1.0);
    /* (the wheel's 2.5 k into the VCO's ~400 k input: 0.6 % lower than the wheel's own voltage, as on the instrument) */
    CHECK(fabs(cents(pitch(buf + N(0.5), N(0.5)), 130.8128 * loaded(51 * 5.0 / 127, 2500, DST_VCO_CV))) < 3, "wheel at 2 V into VCO CV: %.2f Hz", pitch(buf + N(0.5), N(0.5)));
    ctl.wheel = 102;
    run(&p, 1.0);
    CHECK(fabs(cents(pitch(buf + N(0.5), N(0.5)), 130.8128 * loaded(102 * 5.0 / 127, 2500, DST_VCO_CV))) < 3, "wheel at 4 V: %.2f Hz (twice the volts, twice the hertz)", pitch(buf + N(0.5), N(0.5)));
    ctl.wheel = -60;
    run(&p, 1.0);
    CHECK(rms(buf + N(0.5), N(0.5)) < 0.005, "a negative CV stops the VCO: rms %.4f V", rms(buf + N(0.5), N(0.5)));
    /* the keyboard's own voltage: 1 V at the lowest C, doubling an octave */
    p = init_patch(); fresh(); tap_src = SRC_KBD_CV; ctl.gate = 1; ctl.note = 48 * 256;
    run(&p, 0.2); CHECK(fabs(tap[N(0.19)] - 1.0) < 1e-3, "KBD CV at C3: %.4f V", tap[N(0.19)]);
    ctl.note = 84 * 256;
    run(&p, 0.2); CHECK(fabs(tap[N(0.19)] - 8.0) < 1e-2, "KBD CV at C6: %.4f V", tap[N(0.19)]);
    /* FM is exponential on top of that: 1.178 octaves a volt with the knob at 10. EG1 reaches the VCOs as -5 V at
     * rest: with EG1 / EXT up, the pitch sits 5.9 octaves low until the envelope has risen */
    p = init_patch(); p.p[P_FM_EG] = 127; p.p[P_E1_ATK] = 0;
    cable(&p, 0, SRC_WHEEL, DST_FREQ);
    fresh(); ctl.note = 69 * 256; ctl.gate = 1; ctl.wheel = -25;       /* -0.984 V */
    run(&p, 1.0);
    CHECK(fabs(cents(pitch(buf + N(0.5), N(0.5)), 440.0) - 1200 * 1.178 * loaded(-25 * 5.0 / 127, 2500, DST_FREQ)) < 6, "FREQ at -0.98 V, knob 10: %+.0f cents", cents(pitch(buf + N(0.5), N(0.5)), 440.0));
}

static void test_levels(void)
{
    /* one sawtooth at 10 through open filters: 7.5 V p-p at the VCO, a third of it past R4 and the level pot's load,
     * 1 / 427 into the high-pass ... about 1.1 V p-p at SIGNAL OUT ("2 V p-p max") */
    ms20_patch_t p = init_patch();
    double a, b;
    fresh(); ctl.note = 60 * 256; ctl.gate = 1;
    run(&p, 1.0);
    a = peak(buf + N(0.5), N(0.5));
    CHECK(a > 0.4 && a < 0.8, "a sawtooth at SIGNAL OUT: %.2f V peak", a);
    tap_src = SRC_VCO1; run(&p, 0.2);
    CHECK(fabs(peak(tap, N(0.2)) - 3.75) < 0.4, "the sawtooth itself: %.2f V peak", peak(tap, N(0.2)));
    /* both sawtooths are as loud as each other (an MS-20 mini's are within 1 dB) */
    p.p[P_MIX1] = 0; p.p[P_MIX2] = 127; fresh(); ctl.gate = 1; run(&p, 1.0); b = rms(buf + N(0.5), N(0.5));
    p = init_patch(); fresh(); ctl.gate = 1; run(&p, 1.0); a = rms(buf + N(0.5), N(0.5));
    CHECK(fabs(dB(a / b)) < 1.0, "VCO 1's sawtooth against VCO 2's: %+.1f dB", dB(a / b));
    /* the triangle has almost no even harmonics and its third is 15 dB or more down (a flattened tip: more than an ideal triangle's 19) */
    p.p[P_V1WAVE] = W(0); fresh(); ctl.note = 57 * 256; ctl.gate = 1; run(&p, 1.5);
    a = dB(level_at(buf + N(0.5), N(1.0), 660) / level_at(buf + N(0.5), N(1.0), 220));
    CHECK(a < -14 && a > -30, "the triangle's third harmonic: %.1f dB", a);
    /* PW: half the cycle at 0, a sliver at 10 (the fundamental falls by more than 12 dB) */
    p.p[P_V1WAVE] = W(2); p.p[P_V1PW] = 0; fresh(); ctl.note = 57 * 256; ctl.gate = 1; run(&p, 1.0); a = level_at(buf + N(0.5), N(0.5), 220);
    b = dB(level_at(buf + N(0.5), N(0.5), 440) / a);
    CHECK(b < -30, "a square has no second harmonic: %.1f dB", b);
    p.p[P_V1PW] = 127; fresh(); ctl.note = 57 * 256; ctl.gate = 1; run(&p, 1.0);
    CHECK(dB(level_at(buf + N(0.5), N(0.5), 220) / a) < -12, "PW at 10 thins the pulse: %.1f dB", dB(level_at(buf + N(0.5), N(0.5), 220) / a));
}

static void test_filters(void)
{
    ms20_patch_t p = init_patch();
    double f, a, b;
    int i;
    /* the adjustment procedure: PEAK at 10, CUTOFF at 5: 500 Hz, both filters */
    p.p[P_MIX1] = 0; p.p[P_LP_CUT] = K(5); p.p[P_LP_PEAK] = 127;
    fresh(); ctl.gate = 1; run(&p, 2.0); f = pitch(buf + N(1.0), N(1.0));
    CHECK(fabs(cents(f, 500)) < 25, "the low-pass sings at %.1f Hz with CUTOFF at 5", f);
    p = init_patch(); p.p[P_MIX1] = 0; p.p[P_HP_CUT] = K(5); p.p[P_HP_PEAK] = 127;
    fresh(); ctl.gate = 1; run(&p, 2.0); f = pitch(buf + N(1.0), N(1.0));
    CHECK(fabs(cents(f, 500)) < 25, "the high-pass sings at %.1f Hz with CUTOFF at 5", f);
    /* from one stop to the other: 13 Hz .. 15.3 kHz on a vintage MS-20 */
    p = init_patch(); p.p[P_MIX1] = 0; p.p[P_LP_PEAK] = 127; p.p[P_LP_CUT] = 0;
    fresh(); ctl.gate = 1; run(&p, 4.0); f = pitch(buf + N(2.0), N(2.0));
    CHECK(f > 10 && f < 16, "CUTOFF at 0: %.1f Hz", f);
    p.p[P_LP_CUT] = 127; fresh(); ctl.gate = 1; run(&p, 1.0); f = pitch(buf + N(0.5), N(0.5));
    CHECK(f > 13500 && f < 17000, "CUTOFF at 10: %.0f Hz", f);
    /* where PEAK starts it: not at 8 (the Da Funk patch has both at 8 and no whistle), by 9 */
    for (i = 0; i < 2; i++) {
        p = init_patch(); p.p[P_MIX1] = 0;
        p.p[i ? P_HP_CUT : P_LP_CUT] = K(5); p.p[i ? P_HP_PEAK : P_LP_PEAK] = K(8);
        fresh(); ctl.gate = 1; run(&p, 3.0);
        CHECK(rms(buf + N(2.0), N(1.0)) < 0.01, "%s PEAK 8 does not sing: %.4f V", i ? "high-pass" : "low-pass", rms(buf + N(2.0), N(1.0)));
        p.p[i ? P_HP_PEAK : P_LP_PEAK] = K(9.2);
        fresh(); ctl.gate = 1; run(&p, 3.0);
        CHECK(rms(buf + N(2.0), N(1.0)) > 0.05, "%s PEAK 9.2 sings: %.4f V", i ? "high-pass" : "low-pass", rms(buf + N(2.0), N(1.0)));
    }
    /* slopes, with white noise through each filter at CUTOFF 5 (500 Hz), PEAK 0: the low-pass 12 dB an octave, the
     * high-pass 6 (Stinchcombe 2006, section 7; Doepfer) */
    /* (quietly: at a normal level the amplifier's diodes, which come after the filtering, fill the stop band with
     * what they make of the pass band, and the slope measures shallower) */
    p = init_patch(); p.p[P_V1WAVE] = W(3); p.p[P_MIX1] = K(1.5);
    fresh(); ctl.gate = 1; run(&p, 11.0);
    {
        static float ref[1 << 19];
        uint32_t n = N(10.0), k;
        double lo4 = 0, lo8 = 0, lo2 = 0, hi1 = 0, hi2 = 0, r4 = 0, r8 = 0, r2 = 0, r1 = 0, rq = 0;
        memcpy(ref, buf + N(1.0), n * sizeof(float));
        p.p[P_LP_CUT] = K(5);
        fresh(); ctl.gate = 1; run(&p, 11.0);
        /* band powers by a bank of narrow probes around each centre (the noise is the same sequence each run) */
        for (k = 0; k < 40; k++) {
            double d = pow(2.0, ((int)k - 20) / 80.0);
            lo2 += pow(level_at(buf + N(1.0), n, 2000 * d), 2); r2 += pow(level_at(ref, n, 2000 * d), 2);
            lo4 += pow(level_at(buf + N(1.0), n, 4000 * d), 2); r4 += pow(level_at(ref, n, 4000 * d), 2);
            lo8 += pow(level_at(buf + N(1.0), n, 8000 * d), 2); r8 += pow(level_at(ref, n, 8000 * d), 2);
        }
        /* against the circuit's own answer: two real poles (3300 p against 1000 p, R2 = 1.5 R1: the s term is 2.607),
         * at 500 Hz, over the same with CUTOFF at 10 (15.35 kHz), which the reference went through */
        {
            static const double fq[3] = {2000, 4000, 8000};
            double got[3], want[3];
            int j;
            got[0] = 10 * log10(lo2 / r2); got[1] = 10 * log10(lo4 / r4); got[2] = 10 * log10(lo8 / r8);
            for (j = 0; j < 3; j++) {
                double x = fq[j] / 498.8, y = fq[j] / 15350.0;
                want[j] = -10 * log10(pow(1 - x * x, 2) + pow(2.607 * x, 2)) + 10 * log10(pow(1 - y * y, 2) + pow(2.607 * y, 2));
                CHECK(fabs(got[j] - want[j]) < 1.0, "low-pass at %.0f Hz: %.1f dB, the circuit's %.1f", fq[j], got[j], want[j]);
            }
            a = got[1] - got[0]; b = got[2] - got[1];
            CHECK(a < -9.5 && b < -9.0, "low-pass slope against the open filter: %.1f and %.1f dB an octave", a, b);
        }
        p.p[P_LP_CUT] = 127; p.p[P_HP_CUT] = K(8.5);                     /* 6.4 kHz */
        fresh(); ctl.gate = 1; run(&p, 11.0);
        for (k = 0; k < 40; k++) {
            double d = pow(2.0, ((int)k - 20) / 80.0);
            hi1 += pow(level_at(buf + N(1.0), n, 400 * d), 2); r1 += pow(level_at(ref, n, 400 * d), 2);
            hi2 += pow(level_at(buf + N(1.0), n, 800 * d), 2); rq += pow(level_at(ref, n, 800 * d), 2);
        }
        a = 10 * log10(hi2 / rq) - 10 * log10(hi1 / r1);
        CHECK(a > 4.8 && a < 7.2, "high-pass slope: %.1f dB an octave", a);
    }
    /* the diodes are in the signal's way: a louder input comes out with less than its share (the mixer's two VCOs
     * against one), even with no PEAK at all */
    p = init_patch(); p.p[P_V1WAVE] = W(2); p.p[P_V2WAVE] = W(1); p.p[P_MIX1] = K(6);
    fresh(); ctl.note = 45 * 256; ctl.gate = 1; run(&p, 1.0); a = level_at(buf + N(0.5), N(0.5), 110);
    p.p[P_MIX1] = 127; p.p[P_MIX2] = 127;                            /* the same pulse twice, in step: 2 x, and louder still by the knob */
    fresh(); ctl.note = 45 * 256; ctl.gate = 1; run(&p, 1.0); b = level_at(buf + N(0.5), N(0.5), 110);
    {
        double want = dB(2 * ms_level(1.f, 0.0637f) / ms_level(K(6) / 127.f, 0.0637f));
        CHECK(dB(b / a) < want - 1.0 && dB(b / a) > want - 9.0, "the filters squash: %.1f dB louder in, %.1f dB louder out", want, dB(b / a));
    }
}

static void test_envelopes(void)
{
    ms20_patch_t p = init_patch();
    uint32_t i;
    double t;
    /* EG1's jacks: OUT 0 V at rest and +5 V at the top, REV OUT +5 V and 0 V; EG2's REV OUT 0 V and -5 V with SUSTAIN at 0 */
    p.p[P_E1_ATK] = K(3); p.p[P_E1_REL] = K(3);
    fresh(); tap_src = SRC_EG1;
    run(&p, 0.1); CHECK(fabs(tap[N(0.09)]) < 0.01, "EG1 OUT at rest: %.2f V", tap[N(0.09)]);
    ctl.gate = 1; run(&p, 3.0); CHECK(fabs(tap[N(2.9)] - 5.0) < 0.05, "EG1 OUT, key held: %.2f V", tap[N(2.9)]);
    for (i = 0; i < N(3.0) && tap[i] < 5.0 * (1 - exp(-1.0)); i++) ;
    t = i / MS_OUT_FS;                               /* ATTACK at 3: 2 M x taper x 3.3 uF */
    CHECK(fabs(t / (ms_taper(K(3) / 127.f) * 6.6 + 400 * 3.3e-6) - 1) < 0.05, "EG1 ATTACK at 3: %.3f s to 63 %%", t);
    fresh(); tap_src = SRC_EG1_REV;
    run(&p, 0.1); CHECK(fabs(tap[N(0.09)] - 5.0) < 0.01, "EG1 REV OUT at rest: %.2f V", tap[N(0.09)]);
    /* DELAY: nothing for 0.69 x 2 M x taper x 6.8 uF, then the attack */
    p.p[P_E1_DELAY] = K(4); p.p[P_E1_ATK] = 0; fresh(); tap_src = SRC_EG1; ctl.gate = 1; run(&p, 3.0);
    for (i = 0; i < N(3.0) && tap[i] < 2.5; i++) ;
    t = ms_taper(K(4) / 127.f) * 2e6 * 6.8e-6 * 0.6931;
    CHECK(fabs(i / MS_OUT_FS / t - 1) < 0.03, "EG1 DELAY at 4: %.3f s (%.3f)", i / MS_OUT_FS, t);

    p = init_patch(); p.p[P_E2_ATK] = K(4); p.p[P_E2_DEC] = K(4); p.p[P_E2_SUS] = 0; p.p[P_E2_REL] = K(3);
    fresh(); tap_src = SRC_EG2_REV; ctl.gate = 1; run(&p, 6.0);
    for (i = 1, t = 0; i < N(6.0); i++) if (tap[i] < t) t = tap[i];
    CHECK(fabs(t + 5.07) < 0.03, "EG2 REV OUT goes down to %.2f V", t);
    for (i = 0; i < N(6.0) && tap[i] > -5.0; i++) ;   /* the attack is an RC toward 8.87 V, cut off at 5.07: 0.83 RC to 5 V */
    t = (ms_taper(K(4) / 127.f) * 2e6 + 678) * 6.8e-6 * log(8.87 / (8.87 - 5.0));
    CHECK(fabs(i / MS_OUT_FS / t - 1) < 0.03, "EG2 ATTACK at 4: %.3f s (%.3f)", i / MS_OUT_FS, t);
    /* SUSTAIN is what the filters' EG2 is measured from: REV OUT sits at +SUSTAIN at rest, at 0 V while a key is held */
    p.p[P_E2_ATK] = 0; p.p[P_E2_DEC] = K(1); p.p[P_E2_SUS] = 127;
    fresh(); tap_src = SRC_EG2_REV;
    run(&p, 0.1); CHECK(fabs(tap[N(0.09)] - 4.96) < 0.02, "EG2 REV OUT at rest, SUSTAIN 10: %+.2f V", tap[N(0.09)]);
    ctl.gate = 1; run(&p, 2.0); CHECK(fabs(tap[N(1.9)]) < 0.03, "EG2 REV OUT, key held, SUSTAIN 10: %+.2f V", tap[N(1.9)]);
    /* ... so with EG2 / EXT up and SUSTAIN up the low-pass is shut before the note and open during it */
    p = init_patch(); p.p[P_MIX1] = 0; p.p[P_LP_PEAK] = 127; p.p[P_LP_CUT] = K(6); p.p[P_LP_EG] = K(8); p.p[P_E2_REL] = K(5);
    fresh(); cable(&p, 0, SRC_WHEEL, DST_GAIN); ctl.wheel = 127;        /* (the VCA held open, to hear the filter sing) */
    run(&p, 2.0);
    {
        double f0 = pitch(buf + N(1.0), N(1.0)), f1;
        ctl.gate = 1; run(&p, 2.0); f1 = pitch(buf + N(1.0), N(1.0));
        CHECK(fabs(log2(f1 / f0) - 4.96 * MS20_CUT_OCTV * ms_amount(K(8) / 127.f, 1.081f)) < 0.15, "EG2 - SUSTAIN on the cutoff: %.0f Hz at rest, %.0f Hz held", f0, f1);
    }
    /* HOLD keeps EG2 (not EG1) on after the key: 0.69 x 2 M x taper x 10 uF */
    p = init_patch(); p.p[P_E2_HOLD] = K(3); p.p[P_E2_REL] = 0;
    fresh(); tap_src = SRC_EG2_REV; ctl.gate = 1; run(&p, 0.2); ctl.gate = 0; run(&p, 3.0);
    for (i = 0; i < N(3.0) && fabs(tap[i]) < 1.0; i++) ;               /* (REV OUT: 0 V while held, +4.96 V after) */
    t = ms_taper(K(3) / 127.f) * 2e6 * 10e-6 * 0.6931;
    CHECK(fabs(i / MS_OUT_FS / t - 1) < 0.03, "HOLD at 3: %.3f s (%.3f)", i / MS_OUT_FS, t);
}

static void test_vca(void)
{
    /* nothing passes until EG2 is over the transistor's base voltage; INITIAL GAIN opens it without EG2 (diode-OR) */
    ms20_patch_t p = init_patch();
    double a, b;
    fresh(); run(&p, 0.5);
    CHECK(rms(buf + N(0.2), N(0.3)) < 1e-4, "no key, no sound: %.5f V", rms(buf + N(0.2), N(0.3)));
    cable(&p, 0, SRC_WHEEL, DST_GAIN); ctl.wheel = 127; run(&p, 0.5); a = rms(buf + N(0.2), N(0.3));
    ctl.wheel = 0; ctl.gate = 1; run(&p, 0.5); b = rms(buf + N(0.2), N(0.3));
    CHECK(a > 0.1 && fabs(dB(a / b)) < 2.5, "INITIAL GAIN at 5 V against a held key: %+.1f dB", dB(a / b));
    ctl.wheel = 127; run(&p, 0.5);
    CHECK(fabs(dB(rms(buf + N(0.2), N(0.3)) / b)) < 1.5, "INITIAL GAIN and EG2 together are no louder than the larger: %+.1f dB", dB(rms(buf + N(0.2), N(0.3)) / b));
    ctl.gate = 0; ctl.wheel = 10; run(&p, 0.5);       /* 0.39 V: under the base voltage (and D22's) */
    CHECK(rms(buf + N(0.2), N(0.3)) < 1e-3, "INITIAL GAIN at 0.4 V: still shut (%.5f V)", rms(buf + N(0.2), N(0.3)));
    /* the amplifier after it rolls off at 8.8 kHz (C34 100 p across R118 180 k) */
    p = init_patch(); p.p[P_V1WAVE] = W(3);
    fresh(); ctl.gate = 1; run(&p, 6.0);
    {
        double lo = 0, hi = 0;
        int k;
        for (k = 0; k < 60; k++) { lo += pow(level_at(buf + N(1.0), N(5.0), 900 + 7 * k), 2); hi += pow(level_at(buf + N(1.0), N(5.0), 8842 + 7 * k), 2); }
        /* (-3.0 dB of its own, on top of the low-pass's -4.5 dB there even at CUTOFF 10: two real poles, 15.3 kHz) */
        CHECK(fabs(10 * log10(hi / lo) + 7.5) < 1.6, "8.8 kHz against 1 kHz: %.1f dB", 10 * log10(hi / lo));
    }
}

static void test_triggers(void)
{
    ms20_patch_t p = init_patch();
    uint32_t i, edges = 0;
    /* KBD TRIG OUT: +5 V, to ground while a key is down */
    fresh(); tap_src = SRC_KBD_TRIG; run(&p, 0.1); CHECK(tap[N(0.09)] > 4.5, "KBD TRIG OUT at rest: %.1f V", tap[N(0.09)]);
    ctl.gate = 1; run(&p, 0.1); CHECK(tap[N(0.09)] < 0.5, "KBD TRIG OUT, key down: %.1f V", tap[N(0.09)]);
    /* a plug in TRIG IN takes the keyboard off: the MG's rectangle (0 / +5 V) triggers while it is low */
    p.p[P_MG_RATE] = K(3); p.p[P_E2_SUS] = 0; p.p[P_E2_DEC] = K(1.5);
    cable(&p, 0, SRC_MG_RECT, DST_TRIG);
    fresh(); tap_src = SRC_EG2_REV; run(&p, 2.0);
    for (i = 1; i < N(2.0); i++) if (tap[i - 1] > -2.5 && tap[i] <= -2.5) edges++;
    CHECK(edges >= 10 && edges <= 14, "the MG at 6 Hz triggers EG2 %u times in 2 s, no key", edges);
    /* the momentary switch is a contact to ground: into TRIG IN it is a key; released, the input floats high */
    p = init_patch(); cable(&p, 0, SRC_BUTTON, DST_TRIG);
    fresh(); ctl.gate = 1; run(&p, 0.3); CHECK(rms(buf + N(0.1), N(0.2)) < 1e-3, "switch open in TRIG IN: the keyboard no longer triggers");
    ctl.button = 1; run(&p, 0.3); CHECK(rms(buf + N(0.1), N(0.2)) > 0.1, "switch closed: the note sounds");
    /* EG1 TRIG IN alone: EG2 still follows the keyboard */
    p = init_patch(); cable(&p, 0, SRC_BUTTON, DST_EG1_TRIG);
    fresh(); tap_src = SRC_EG1; ctl.gate = 1; run(&p, 0.3);
    CHECK(tap[N(0.29)] < 0.1 && rms(buf + N(0.1), N(0.2)) > 0.1, "a plug in EG1 TRIG IN: EG1 waits (%.2f V), EG2 plays", tap[N(0.29)]);
}

static void test_panel(void)
{
    ms20_patch_t p = init_patch();
    uint32_t i, moved = 0, held = 0;
    double a, b;
    /* the MG: 0.1 Hz .. 20 Hz, +-2.7 V; the rectangle +5 V while the triangle falls */
    p.p[P_MG_RATE] = 127; fresh(); tap_src = SRC_MG_TRI; run(&p, 2.0);
    CHECK(fabs(pitch(tap, N(2.0)) / 20.2 - 1) < 0.04 && fabs(peak(tap, N(2.0)) - 2.7) < 0.02, "MG at 10: %.2f Hz, %.2f V", pitch(tap, N(2.0)), peak(tap, N(2.0)));
    p.p[P_MG_RATE] = 0; fresh(); tap_src = SRC_MG_TRI; render(&p, N(11.8));
    CHECK(fabs(pitch(tap, N(11.8)) / 0.096 - 1) < 0.08, "MG at 0: %.3f Hz", pitch(tap, N(11.8)));
    p.p[P_MG_RATE] = K(5); p.p[P_MG_WAVE] = 127; fresh(); tap_src = SRC_MG_RECT; run(&p, 2.0);
    for (i = 0, a = 0; i < N(2.0); i++) a += tap[i] > 2.5;
    b = pitch(tap, N(2.0));
    p.p[P_MG_WAVE] = K(5); fresh(); tap_src = SRC_MG_RECT; run(&p, 2.0);
    CHECK(a / N(2.0) < 0.05 && fabs(b / pitch(tap, N(2.0)) - 1) < 0.08, "WAVE FORM at 10: the rectangle is high %.1f %% of the time, the rate %.2f against %.2f Hz", 100 * a / N(2.0), b, pitch(tap, N(2.0)));
    /* "sample and hold": follows while CLOCK is high (or unplugged), holds while it is low */
    p = init_patch(); p.p[P_MG_RATE] = K(1); cable(&p, 0, SRC_WHITE, DST_SH_IN);
    fresh(); tap_src = SRC_SH; blk = 1; run(&p, 0.5);
    for (i = 1; i < N(0.5); i++) moved += tap[i] != tap[i - 1];
    CHECK(moved > N(0.5) * 9 / 10, "S&H with no clock follows its input");
    cable(&p, 1, SRC_MG_RECT, DST_SH_CLOCK);
    fresh(); tap_src = SRC_SH; blk = 1; run(&p, 2.0);
    for (i = 1, moved = 0; i < N(2.0); i++) { moved += tap[i] != tap[i - 1]; held += tap[i] == tap[i - 1]; }
    CHECK(moved > N(2.0) / 4 && held > N(2.0) / 4, "S&H on the MG's rectangle: follows %u samples, holds %u", moved, held);
    /* the modulation VCA is opened by EG1 unless something is in CONTROL INPUT, and it is slow (a photocell) */
    p = init_patch(); p.p[P_MG_RATE] = 127; cable(&p, 0, SRC_MG_TRI, DST_MVCA_IN);
    fresh(); tap_src = SRC_MVCA; run(&p, 0.5); a = peak(tap + N(0.3), N(0.2));
    ctl.gate = 1; run(&p, 0.5); b = peak(tap + N(0.3), N(0.2));
    CHECK(a < 0.02 && fabs(b - 2.7) < 0.3, "the modulation VCA: %.3f V with EG1 at rest, %.2f V with a key down", a, b);
    ctl.gate = 0; run(&p, 0.02);
    CHECK(peak(tap, N(0.02)) > 1.0, "... and still open 20 ms after EG1 has gone (%.2f V)", peak(tap, N(0.02)));
    /* a plug in VCO 2 CV IN takes VCO 2 off the keyboard */
    p = init_patch(); p.p[P_MIX1] = 0; p.p[P_MIX2] = 127; cable(&p, 0, SRC_WHEEL, DST_VCO2_CV);
    fresh(); ctl.gate = 1; ctl.note = 72 * 256; ctl.wheel = 51; run(&p, 1.0);
    CHECK(fabs(cents(pitch(buf + N(0.5), N(0.5)), 130.8128 * loaded(51 * 5.0 / 127, 2500, DST_VCO2_CV))) < 3, "VCO 2 from the wheel: %.2f Hz whatever the key", pitch(buf + N(0.5), N(0.5)));
    /* PORTAMENTO glides only while a key is down: let go half way and the pitch stays there */
    p = init_patch(); p.p[P_PORTA] = 127; p.p[P_E2_REL] = 127;
    fresh(); ctl.note = 48 * 256; ctl.gate = 1; run(&p, 3.0);
    ctl.note = 72 * 256; run(&p, 0.3); ctl.gate = 0; tap_src = SRC_KBD_CV; run(&p, 1.0);
    CHECK(tap[N(0.99)] > 1.5 && tap[N(0.99)] < 3.5 && fabs(tap[N(0.99)] - tap[N(0.1)]) < 1e-4, "a glide from 1 V to 4 V, let go after 0.3 s: stays at %.2f V", tap[N(0.99)]);
    /* the external signal processor's F-V converter tracks in Hz / V: twice the frequency, twice the volts */
    p = init_patch(); p.p[P_V1WAVE] = W(0); p.p[P_ESP_LEVEL] = K(0.2); p.p[P_ESP_LOW] = K(2); p.p[P_ESP_HIGH] = K(4); p.p[P_ESP_CV] = 127;
    cable(&p, 0, SRC_VCO1, DST_ESP_IN);
    fresh(); tap_src = SRC_ESP_FV; blk = 1; ctl.gate = 1; ctl.note = 48 * 256; run(&p, 2.0);
    for (i = N(1.0), a = 0; i < N(2.0); i++) a += tap[i] / N(1.0);
    ctl.note = 60 * 256; run(&p, 2.0);
    for (i = N(1.0), b = 0; i < N(2.0); i++) b += tap[i] / N(1.0);
    CHECK(fabs(b / a - 2) < 0.03 && fabs(a - 2.94) < 0.1, "F-V: %.2f V at 131 Hz, %.2f V at 262 Hz", a, b);
}

static void test_fuzz(void)                         /* any knobs, any cables, keys and wheel: finite, bounded, and it recovers */
{
    ms20_patch_t p;
    uint32_t seed = 12345, r, i, k, bad = 0;
    double worst = 0;
    fresh();
    for (r = 0; r < 400; r++) {
        for (i = 0; i < MS_NPARAM; i++) { seed = seed * 1664525u + 1013904223u; p.p[i] = (uint8_t)(seed >> 25); }
        for (i = 0; i < MS_NCABLE; i++) {                       /* any jacks, either kind, loose ends, the same jack twice */
            seed = seed * 1664525u + 1013904223u; p.cable[i][0] = (uint8_t)((seed >> 8) % MS_NJACK);
            seed = seed * 1664525u + 1013904223u; p.cable[i][1] = (uint8_t)((seed >> 8) % MS_NJACK);
        }
        seed = seed * 1664525u + 1013904223u;
        ctl.note = (int32_t)((seed >> 8) % 96) * 256 + 12 * 256; ctl.gate = (seed >> 3) & 1; ctl.wheel = (int32_t)((seed >> 16) % 255) - 127; ctl.button = (seed >> 5) & 1;
        render(&p, 4096);
        for (k = 0; k < 4096; k++) {
            if (!(buf[k] - buf[k] == 0)) bad++;
            if (fabs(buf[k]) > worst) worst = fabs(buf[k]);
        }
    }
    CHECK(!bad && worst <= 13.6, "400 random patches: %u samples not finite, the largest %.1f V", bad, worst);
    p = init_patch(); ctl.note = 69 * 256; ctl.gate = 1; ctl.wheel = 0; ctl.button = 0;
    run(&p, 1.5);
    CHECK(fabs(cents(pitch(buf + N(1.0), N(0.5)), 440)) < 2, "and the plain sound after them: %.2f Hz", pitch(buf + N(1.0), N(0.5)));
}

/* The patch panel as wiring (ms20.h, ms20_nets): what a real patch panel does follows from the jacks' own circuits */
static void test_wiring(void)
{
    ms20_patch_t p = init_patch();
    double a, b;
    uint32_t i, moved;
    /* a dummy plug (a cable to nothing) in TRIG IN: the input sits at its pull-up, off; the keys no longer play */
    join(&p, 0, MS_JACK_IN(DST_TRIG), 0);
    fresh(); ctl.gate = 1; run(&p, 0.5);
    CHECK(rms(buf + N(0.2), N(0.3)) < 1e-4, "a dummy plug in TRIG IN: a key down plays nothing (%.5f V)", rms(buf + N(0.2), N(0.3)));
    /* ... in CONTROL INPUT: the modulation VCA sits shut (100 k to ground), whatever EG 1 does */
    p = init_patch(); p.p[P_MG_RATE] = 127; cable(&p, 0, SRC_MG_TRI, DST_MVCA_IN); join(&p, 1, MS_JACK_IN(DST_MVCA_CTL), 0);
    fresh(); tap_src = SRC_MVCA; ctl.gate = 1; run(&p, 0.5);
    CHECK(peak(tap + N(0.3), N(0.2)) < 0.01, "a dummy plug in CONTROL INPUT: the VCA stays shut (%.3f V)", peak(tap + N(0.3), N(0.2)));
    /* ... in VCO 2 CV IN: off the keyboard, at R207's 0.27 V: a low crawl */
    p = init_patch(); p.p[P_MIX1] = 0; p.p[P_MIX2] = 127; join(&p, 0, MS_JACK_IN(DST_VCO2_CV), 0);
    fresh(); ctl.gate = 1; ctl.note = 72 * 256; run(&p, 2.0);
    CHECK(fabs(cents(pitch(buf + N(1.0), N(1.0)), 130.8128 * 0.27)) < 5, "a dummy plug in VCO 2 CV IN: %.1f Hz whatever the key", pitch(buf + N(1.0), N(1.0)));
    /* the momentary switch into S&H CLOCK: held, the clock is grounded and the S&H holds; let go, it follows again */
    p = init_patch(); cable(&p, 0, SRC_WHITE, DST_SH_IN); cable(&p, 1, SRC_BUTTON, DST_SH_CLOCK);
    fresh(); tap_src = SRC_SH; blk = 1; ctl.button = 1; run(&p, 0.2);
    for (i = 1, moved = 0; i < N(0.2); i++) moved += tap[i] != tap[i - 1];
    CHECK(moved < 10, "the switch held on S&H CLOCK: it holds (%u changes)", moved);
    ctl.button = 0; run(&p, 0.2);
    for (i = 1, moved = 0; i < N(0.2); i++) moved += tap[i] != tap[i - 1];
    CHECK(moved > N(0.2) / 2, "let go: it follows (%u changes)", moved);
    /* two inputs joined: S&H CLOCK's 4.7 V through 69 k against CONTROL INPUT's 110 k to ground: 2.9 V, the VCA part open */
    p = init_patch(); p.p[P_MG_RATE] = 127; cable(&p, 0, SRC_MG_TRI, DST_MVCA_IN); join(&p, 1, MS_JACK_IN(DST_SH_CLOCK), MS_JACK_IN(DST_MVCA_CTL));
    fresh(); tap_src = SRC_MVCA; run(&p, 0.6);
    a = peak(tap + N(0.4), N(0.2));
    {
        double c = loaded(4.69, 68.75e3, DST_MVCA_CTL) * 0.2072 - 0.0363;
        b = 2.7 * 0.909 * 0 + 2.7 * pow(c, 0.75);
    }
    CHECK(fabs(a - b) < 0.15, "S&H CLOCK joined to CONTROL INPUT: the VCA passes %.2f V of the MG's 2.7 (%.2f by the circuit)", a, b);
    /* two outputs joined: nothing takes the result; the sound is as with no cable */
    p = init_patch(); fresh(); ctl.gate = 1; run(&p, 0.5); a = rms(buf + N(0.2), N(0.3));
    join(&p, 0, MS_JACK_OUT(SRC_MG_TRI), MS_JACK_OUT(SRC_EG1)); fresh(); ctl.gate = 1; run(&p, 0.5); b = rms(buf + N(0.2), N(0.3));
    CHECK(fabs(a - b) < 1e-6, "MG OUT joined to EG 1 OUT: nothing changes (%.4f, %.4f V)", a, b);
    /* a dummy plug in an output: nothing at all */
    join(&p, 0, MS_JACK_OUT(SRC_MG_TRI), 0); fresh(); ctl.gate = 1; run(&p, 0.5);
    CHECK(fabs(rms(buf + N(0.2), N(0.3)) - a) < 1e-6, "a dummy plug in an output: nothing changes");
}

int main(void)
{
    test_pitch();
    test_hz_per_volt();
    test_levels();
    test_filters();
    test_envelopes();
    test_vca();
    test_triggers();
    test_panel();
    test_wiring();
    test_fuzz();
    printf("%d checks, %d failed\n", checks, fails);
    return fails != 0;
}
