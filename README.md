# gb-racer

**Play:** https://bluesky-rgb.github.io/gb-racer/

Two things in one repository:

Two cartridges, one console: the page has a switcher between the two games (`?cart=lance`
opens the shooter directly).

1. **A Game Boy (DMG) emulator** written from scratch in C11 (`emu/`), compiled to WebAssembly
   with plain clang (no Emscripten) and wrapped in a web page with crisp integer scaling, sound,
   touch controls and keyboard controls (`web/`).
2. **Scanline Sprint**, an original pseudo-3D racing game for the Game Boy written in RGBDS
   assembly (`game/`). All graphics and music are original and generated from the scripts in
   `game/tools/`.
3. **Orbit Lance**, an original vertical shooter in RGBDS assembly (`shooter/`), sharing the sound
   driver and drawing tools with the racer.

Controls (racer): D-pad steers, A accelerates, B brakes, Start pauses.
Controls (shooter): D-pad moves, hold A to fire, B drops a bomb, Select on the title picks a stage.
On a keyboard: arrow keys, X (A), Z (B), Enter (Start), Shift (Select).

## Building

    make            # native test library (build/libgb.so)
    make wasm       # web/gb.wasm
    make -C game    # game/build/racer.gb  (needs RGBDS)
    make -C shooter # shooter/build/lance.gb
    make site       # copies everything into docs/ for GitHub Pages

## Testing

    python3 tests/run_blargg.py <roms...>     # Blargg test ROMs
    python3 tests/run_mooneye.py <dir>        # mooneye acceptance tests
    python3 tests/run_images.py               # dmg-acid2 against its reference image
    python3 tools/verify_mgba.py out_dir      # replay bot-driven races in mGBA, compare every frame
    node tests/web_test.js docs build         # headless browser test of the web page

See [REPORT.md](REPORT.md) for results.
