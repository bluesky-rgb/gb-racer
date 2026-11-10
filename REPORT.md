# Project report

Play link: **https://bluesky-rgb.github.io/gb-racer/**

## Time

| | |
|---|---|
| Started | 2026-11-09 23:48 PST |
| Finished | 2026-11-10 ~07:10 PST |
| Wall-clock | about 7 h 20 min |
| Active working time | about 1 h 25 min (the session sat idle twice, 00:25-01:49 and 02:21-06:58, until it was told to continue) |
| Part 1 (emulator + web page) | about 30 min |
| Part 2 (game, verification, deployment) | about 55 min |

## Lines of code

| Part | Files | Lines |
|---|---|---|
| Part 1: emulator core, WebAssembly glue, web page | `emu/`, `web/` | 2,301 |
| Part 2: game, RGBDS assembly | `game/src/` | 3,489 |
| Part 2: art, music, course and table generators (Python) | `game/tools/` | 1,101 |
| Test harnesses and tools (Python, C, JS) | `tools/`, `tests/` | 768 |

## Test results

Emulator (full log: produced by the commands in README, summarised here):

| Suite | Result |
|---|---|
| Blargg `cpu_instrs` (11 individual ROMs + combined ROM) | 12 / 12 pass |
| Blargg `instr_timing`, `mem_timing`, `mem_timing-2`, `halt_bug` | 4 / 4 pass |
| Blargg `dmg_sound` (12 ROMs) | 12 / 12 pass |
| `dmg-acid2` against the official reference image | pass, 0 differing pixels |
| mooneye acceptance suite (DMG-applicable tests) | 66 / 66 pass |
| mooneye `sprite_priority` image | pass, 0 differing pixels |
| Blargg `oam_bug` | not passed: the OAM corruption bug is not emulated |

Game, compared with mGBA (same ROM, same recorded inputs, every frame compared pixel for pixel):

| Run | Frames | Differing frames |
|---|---|---|
| Title and course select | 252 | 0 |
| Course 1 Sunset Coast, full 3-lap race | 7,133 | 0 |
| Course 2 Mesa Canyon, full 3-lap race | 7,557 | 0 |
| Course 3 Neon Night, full 3-lap race | 7,448 | 0 |
| No steering: collisions, off-road, time-up ending | 3,742 | 0 |
| **Total** | **26,132** | **0** |

Matching screenshot pairs (`*_ours.png` / `*_mgba.png`) are in `docs/screenshots/`.

Frame rate: the game runs its logic every frame (59.7 fps). Measured in the emulator over the
three full races, the busiest frame used 83.5% of a frame's CPU time and no frame was dropped
during play.

Web page: tested in headless Chromium with iPad (portrait and landscape), iPad Pro, iPhone and
desktop profiles: the screen scales by a whole number of device pixels, multi-touch on the D-pad
and buttons works (including sliding between directions and from A to B), and audio is produced.
It has not been tried on a physical iPad.

## Problems and fixes

- **No Emscripten available.** Compiled the core freestanding with clang's wasm32 target and
  wrote the small amount of JavaScript glue by hand. The module is 24 KB.
- **dmg-acid2 would not build with current RGBDS.** Used the prebuilt test ROM that ships in
  mGBA's test data instead.
- **PPU timing.** The first version failed 10 mooneye tests. Disassembling the test ROMs showed
  what each one measured; the fixes were: STAT mode bits lag the internal mode by one M-cycle,
  the HBlank interrupt leads the visible mode-0 by one dot, OAM and VRAM lock windows differ for
  reads and writes, the first line after LCD-on is 4 dots short, and the LY=LYC interrupt line
  stays latched while the LCD is off.
- **Timer edge cases.** A TIMA overflow caused by a write to TAC/DIV raises its interrupt in the
  same cycle; the boot-time DIV phase and serial clock phase needed aligning with it.
- **Game CPU budget.** The first complete build used about 90% of the frame on average. Profiling
  by routine led to: page-aligned lookup tables for sprite placement instead of multiplies,
  stopping the scenery loop at the first object too small to draw, unrolling the two road loops,
  and switching the raster interrupt off below the last road line. Worst case is now 83.5%.
- **Sprite and background tiles share VRAM.** The title logo and the scenery sprites overlapped.
  The asset packer now reserves a per-scene range of tile numbers for sprites and remaps the
  background around it.
- **First frame after LCD-on.** A real DMG (and this emulator) shows a blank first frame; mGBA
  shows it. The game now turns the LCD on with blank palettes for one frame, so both match.
- **Sound requests from the main program** could race with the driver running in the VBlank
  interrupt. They are now single-byte requests picked up by the driver, so the main program never
  disables interrupts while the raster effect is running.

## Known limitations

- The music was checked by rendering audio and confirming each channel plays the written notes;
  nobody has listened to it.
- Rivals hold their lanes; they do not weave or block.
- The emulator does not emulate the OAM corruption bug, the RTC of MBC3, or battery saves.
