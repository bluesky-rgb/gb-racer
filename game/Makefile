RGBDS ?= /home/claude/ext/rgbds
ASM   := $(RGBDS)/rgbasm
LINK  := $(RGBDS)/rgblink
FIX   := $(RGBDS)/rgbfix
SRC   := $(wildcard src/*.asm src/*.inc)
TOOLS := $(wildcard tools/*.py)

all: build/racer.gb

build/assets.inc: $(TOOLS)
	@mkdir -p build
	python3 tools/mktables.py build/tables.asm
	python3 tools/mkassets.py build
	python3 tools/mkmusic.py build/music.asm
	python3 tools/mktracks.py build/tracks.asm

build/racer.gb: $(SRC) build/assets.inc
	$(ASM) -E -I src -I build -o build/racer.o src/main.asm
	$(LINK) -m build/racer.map -n build/racer.sym -o $@ build/racer.o
	$(FIX) -v -p 0xFF -m 0x19 -r 0 -t "SCANLINESPRINT" -j -l 0x33 -k "ZZ" $@

clean:
	rm -rf build
.PHONY: all clean
