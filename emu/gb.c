/* Bus, cartridge mappers, timer, serial, joypad, OAM DMA and frame loop. */
#include "gb.h"
#include <string.h>

/* ------------------------------------------------------------------ cart */

static void cart_setup(GB *g) {
    GBCart *c = &g->cart;
    uint8_t t = c->rom_size > 0x147 ? c->rom[0x147] : 0;
    c->type = 0; c->has_ram = false;
    switch (t) {
    case 0x00: break;
    case 0x01: c->type = 1; break;
    case 0x02: case 0x03: c->type = 1; c->has_ram = true; break;
    case 0x05: case 0x06: c->type = 2; c->has_ram = true; break;
    case 0x08: case 0x09: c->has_ram = true; break;
    case 0x0F: case 0x11: c->type = 3; break;
    case 0x10: case 0x12: case 0x13: c->type = 3; c->has_ram = true; break;
    case 0x19: case 0x1C: c->type = 5; break;
    case 0x1A: case 0x1B: case 0x1D: case 0x1E: c->type = 5; c->has_ram = true; break;
    default: c->type = 1; c->has_ram = true; break;
    }
    static const uint32_t ram_sizes[6] = { 0, 0x800, 0x2000, 0x8000, 0x20000, 0x10000 };
    uint8_t rs = c->rom_size > 0x149 ? c->rom[0x149] : 0;
    c->ram_size = rs < 6 ? ram_sizes[rs] : 0;
    if (c->type == 2) c->ram_size = 0x200;
    if (c->has_ram && c->ram_size == 0) c->ram_size = 0x2000;
    if (!c->has_ram) c->ram_size = 0;
    uint32_t m = 0x8000;
    while (m < c->rom_size) m <<= 1;
    c->rom_mask = m - 1;
    c->ram_en = false; c->mode = false; c->bank = 1; c->bank_hi = 0; c->ram_bank = 0;
}

static inline uint8_t rom_at(const GBCart *c, uint32_t off) {
    off &= c->rom_mask;
    return off < c->rom_size ? c->rom[off] : 0xFF;
}

static uint8_t cart_read_rom(GB *g, uint16_t a) {
    GBCart *c = &g->cart;
    if (a < 0x4000) {
        if (c->type == 1 && c->mode) return rom_at(c, ((uint32_t)c->bank_hi << 19) | a);
        return rom_at(c, a);
    }
    uint32_t bank;
    switch (c->type) {
    case 1: bank = ((uint32_t)c->bank_hi << 5) | c->bank; break;
    case 0: bank = 1; break;
    default: bank = c->bank; break;
    }
    return rom_at(c, (bank << 14) | (a & 0x3FFF));
}

static void cart_write_rom(GB *g, uint16_t a, uint8_t v) {
    GBCart *c = &g->cart;
    switch (c->type) {
    case 1:
        if (a < 0x2000) c->ram_en = (v & 0x0F) == 0x0A;
        else if (a < 0x4000) { c->bank = v & 0x1F; if (!c->bank) c->bank = 1; }
        else if (a < 0x6000) c->bank_hi = v & 3;
        else c->mode = v & 1;
        break;
    case 2:
        if (a < 0x4000) {
            if (a & 0x100) { c->bank = v & 0x0F; if (!c->bank) c->bank = 1; }
            else c->ram_en = (v & 0x0F) == 0x0A;
        }
        break;
    case 3:
        if (a < 0x2000) c->ram_en = (v & 0x0F) == 0x0A;
        else if (a < 0x4000) { c->bank = v & 0x7F; if (!c->bank) c->bank = 1; }
        else if (a < 0x6000) c->ram_bank = v;
        break;
    case 5:
        if (a < 0x2000) c->ram_en = (v & 0x0F) == 0x0A;
        else if (a < 0x3000) c->bank = (c->bank & 0x100) | v;
        else if (a < 0x4000) c->bank = (c->bank & 0xFF) | ((v & 1) << 8);
        else if (a < 0x6000) c->ram_bank = v & 0x0F;
        break;
    default: break;
    }
}

static uint32_t cart_ram_off(const GBCart *c, uint16_t a) {
    uint32_t bank = 0;
    if (c->type == 1) bank = c->mode ? c->bank_hi : 0;
    else if (c->type == 3 || c->type == 5) bank = c->ram_bank;
    return ((bank << 13) | (a & 0x1FFF)) & (c->ram_size - 1);
}

static uint8_t cart_read_ram(GB *g, uint16_t a) {
    GBCart *c = &g->cart;
    if (!c->ram_size || (!c->ram_en && c->type != 0)) return 0xFF;
    if (c->type == 3 && c->ram_bank >= 8) return 0x00; /* RTC registers: not emulated */
    if (c->type == 2) return c->ram[a & 0x1FF] | 0xF0;
    return c->ram[cart_ram_off(c, a)];
}

static void cart_write_ram(GB *g, uint16_t a, uint8_t v) {
    GBCart *c = &g->cart;
    if (!c->ram_size || (!c->ram_en && c->type != 0)) return;
    if (c->type == 3 && c->ram_bank >= 8) return;
    if (c->type == 2) { c->ram[a & 0x1FF] = v & 0x0F; c->ram_dirty = true; return; }
    c->ram[cart_ram_off(c, a)] = v;
    c->ram_dirty = true;
}

/* ----------------------------------------------------------------- timer */

static inline bool timer_bit(const GBTimer *t) {
    static const uint16_t bits[4] = { 1 << 9, 1 << 3, 1 << 5, 1 << 7 };
    return (t->tac & 4) && (t->div & bits[t->tac & 3]);
}

static void tima_inc(GB *g) {
    if (++g->timer.tima == 0) g->timer.overflow_pending = true;
}

static void serial_clock(GB *g);

/* set the system counter, generating falling-edge side effects */
static void div_set(GB *g, uint16_t nv) {
    GBTimer *t = &g->timer;
    uint16_t old = t->div;
    bool before = timer_bit(t);
    t->div = nv;
    if (before && !timer_bit(t)) tima_inc(g);
    uint16_t fall = old & ~nv;
    if (fall & (1 << 12)) apu_frame_step(g);
    /* the serial shift clock runs one M-cycle ahead of the DIV value the CPU reads */
    if ((uint16_t)(old + 4) & ~(uint16_t)(nv + 4) & (1 << 8)) serial_clock(g);
}

/* An increment forced by a DIV/TAC write happens early in the write cycle, so an
 * overflow it causes has already reloaded TIMA and raised the interrupt by its end. */
static void timer_glitch_overflow(GB *g) {
    GBTimer *t = &g->timer;
    if (t->overflow_pending) {
        t->overflow_pending = false;
        t->tima = t->tma;
        g->iflag |= GB_INT_TIMER;
    }
}

static void timer_tick(GB *g) {
    GBTimer *t = &g->timer;
    t->reloading = false;
    if (t->overflow_pending) {
        t->overflow_pending = false;
        t->tima = t->tma;
        t->reloading = true;
        g->iflag |= GB_INT_TIMER;
    }
    div_set(g, (uint16_t)(t->div + 4));
}

/* ---------------------------------------------------------------- serial */

static void serial_clock(GB *g) {
    if (g->serial_bits > 0 && (g->sc & 0x81) == 0x81) {
        g->sb = (uint8_t)((g->sb << 1) | 1);
        if (--g->serial_bits == 0) {
            g->sc &= 0x7F;
            g->iflag |= GB_INT_SERIAL;
        }
    }
}

/* ---------------------------------------------------------------- joypad */

static uint8_t joy_lines(const GB *g) {
    uint8_t v = 0x0F;
    if (!(g->p1 & 0x10)) v &= ~(g->keys & 0x0F);
    if (!(g->p1 & 0x20)) v &= ~(g->keys >> 4);
    return v & 0x0F;
}

void gb_set_keys(GB *g, uint8_t keys) {
    uint8_t before = joy_lines(g);
    g->keys = keys;
    uint8_t after = joy_lines(g);
    if (before & ~after) g->iflag |= GB_INT_JOYPAD;
}

/* ------------------------------------------------------------------- bus */

static uint8_t raw_read(GB *g, uint16_t a) {
    if (a < 0x8000) return cart_read_rom(g, a);
    if (a < 0xA000) return g->vram[a & 0x1FFF];
    if (a < 0xC000) return cart_read_ram(g, a);
    return g->wram[a & 0x1FFF];
}

static void dma_tick(GB *g) {
    if (g->dma_active && g->dma_idx >= 0xA0) g->dma_active = false;
    if (g->dma_pending && --g->dma_pending == 0) {
        g->dma_active = true;
        g->dma_idx = 0;
        g->dma_src = (uint16_t)(g->dma_reg << 8);
    }
    if (g->dma_active && g->dma_idx < 0xA0) {
        g->oam[g->dma_idx] = raw_read(g, (uint16_t)(g->dma_src + g->dma_idx));
        g->dma_idx++;
    }
}

void gb_tick(GB *g) {
    g->cycles += 4;
    g->frame_cycles += 4;
    timer_tick(g);
    dma_tick(g);
    ppu_tick(g);
    apu_tick(g);
}

static uint8_t io_read(GB *g, uint16_t a) {
    switch (a) {
    case 0xFF00: return (uint8_t)(0xC0 | (g->p1 & 0x30) | joy_lines(g));
    case 0xFF01: return g->sb;
    case 0xFF02: return g->sc | 0x7E;
    case 0xFF04: return (uint8_t)(g->timer.div >> 8);
    case 0xFF05: return g->timer.tima;
    case 0xFF06: return g->timer.tma;
    case 0xFF07: return g->timer.tac | 0xF8;
    case 0xFF0F: return g->iflag | 0xE0;
    case 0xFF46: return g->dma_reg;
    default: break;
    }
    if (a >= 0xFF10 && a <= 0xFF3F) return apu_read(g, a);
    if (a >= 0xFF40 && a <= 0xFF4B) return ppu_read(g, a);
    return 0xFF;
}

static void io_write(GB *g, uint16_t a, uint8_t v) {
    switch (a) {
    case 0xFF00: {
        uint8_t before = joy_lines(g);
        g->p1 = v & 0x30;
        if (before & ~joy_lines(g)) g->iflag |= GB_INT_JOYPAD;
        return;
    }
    case 0xFF01: g->sb = v; return;
    case 0xFF02:
        g->sc = v & 0x81;
        if ((v & 0x81) == 0x81) {
            g->serial_bits = 8;
            if (g->serial_n < (int)sizeof g->serial_out - 1) {
                g->serial_out[g->serial_n++] = (char)g->sb;
                g->serial_out[g->serial_n] = 0;
            }
        }
        return;
    case 0xFF04: div_set(g, 0); timer_glitch_overflow(g); return;
    case 0xFF05:
        if (!g->timer.reloading) { g->timer.tima = v; g->timer.overflow_pending = false; }
        return;
    case 0xFF06:
        g->timer.tma = v;
        if (g->timer.reloading) g->timer.tima = v;
        return;
    case 0xFF07: {
        bool before = timer_bit(&g->timer);
        g->timer.tac = v & 7;
        if (before && !timer_bit(&g->timer)) tima_inc(g);
        timer_glitch_overflow(g);
        return;
    }
    case 0xFF0F: g->iflag = v & 0x1F; return;
    case 0xFF46: g->dma_reg = v; g->dma_pending = 2; return;
    default: break;
    }
    if (a >= 0xFF10 && a <= 0xFF3F) { apu_write(g, a, v); return; }
    if (a >= 0xFF40 && a <= 0xFF4B) { ppu_write(g, a, v); return; }
}

uint8_t gb_read(GB *g, uint16_t a) {
    if (a < 0x8000) return cart_read_rom(g, a);
    if (a < 0xA000) return ppu_vram_locked(g) ? 0xFF : g->vram[a & 0x1FFF];
    if (a < 0xC000) return cart_read_ram(g, a);
    if (a < 0xFE00) return g->wram[a & 0x1FFF];
    if (a < 0xFEA0) return (g->dma_active || ppu_oam_locked(g)) ? 0xFF : g->oam[a - 0xFE00];
    if (a < 0xFF00) return (g->dma_active || ppu_oam_locked(g)) ? 0xFF : 0x00;
    if (a < 0xFF80) return io_read(g, a);
    if (a < 0xFFFF) return g->hram[a - 0xFF80];
    return g->ie;
}

void gb_write(GB *g, uint16_t a, uint8_t v) {
    if (a < 0x8000) { cart_write_rom(g, a, v); return; }
    if (a < 0xA000) { if (!ppu_vram_wlocked(g)) g->vram[a & 0x1FFF] = v; return; }
    if (a < 0xC000) { cart_write_ram(g, a, v); return; }
    if (a < 0xFE00) { g->wram[a & 0x1FFF] = v; return; }
    if (a < 0xFEA0) { if (!g->dma_active && !ppu_oam_wlocked(g)) g->oam[a - 0xFE00] = v; return; }
    if (a < 0xFF00) return;
    if (a < 0xFF80) { io_write(g, a, v); return; }
    if (a < 0xFFFF) { g->hram[a - 0xFF80] = v; return; }
    g->ie = v;
}

uint8_t gb_peek(GB *g, uint16_t a) {
    if (a < 0x8000) return cart_read_rom(g, a);
    if (a < 0xA000) return g->vram[a & 0x1FFF];
    if (a < 0xC000) return cart_read_ram(g, a);
    if (a < 0xFE00) return g->wram[a & 0x1FFF];
    if (a < 0xFEA0) return g->oam[a - 0xFE00];
    if (a < 0xFF00) return 0;
    if (a < 0xFF80) return io_read(g, a);
    if (a < 0xFFFF) return g->hram[a - 0xFF80];
    return g->ie;
}

/* ------------------------------------------------------------- lifecycle */

/* Recreate what the boot ROM leaves in VRAM: the cartridge logo, scaled 2x, and its tilemap. */
static void boot_logo(GB *g) {
    if (g->cart.rom_size < 0x134) return;
    uint8_t *p = &g->vram[0x10];
    for (int i = 0; i < 48; i++) {
        uint8_t b = g->cart.rom[0x104 + i];
        for (int n = 0; n < 2; n++, b = (uint8_t)(b << 4)) {
            uint8_t wide = 0;
            for (int k = 0; k < 4; k++)
                if (b & (0x80 >> k)) wide |= (uint8_t)(0xC0 >> (k * 2));
            p[0] = wide; p[2] = wide;
            p += 4;
        }
    }
    static const uint8_t reg_mark[8] = { 0x3C, 0x42, 0xB9, 0xA5, 0xB9, 0xA5, 0x42, 0x3C };
    for (int i = 0; i < 8; i++) g->vram[0x190 + i * 2] = reg_mark[i];
    for (int i = 0; i < 12; i++) {
        g->vram[0x1904 + i] = (uint8_t)(1 + i);
        g->vram[0x1924 + i] = (uint8_t)(13 + i);
    }
    g->vram[0x1910] = 0x19;
}

void gb_reset(GB *g) {
    const uint8_t *rom = g->cart.rom;
    size_t size = g->cart.rom_size;
    uint32_t rate = g->apu.rate;
    uint8_t mask = g->apu.chan_mask;
    memset(g, 0, sizeof *g);
    g->cart.rom = rom;
    g->cart.rom_size = size;
    cart_setup(g);

    /* state left behind by the DMG boot ROM */
    GBCpu *c = &g->cpu;
    c->r[R_A] = 0x01; c->r[R_F] = 0xB0; c->r[R_B] = 0x00; c->r[R_C] = 0x13;
    c->r[R_D] = 0x00; c->r[R_E] = 0xD8; c->r[R_H] = 0x01; c->r[R_L] = 0x4D;
    c->sp = 0xFFFE; c->pc = 0x0100;
    g->timer.div = 0xABC8;
    g->timer.tac = 0;
    g->iflag = 0x01;
    g->p1 = 0x00;
    g->sc = 0x00;
    g->dma_reg = 0xFF;
    g->apu.rate = rate ? rate : 48000;
    g->apu.chan_mask = mask ? mask : 0x0F;
    boot_logo(g);
    ppu_reset(g);
    apu_reset(g);
}

void gb_init(GB *g, const uint8_t *rom, size_t rom_size) {
    g->cart.rom = rom;
    g->cart.rom_size = rom_size;
    g->apu.rate = 0;
    g->apu.chan_mask = 0;
    gb_reset(g);
}

void gb_run_frame(GB *g) {
    g->frame_ready = false;
    while (!g->frame_ready) {
        gb_cpu_step(g);
        if (!(g->ppu.lcdc & 0x80) && g->frame_cycles >= GB_FRAME_TCYCLES) {
            /* LCD off: pace frames by time and show a blank screen */
            memset(g->ppu.front, 0, sizeof g->ppu.front);
            g->frame_ready = true;
        }
    }
    g->frame_cycles = 0;
}

const char *gb_cart_title(const GB *g, char out[17]) {
    int i = 0;
    for (; i < 16 && 0x134 + (size_t)i < g->cart.rom_size; i++) {
        char ch = (char)g->cart.rom[0x134 + i];
        if (ch < 32 || ch > 126) break;
        out[i] = ch;
    }
    out[i] = 0;
    return out;
}
