/* APU: two pulse channels (one with sweep), wave channel, noise channel,
 * frame sequencer driven by the DIV counter, and a box-filter resampler
 * with the DMG's output high-pass filter. */
#include "gb.h"
#include <string.h>

static const uint8_t duty_wave[4] = { 0x01, 0x81, 0x87, 0x7E };

/* ------------------------------------------------------------ envelopes */

static inline void env_clock(uint8_t *vol, uint8_t period, uint8_t *timer, bool up) {
    if (!period) return;
    if (*timer > 0) (*timer)--;
    if (*timer == 0) {
        *timer = period;
        if (up && *vol < 15) (*vol)++;
        else if (!up && *vol > 0) (*vol)--;
    }
}

/* ---------------------------------------------------------------- sweep */

static unsigned sweep_calc(GBSquare *s) {
    unsigned delta = s->sw_shadow >> s->sw_shift;
    unsigned nf;
    if (s->sw_neg) { nf = s->sw_shadow - delta; s->sw_neg_used = true; }
    else nf = s->sw_shadow + delta;
    if (nf > 2047) s->on = false;
    return nf;
}

static void sweep_clock(GBSquare *s) {
    if (s->sw_timer > 0) s->sw_timer--;
    if (s->sw_timer == 0) {
        s->sw_timer = s->sw_period ? s->sw_period : 8;
        if (s->sw_on && s->sw_period) {
            unsigned nf = sweep_calc(s);
            if (nf <= 2047 && s->sw_shift) {
                s->sw_shadow = (uint16_t)nf;
                s->freq = (uint16_t)nf;
                sweep_calc(s);
            }
        }
    }
}

/* ------------------------------------------------------- frame sequencer */

static inline void len_clock(bool *on, int *length, bool en) {
    if (en && *length > 0 && --*length == 0) *on = false;
}

void apu_frame_step(GB *g) {
    GBApu *a = &g->apu;
    if (!a->power) return;
    uint8_t step = a->fs_step;
    a->fs_step = (step + 1) & 7;
    if (!(step & 1)) {
        len_clock(&a->sq1.on, &a->sq1.length, a->sq1.len_en);
        len_clock(&a->sq2.on, &a->sq2.length, a->sq2.len_en);
        len_clock(&a->wave.on, &a->wave.length, a->wave.len_en);
        len_clock(&a->noise.on, &a->noise.length, a->noise.len_en);
    }
    if (step == 2 || step == 6) sweep_clock(&a->sq1);
    if (step == 7) {
        env_clock(&a->sq1.vol, a->sq1.env_period, &a->sq1.env_timer, a->sq1.env_up);
        env_clock(&a->sq2.vol, a->sq2.env_period, &a->sq2.env_timer, a->sq2.env_up);
        env_clock(&a->noise.vol, a->noise.env_period, &a->noise.env_timer, a->noise.env_up);
    }
}

/* ------------------------------------------------------------- channels */

static inline int noise_period(const GBNoise *n) {
    return (n->divisor ? n->divisor * 16 : 8) << n->shift;
}

static inline void square_tick(GBSquare *s) {
    s->timer -= 4;
    while (s->timer <= 0) {
        s->timer += (2048 - s->freq) * 4;
        s->duty_pos = (s->duty_pos + 1) & 7;
    }
}

static inline void wave_tick(GBWave *w) {
    w->just_read = false;
    if (!w->on) return;
    for (int t = 0; t < 4; t++) {
        if (--w->timer <= 0) {
            w->timer = (2048 - w->freq) * 2;
            w->pos = (w->pos + 1) & 31;
            uint8_t b = w->ram[w->pos >> 1];
            w->sample = (w->pos & 1) ? (b & 15) : (b >> 4);
            w->just_read = t >= 2;
        }
    }
}

static inline void noise_tick(GBNoise *n) {
    n->timer -= 4;
    while (n->timer <= 0) {
        n->timer += noise_period(n);
        if (n->shift < 14) {
            unsigned x = (n->lfsr ^ (n->lfsr >> 1)) & 1;
            n->lfsr = (uint16_t)((n->lfsr >> 1) | (x << 14));
            if (n->narrow) n->lfsr = (uint16_t)((n->lfsr & ~0x40u) | (x << 6));
        }
    }
}

void apu_tick(GB *g) {
    GBApu *a = &g->apu;
    float l = 0, r = 0;
    if (a->power) {
        square_tick(&a->sq1);
        square_tick(&a->sq2);
        wave_tick(&a->wave);
        noise_tick(&a->noise);

        int d[4];
        bool dac[4] = { a->sq1.dac, a->sq2.dac, a->wave.dac, a->noise.dac };
        d[0] = (a->sq1.on && ((duty_wave[a->sq1.duty] >> a->sq1.duty_pos) & 1)) ? a->sq1.vol : 0;
        d[1] = (a->sq2.on && ((duty_wave[a->sq2.duty] >> a->sq2.duty_pos) & 1)) ? a->sq2.vol : 0;
        d[2] = (a->wave.on && a->wave.vol_code) ? a->wave.sample >> (a->wave.vol_code - 1) : 0;
        d[3] = (a->noise.on && !(a->noise.lfsr & 1)) ? a->noise.vol : 0;
        for (int i = 0; i < 4; i++) {
            if (!dac[i] || !(a->chan_mask & (1 << i))) continue;
            float v = (float)d[i] * (1.0f / 7.5f) - 1.0f;
            if (a->nr51 & (0x10 << i)) l += v;
            if (a->nr51 & (0x01 << i)) r += v;
        }
        l *= (float)(((a->nr50 >> 4) & 7) + 1) * (1.0f / 32.0f);
        r *= (float)((a->nr50 & 7) + 1) * (1.0f / 32.0f);
    }
    a->acc_l += l; a->acc_r += r; a->acc_n++;
    a->phase += a->rate;
    if (a->phase >= GB_CPU_HZ / 4) {
        a->phase -= GB_CPU_HZ / 4;
        float inl = a->acc_l / (float)a->acc_n, inr = a->acc_r / (float)a->acc_n;
        a->acc_l = a->acc_r = 0; a->acc_n = 0;
        float outl = inl - a->cap_l, outr = inr - a->cap_r;
        a->cap_l = inl - outl * a->hp_factor;
        a->cap_r = inr - outr * a->hp_factor;
        if (a->buf_n < GB_AUDIO_BUF) {
            a->buf[a->buf_n * 2] = outl;
            a->buf[a->buf_n * 2 + 1] = outr;
            a->buf_n++;
        }
    }
}

/* ------------------------------------------------------------ registers */

static const uint8_t read_mask[0x30] = {
    0x80, 0x3F, 0x00, 0xFF, 0xBF, /* NR10-NR14 */
    0xFF, 0x3F, 0x00, 0xFF, 0xBF, /* NR20-NR24 */
    0x7F, 0xFF, 0x9F, 0xFF, 0xBF, /* NR30-NR34 */
    0xFF, 0xFF, 0x00, 0x00, 0xBF, /* NR40-NR44 */
    0x00, 0x00, 0x70,             /* NR50-NR52 */
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

uint8_t apu_read(GB *g, uint16_t addr) {
    GBApu *a = &g->apu;
    if (addr >= 0xFF30) {
        if (a->wave.on) return a->wave.just_read ? a->wave.ram[a->wave.pos >> 1] : 0xFF;
        return a->wave.ram[addr - 0xFF30];
    }
    if (addr == 0xFF26)
        return (uint8_t)((a->power ? 0x80 : 0) | 0x70 | (a->sq1.on ? 1 : 0) | (a->sq2.on ? 2 : 0) |
                         (a->wave.on ? 4 : 0) | (a->noise.on ? 8 : 0));
    int i = addr - 0xFF10;
    return a->reg[i] | read_mask[i];
}

/* shared NRx4 handling of the length-enable bit; returns true if triggered */
static bool len_write(GBApu *a, bool *on, int *length, bool *len_en, int max, uint8_t v) {
    bool was = *len_en;
    bool no_clock_next = a->fs_step & 1; /* the next sequencer step does not clock length */
    *len_en = v & 0x40;
    if (no_clock_next && !was && *len_en && *length > 0) {
        if (--*length == 0 && !(v & 0x80)) *on = false;
    }
    if (v & 0x80) {
        if (*length == 0) {
            *length = max;
            if (no_clock_next && *len_en) (*length)--;
        }
        return true;
    }
    return false;
}

static void square_trigger(GBSquare *s, bool sweep) {
    s->on = s->dac;
    s->timer = (2048 - s->freq) * 4;
    s->env_timer = s->env_period ? s->env_period : 8;
    s->vol = s->env_init;
    if (sweep) {
        s->sw_shadow = s->freq;
        s->sw_timer = s->sw_period ? s->sw_period : 8;
        s->sw_on = s->sw_period || s->sw_shift;
        s->sw_neg_used = false;
        if (s->sw_shift) sweep_calc(s);
    }
}

static void power_off(GBApu *a) {
    int l1 = a->sq1.length, l2 = a->sq2.length, l3 = a->wave.length, l4 = a->noise.length;
    uint8_t ram[16];
    memcpy(ram, a->wave.ram, 16);
    memset(a->reg, 0, 0x17);
    memset(&a->sq1, 0, sizeof a->sq1);
    memset(&a->sq2, 0, sizeof a->sq2);
    memset(&a->wave, 0, sizeof a->wave);
    memset(&a->noise, 0, sizeof a->noise);
    memcpy(a->wave.ram, ram, 16);
    /* DMG keeps the length counters across power cycles */
    a->sq1.length = l1; a->sq2.length = l2; a->wave.length = l3; a->noise.length = l4;
    a->nr50 = a->nr51 = 0;
    a->power = false;
}

void apu_write(GB *g, uint16_t addr, uint8_t v) {
    GBApu *a = &g->apu;
    if (addr >= 0xFF30) {
        if (a->wave.on) { if (a->wave.just_read) a->wave.ram[a->wave.pos >> 1] = v; }
        else a->wave.ram[addr - 0xFF30] = v;
        return;
    }
    if (addr == 0xFF26) {
        if (!(v & 0x80) && a->power) power_off(a);
        else if ((v & 0x80) && !a->power) { a->power = true; a->fs_step = 0; }
        return;
    }
    if (addr > 0xFF26) return;
    if (!a->power) {
        /* only the length counters are writable while powered down (DMG) */
        switch (addr) {
        case 0xFF11: a->sq1.length = 64 - (v & 63); break;
        case 0xFF16: a->sq2.length = 64 - (v & 63); break;
        case 0xFF1B: a->wave.length = 256 - v; break;
        case 0xFF20: a->noise.length = 64 - (v & 63); break;
        default: break;
        }
        return;
    }
    a->reg[addr - 0xFF10] = v;
    switch (addr) {
    /* ---- pulse 1 ---- */
    case 0xFF10:
        a->sq1.sw_period = (v >> 4) & 7;
        a->sq1.sw_shift = v & 7;
        if (a->sq1.sw_neg && !(v & 8) && a->sq1.sw_neg_used) a->sq1.on = false;
        a->sq1.sw_neg = v & 8;
        break;
    case 0xFF11: a->sq1.duty = v >> 6; a->sq1.length = 64 - (v & 63); break;
    case 0xFF12:
        a->sq1.env_init = v >> 4; a->sq1.env_up = v & 8; a->sq1.env_period = v & 7;
        a->sq1.dac = (v & 0xF8) != 0;
        if (!a->sq1.dac) a->sq1.on = false;
        break;
    case 0xFF13: a->sq1.freq = (uint16_t)((a->sq1.freq & 0x700) | v); break;
    case 0xFF14:
        a->sq1.freq = (uint16_t)((a->sq1.freq & 0xFF) | ((v & 7) << 8));
        if (len_write(a, &a->sq1.on, &a->sq1.length, &a->sq1.len_en, 64, v)) square_trigger(&a->sq1, true);
        break;
    /* ---- pulse 2 ---- */
    case 0xFF16: a->sq2.duty = v >> 6; a->sq2.length = 64 - (v & 63); break;
    case 0xFF17:
        a->sq2.env_init = v >> 4; a->sq2.env_up = v & 8; a->sq2.env_period = v & 7;
        a->sq2.dac = (v & 0xF8) != 0;
        if (!a->sq2.dac) a->sq2.on = false;
        break;
    case 0xFF18: a->sq2.freq = (uint16_t)((a->sq2.freq & 0x700) | v); break;
    case 0xFF19:
        a->sq2.freq = (uint16_t)((a->sq2.freq & 0xFF) | ((v & 7) << 8));
        if (len_write(a, &a->sq2.on, &a->sq2.length, &a->sq2.len_en, 64, v)) square_trigger(&a->sq2, false);
        break;
    /* ---- wave ---- */
    case 0xFF1A:
        a->wave.dac = v & 0x80;
        if (!a->wave.dac) a->wave.on = false;
        break;
    case 0xFF1B: a->wave.length = 256 - v; break;
    case 0xFF1C: a->wave.vol_code = (v >> 5) & 3; break;
    case 0xFF1D: a->wave.freq = (uint16_t)((a->wave.freq & 0x700) | v); break;
    case 0xFF1E: {
        GBWave *w = &a->wave;
        w->freq = (uint16_t)((w->freq & 0xFF) | ((v & 7) << 8));
        if (len_write(a, &w->on, &w->length, &w->len_en, 256, v)) {
            if (w->on && w->timer == 2) {
                /* DMG quirk: retriggering while the channel is fetching corrupts wave RAM */
                unsigned idx = ((w->pos + 1) & 31) >> 1;
                if (idx < 4) w->ram[0] = w->ram[idx];
                else memcpy(w->ram, &w->ram[idx & ~3u], 4);
            }
            w->on = w->dac;
            w->pos = 0;
            w->timer = (2048 - w->freq) * 2 + 6;
        }
        break;
    }
    /* ---- noise ---- */
    case 0xFF20: a->noise.length = 64 - (v & 63); break;
    case 0xFF21:
        a->noise.env_init = v >> 4; a->noise.env_up = v & 8; a->noise.env_period = v & 7;
        a->noise.dac = (v & 0xF8) != 0;
        if (!a->noise.dac) a->noise.on = false;
        break;
    case 0xFF22: a->noise.shift = v >> 4; a->noise.narrow = v & 8; a->noise.divisor = v & 7; break;
    case 0xFF23:
        if (len_write(a, &a->noise.on, &a->noise.length, &a->noise.len_en, 64, v)) {
            GBNoise *n = &a->noise;
            n->on = n->dac;
            n->lfsr = 0x7FFF;
            n->timer = noise_period(n);
            n->env_timer = n->env_period ? n->env_period : 8;
            n->vol = n->env_init;
        }
        break;
    case 0xFF24: a->nr50 = v; break;
    case 0xFF25: a->nr51 = v; break;
    default: break;
    }
}

void gb_set_audio_rate(GB *g, uint32_t hz) {
    GBApu *a = &g->apu;
    if (hz < 8000) hz = 8000;
    a->rate = hz;
    /* DMG output capacitor: charge factor 0.999958 per T-cycle */
    float f = 1.0f;
    for (uint32_t i = 0; i < GB_CPU_HZ / hz; i++) f *= 0.999958f;
    a->hp_factor = f;
}

void apu_reset(GB *g) {
    GBApu *a = &g->apu;
    gb_set_audio_rate(g, a->rate);
    a->power = true;
    /* register state after the boot ROM */
    static const uint8_t init[0x17] = {
        0x80, 0xBF, 0xF3, 0xFF, 0xBF, 0xFF, 0x3F, 0x00, 0xFF, 0xBF, 0x7F, 0xFF,
        0x9F, 0xFF, 0xBF, 0xFF, 0xFF, 0x00, 0x00, 0xBF, 0x77, 0xF3, 0xF1
    };
    memcpy(a->reg, init, sizeof init);
    a->nr50 = 0x77; a->nr51 = 0xF3;
    a->sq1.duty = 2; a->sq1.dac = true; a->sq1.on = true;
    a->sq1.env_init = 0xF; a->sq1.env_period = 3; a->sq1.vol = 0;
    a->sq1.freq = 0x7FF; a->sq1.timer = 4;
    a->sq2.timer = 4; a->sq2.freq = 0x7FF;
    a->wave.freq = 0x7FF; a->wave.timer = 2;
    a->noise.lfsr = 0x7FFF; a->noise.timer = 8;
    static const uint8_t wave_init[16] = { 0x84, 0x40, 0x43, 0xAA, 0x2D, 0x78, 0x92, 0x3C,
                                           0x60, 0x59, 0x59, 0xB0, 0x34, 0xB8, 0x2E, 0xDA };
    memcpy(a->wave.ram, wave_init, 16);
}
