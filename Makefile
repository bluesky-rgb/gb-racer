CC      ?= gcc
CFLAGS  := -std=c11 -O2 -Wall -Wextra -Wpedantic -Wconversion -Wno-sign-conversion
CORE    := emu/gb.c emu/cpu.c emu/ppu.c emu/apu.c

WASM_CC ?= clang
WASM_FLAGS := --target=wasm32 -std=c11 -O2 -nostdlib -ffreestanding -fno-builtin -mbulk-memory \
              -Iweb/libc -Wall -Wextra -Wl,--no-entry -Wl,--strip-all -Wl,-z,stack-size=65536

all: build/libgb.so

wasm: web/gb.wasm

web/gb.wasm: $(CORE) web/wasm_glue.c emu/gb.h
	$(WASM_CC) $(WASM_FLAGS) -o $@ $(CORE) web/wasm_glue.c

build/libgb.so: $(CORE) emu/capi.c emu/gb.h
	@mkdir -p build
	$(CC) $(CFLAGS) -shared -fPIC -o $@ $(CORE) emu/capi.c

clean:
	rm -rf build
# static site for GitHub Pages
site: web/gb.wasm
	@mkdir -p docs
	cp web/index.html web/app.js web/audio-worklet.js web/gb.wasm docs/
	@if [ -f web/icon.png ]; then cp web/icon.png docs/; fi
	@if [ -f game/build/racer.gb ]; then cp game/build/racer.gb docs/racer.gb; fi
	@if [ -f shooter/build/lance.gb ]; then cp shooter/build/lance.gb docs/lance.gb; fi
	@touch docs/.nojekyll

.PHONY: all wasm site clean
