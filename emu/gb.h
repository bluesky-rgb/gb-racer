/* Game Boy (DMG) emulator core - public interface and machine state.
 * Freestanding C11: no libc dependencies beyond memcpy/memset. */
#ifndef GB_CORE_H
#define GB_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define GB_W 160
#define GB_H 144
#define GB_CPU_HZ 4194304
#define GB_FRAME_TCYCLES 70224
#define GB_AUDIO_BUF 8192 /* stereo frames */

enum {
    GB_KEY_RIGHT = 0x01, GB_KEY_LEFT = 0x02, GB_KEY_UP = 0x04, GB_KEY_DOWN = 0x08,
    GB_KEY_A = 0x10, GB_KEY_B = 0x20, GB_KEY_SELECT = 0x40, GB_KEY_START = 0x80
};

enum { GB_INT_VBLANK = 1, GB_INT_STAT = 2, GB_INT_TIMER = 4, GB_INT_SERIAL = 8, GB_INT_JOYPAD = 16 };

/* register indices inside cpu.r[] (matches opcode encoding, F in slot 6) */
enum { R_B, R_C, R_D, R_E, R_H, R_L, R_F, R_A };

typedef struct {
    uint8_t r[8];
    uint16_t sp, pc;
    bool ime;
    uint8_t ime_pending;
    bool halted, halt_bug, locked;
} GBCpu;

typedef struct {
    uint16_t div;          /* 16-bit system counter, DIV = high byte */
    uint8_t tima, tma, tac;
    bool overflow_pending; /* TIMA overflowed, reload happens next M-cycle */
    bool reloading;        /* TIMA was reloaded this M-cycle */
} GBTimer;

typedef struct {
    uint8_t lcdc, stat, scy, scx, ly, lyc, bgp, obp0, obp1, wy, wx;
    int line, dot;
    uint8_t mode;          /* mode visible in STAT */
    bool lyc_match, stat_line;
    uint8_t imode;         /* mode as seen by the STAT interrupt logic (can lead `mode`) */
    int mode3_end;         /* dot at which mode 3 ends on this line */
    int render_x;          /* pixels already drawn on this line */
    bool wy_trig;          /* WY==LY seen this frame */
    bool win_drawn;        /* window drew pixels on this line */
    int win_line;
    uint8_t spr[10];
    int nspr;
    bool first_line;       /* first line after LCD enable */
    bool skip_frame;       /* first frame after LCD enable is not shown */
    uint8_t fb[GB_W * GB_H];     /* shades 0..3 being drawn */
    uint8_t front[GB_W * GB_H];  /* last completed frame */
} GBPpu;

typedef struct {
    bool on, dac;
    uint8_t duty, duty_pos;
    uint16_t freq;
    int timer;
    int length; bool len_en;
    uint8_t vol, env_init, env_period, env_timer; bool env_up;
    /* sweep (channel 1 only) */
    uint8_t sw_period, sw_shift, sw_timer; bool sw_neg, sw_on, sw_neg_used;
    uint16_t sw_shadow;
} GBSquare;

typedef struct {
    bool on, dac;
    uint16_t freq;
    int timer;
    int length; bool len_en;
    uint8_t vol_code, pos, sample;
    uint8_t ram[16];
    bool just_read;        /* wave RAM was fetched by the channel this M-cycle */
} GBWave;

typedef struct {
    bool on, dac;
    int timer;
    int length; bool len_en;
    uint8_t vol, env_init, env_period, env_timer; bool env_up;
    uint8_t shift, divisor; bool narrow;
    uint16_t lfsr;
} GBNoise;

typedef struct {
    bool power;
    uint8_t nr50, nr51;
    uint8_t reg[0x30];     /* raw register values FF10..FF3F */
    uint8_t fs_step;       /* frame sequencer: next step to run */
    GBSquare sq1, sq2;
    GBWave wave;
    GBNoise noise;
    /* resampling */
    uint32_t rate, phase;
    float acc_l, acc_r; int acc_n;
    float cap_l, cap_r, hp_factor;
    float buf[GB_AUDIO_BUF * 2];
    int buf_n;
    uint8_t chan_mask;     /* debug: per-channel mute, bit set = audible */
} GBApu;

typedef struct {
    const uint8_t *rom;
    size_t rom_size;
    uint32_t rom_mask;
    uint8_t type;          /* 0 none, 1 MBC1, 2 MBC2, 3 MBC3, 5 MBC5 */
    bool has_ram;
    uint32_t ram_size;
    uint8_t ram[0x20000];
    bool ram_en, mode;
    uint16_t bank; uint8_t bank_hi, ram_bank;
    bool ram_dirty;
} GBCart;

typedef struct GB {
    GBCpu cpu;
    GBTimer timer;
    GBPpu ppu;
    GBApu apu;
    GBCart cart;
    uint8_t vram[0x2000], wram[0x2000], oam[0xA0], hram[0x80];
    uint8_t ie, iflag;
    /* joypad */
    uint8_t keys, p1;
    /* serial */
    uint8_t sb, sc; int serial_bits;
    char serial_out[4096]; int serial_n;
    /* OAM DMA */
    uint8_t dma_reg, dma_pending, dma_idx; bool dma_active; uint16_t dma_src;
    /* bookkeeping */
    uint64_t cycles;       /* T-cycles since reset */
    bool frame_ready;
    uint32_t frame_cycles; /* T-cycles since last frame boundary (LCD off pacing) */
    bool breakpoint;       /* LD B,B executed (mooneye test protocol) */
} GB;

/* core API */
void gb_init(GB *g, const uint8_t *rom, size_t rom_size);
void gb_reset(GB *g);
void gb_run_frame(GB *g);
void gb_set_keys(GB *g, uint8_t keys);
void gb_set_audio_rate(GB *g, uint32_t hz);
const char *gb_cart_title(const GB *g, char out[17]);

/* internals shared between modules */
void gb_tick(GB *g); /* advance hardware one M-cycle (4 T-cycles) */
uint8_t gb_read(GB *g, uint16_t addr);
void gb_write(GB *g, uint16_t addr, uint8_t v);
uint8_t gb_peek(GB *g, uint16_t addr); /* debugger read without side effects/locking */
void gb_cpu_step(GB *g);

void ppu_reset(GB *g);
void ppu_tick(GB *g);  /* 4 dots */
uint8_t ppu_read(GB *g, uint16_t addr);
void ppu_write(GB *g, uint16_t addr, uint8_t v);
static inline bool ppu_vram_locked(const GB *g) { return (g->ppu.lcdc & 0x80) && (g->ppu.mode == 3 || g->ppu.imode == 3); }
bool ppu_oam_locked(const GB *g);
/* writes follow the STAT mode bits; OAM has a one-cycle writable gap between modes 2 and 3 */
static inline bool ppu_vram_wlocked(const GB *g) { return (g->ppu.lcdc & 0x80) && g->ppu.mode == 3; }
static inline bool ppu_oam_wlocked(const GB *g) {
    return (g->ppu.lcdc & 0x80) && (g->ppu.mode == 3 || (g->ppu.mode == 2 && g->ppu.imode == 2));
}

void apu_reset(GB *g);
void apu_tick(GB *g);  /* 4 T-cycles */
void apu_frame_step(GB *g);
uint8_t apu_read(GB *g, uint16_t addr);
void apu_write(GB *g, uint16_t addr, uint8_t v);

#endif
