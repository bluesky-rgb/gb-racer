RGBDS ?= /home/claude/ext/rgbds
ASM   := $(RGBDS)/rgbasm
LINK  := $(RGBDS)/rgblink
FIX   := $(RGBDS)/rgbfix
SRC   := $(wildcard src/*.asm src/*.inc) ../game/src/sound.asm ../game/src/hardware.inc
TOOLS := $(wildcard tools/*.py) ../game/tools/gbgfx.py ../game/tools/font.py ../game/tools/art.py ../game/tools/chiptune.py

all: build/lance.gb

build/assets.inc: $(TOOLS)
	@mkdir -p build
	python3 tools/mkassets.py build
	python3 tools/mkstages.py build/stages.asm
	python3 tools/mksongs.py build/music.asm

build/lance.gb: $(SRC) build/assets.inc
	$(ASM) -E -I src -I ../game/src -I build -o build/lance.o src/main.asm
	$(LINK) -m build/lance.map -n build/lance.sym -o $@ build/lance.o
	$(FIX) -v -p 0xFF -m 0x19 -r 0 -t "ORBITLANCE" -j -l 0x33 -k "ZZ" $@

clean:
	rm -rf build
.PHONY: all clean
