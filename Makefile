CC      ?= gcc
CFLAGS  := -std=c11 -O2 -Wall -Wextra -Wpedantic -Wconversion -Wno-sign-conversion
CORE    := emu/gb.c emu/cpu.c emu/ppu.c emu/apu.c

all: build/libgb.so

build/libgb.so: $(CORE) emu/capi.c emu/gb.h
	@mkdir -p build
	$(CC) $(CFLAGS) -shared -fPIC -o $@ $(CORE) emu/capi.c

clean:
	rm -rf build
.PHONY: all clean
