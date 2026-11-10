/* Minimal string.h for the freestanding WebAssembly build. */
#ifndef WASM_STRING_H
#define WASM_STRING_H
#include <stddef.h>
void *memcpy(void *dst, const void *src, size_t n);
void *memset(void *dst, int c, size_t n);
void *memmove(void *dst, const void *src, size_t n);
#endif
