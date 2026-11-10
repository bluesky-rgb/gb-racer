/* WebAssembly entry points. Built freestanding with clang (no Emscripten, no libc):
 * all state is static and JavaScript reads the buffers straight out of linear memory. */
#include "../emu/gb.h"
#include <string.h>

#define EXPORT(name) __attribute__((export_name(#name))) name
#define ROM_MAX (8 * 1024 * 1024)

static GB gb;
static uint8_t rom[ROM_MAX];
static uint32_t rgba[GB_W * GB_H];
static uint32_t palette[4] = { 0xFFFFFFFF, 0xFFAAAAAA, 0xFF555555, 0xFF000000 };

void *memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = dst; const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dst;
}
void *memset(void *dst, int c, size_t n) {
    uint8_t *d = dst;
    while (n--) *d++ = (uint8_t)c;
    return dst;
}
void *memmove(void *dst, const void *src, size_t n) {
    uint8_t *d = dst; const uint8_t *s = src;
    if (d < s) while (n--) *d++ = *s++;
    else { d += n; s += n; while (n--) *--d = *--s; }
    return dst;
}

uint8_t *EXPORT(wasm_rom_buffer)(void) { return rom; }
uint32_t EXPORT(wasm_rom_max)(void) { return ROM_MAX; }

void EXPORT(wasm_load)(uint32_t size, uint32_t sample_rate) {
    if (size < 0x8000) { memset(rom + size, 0xFF, 0x8000 - size); size = 0x8000; }
    gb_init(&gb, rom, size);
    gb_set_audio_rate(&gb, sample_rate);
}

void EXPORT(wasm_reset)(void) { gb_reset(&gb); }
void EXPORT(wasm_set_keys)(uint32_t keys) { gb_set_keys(&gb, (uint8_t)keys); }
void EXPORT(wasm_set_rate)(uint32_t hz) { gb_set_audio_rate(&gb, hz); }
void EXPORT(wasm_set_palette)(uint32_t i, uint32_t abgr) { palette[i & 3] = abgr; }

/* run one video frame; returns the number of stereo audio frames produced */
uint32_t EXPORT(wasm_run_frame)(void) {
    gb.apu.buf_n = 0;
    gb_run_frame(&gb);
    const uint8_t *src = gb.ppu.front;
    for (int i = 0; i < GB_W * GB_H; i++) rgba[i] = palette[src[i] & 3];
    return (uint32_t)gb.apu.buf_n;
}

uint32_t *EXPORT(wasm_video)(void) { return rgba; }
float *EXPORT(wasm_audio)(void) { return gb.apu.buf; }
uint8_t *EXPORT(wasm_cart_ram)(void) { return gb.cart.ram; }
uint32_t EXPORT(wasm_cart_ram_size)(void) { return gb.cart.ram_size; }
