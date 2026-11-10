/* Thin C API for host tools (Python ctypes test harness). Not part of the freestanding core. */
#include "gb.h"
#include <stdlib.h>
#include <string.h>

GB *gbx_create(const uint8_t *rom, size_t n) {
    GB *g = calloc(1, sizeof *g);
    uint8_t *copy = malloc(n < 0x8000 ? 0x8000 : n);
    memset(copy, 0xFF, n < 0x8000 ? 0x8000 : n);
    memcpy(copy, rom, n);
    gb_init(g, copy, n < 0x8000 ? 0x8000 : n);
    return g;
}
void gbx_destroy(GB *g) { free((void *)g->cart.rom); free(g); }
const uint8_t *gbx_front(GB *g) { return g->ppu.front; }
const char *gbx_serial(GB *g) { return g->serial_out; }
int gbx_audio(GB *g, float *out, int max) {
    int n = g->apu.buf_n < max ? g->apu.buf_n : max;
    memcpy(out, g->apu.buf, (size_t)n * 2 * sizeof(float));
    g->apu.buf_n = 0;
    return n;
}
uint8_t gbx_peek(GB *g, uint16_t a) { return gb_peek(g, a); }
void gbx_poke(GB *g, uint16_t a, uint8_t v) {
    if (a >= 0xC000 && a < 0xFE00) g->wram[a & 0x1FFF] = v;
    else if (a >= 0xFF80 && a < 0xFFFF) g->hram[a - 0xFF80] = v;
}
uint8_t gbx_reg(GB *g, int i) { return g->cpu.r[i]; }
uint16_t gbx_pc(GB *g) { return g->cpu.pc; }
int gbx_breakpoint(GB *g) { return g->breakpoint; }
uint64_t gbx_cycles(GB *g) { return g->cycles; }
void gbx_step(GB *g) { gb_cpu_step(g); }
int gbx_halted(GB *g) { return g->cpu.halted; }
int gbx_line(GB *g) { return g->ppu.line; }
void gbx_chan_mask(GB *g, int m) { g->apu.chan_mask = (uint8_t)m; }
void gbx_set_div(GB *g, uint16_t v) { g->timer.div = v; }
uint64_t gbx_halt_cycles(GB *g) { return g->halt_cycles; }
