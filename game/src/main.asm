; SCANLINE SPRINT - an original pseudo-3D racer for the Game Boy (DMG)
; Entry point, interrupt handlers and shared memory layout.

INCLUDE "hardware.inc"
INCLUDE "assets.inc"
INCLUDE "charmap.inc"
INCLUDE "defs.inc"

; ---------------------------------------------------------------- vectors
SECTION "VBlankVec", ROM0[$0040]
    jp VBlankISR

; The STAT interrupt is the raster effect. It runs in HBlank of every road line
; and loads the scroll registers for the NEXT line from two page-aligned tables
; indexed by LY. The frame's first invocation is an LY=LYC interrupt two lines
; above the horizon, which switches the interrupt source over to HBlank.
SECTION "StatVec", ROM0[$0048]
StatISR:
    push af
    push hl
    ldh a, [rLY]
    ld l, a
    ldh a, [hTabPage]
    ld h, a
    ld a, [hl]
    ldh [rSCX], a
    inc h
    ld a, [hl]
    ldh [rSCY], a
    ldh a, [hKick]
    cp l
    jr z, .kick
    pop hl
    pop af
    reti
.kick
    ; first time (the LYC line): switch the interrupt source to HBlank and
    ; re-aim the kick at the last road line, where the raster is switched off again
    ld a, l
    cp HUD_LINE - 1
    jr z, .stop
    ld a, STAT_MODE0
    ldh [rSTAT], a
    ld a, HUD_LINE - 1
    ldh [hKick], a
    pop hl
    pop af
    reti
.stop
    ld a, STAT_LYC
    ldh [rSTAT], a
    pop hl
    pop af
    reti

SECTION "Header", ROM0[$0100]
    nop
    jp Start
    ds $150 - @, 0          ; header is filled in by rgbfix

; ---------------------------------------------------------------- memory
SECTION "ShadowOAM", WRAM0[$C000]
wOAM::          ds 160

SECTION "RowX", WRAM0[$C100]
wRowX::         ds 128          ; SCX for each road texture row (this frame)

SECTION "RasterTables", WRAMX[$D000]
wTab0X::        ds 256          ; buffer 0: SCX then SCY, indexed by LY
wTab0Y::        ds 256
wTab1X::        ds 256          ; buffer 1
wTab1Y::        ds 256

SECTION "HRAM", HRAM
hDMA::          ds 10           ; OAM DMA routine
hTabPage::      db              ; high byte of the raster table being displayed
hKick::         db              ; LY the raster handler is waiting for (start line, then stop line)
hKickBase::     db              ; LY of the LYC interrupt that starts the raster
hSkyX::         db              ; scroll used above the horizon
hSkyY::         db
hPendPage::     db              ; values the next buffer flip will install
hPendKick::     db
hPendSkyX::     db
hPendSkyY::     db
hFrameReady::   db              ; main loop finished a frame: flip at VBlank
hVBlankFlag::   db
hFrame::        db              ; free-running frame counter
hKeys::         db              ; buttons held
hKeysNew::      db              ; buttons pressed this frame
hHudOn::        db              ; copy the HUD buffer to the window each frame
hInSound::      db              ; re-entrancy guard for the sound driver
hLagFrames::    db              ; frames where the main loop missed VBlank (debug)
hBGP::          db              ; palettes, applied every VBlank
hOBP0::         db
hOBP1::         db
hRow::          db              ; scratch for the sprite code
hType::         db
hOamLo::        db
hScP3::         db
hScCount::      db

; ---------------------------------------------------------------- start
SECTION "Main", ROM0

Start:
    di
    ld sp, $E000
    ; wait for VBlank, then switch the LCD off for setup
.waitvb
    ldh a, [rLY]
    cp 145
    jr nz, .waitvb
    xor a
    ldh [rLCDC], a
    ldh [rIF], a
    ldh [rIE], a

    ; clear RAM (inline: the stack lives in the memory being cleared)
    ld hl, $C000
    ld bc, $2000
.clear
    xor a
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .clear
    ld hl, $FF80
    ld b, $7F
    xor a
.clearh
    ld [hl+], a
    dec b
    jr nz, .clearh
    ld sp, $E000

    ld a, 1
    ld [rROMB0], a

    ; install the DMA routine and RAM-resident inner loops
    ld hl, DMARoutine
    ld de, hDMA
    ld bc, DMARoutineEnd - DMARoutine
    call MemCopy
    ld hl, RamCodeSrc
    ld de, RamCodeStart
    ld bc, RamCodeEnd - RamCodeStart
    call MemCopy

    ld a, $FF
    ldh [hKick], a
    ldh [hKickBase], a
    ldh [hPendKick], a
    ld a, HIGH(wTab0X)
    ldh [hTabPage], a

    call SoundInit
    call ClearOAM

    ld a, STAT_LYC
    ldh [rSTAT], a
    ld a, $FF
    ldh [rLYC], a
    xor a
    ldh [rIF], a
    ld a, IE_VBLANK | IE_STAT
    ldh [rIE], a

    jp GameStart

; ---------------------------------------------------------------- VBlank
VBlankISR:
    push af
    push bc
    push de
    push hl
    ldh a, [hFrameReady]
    or a
    jr z, .noflip
    xor a
    ldh [hFrameReady], a
    ldh a, [hPendPage]
    ldh [hTabPage], a
    ldh a, [hPendKick]
    ldh [hKickBase], a
    ldh a, [hPendSkyX]
    ldh [hSkyX], a
    ldh a, [hPendSkyY]
    ldh [hSkyY], a
    call hDMA
    ldh a, [hHudOn]
    or a
    call nz, HudCopy
    jr .flipped
.noflip
    ld hl, hLagFrames
    inc [hl]
.flipped
    ldh a, [hBGP]
    ldh [rBGP], a
    ldh a, [hOBP0]
    ldh [rOBP0], a
    ldh a, [hOBP1]
    ldh [rOBP1], a
    ; top-of-frame registers: sky scroll, and re-arm the LYC kick
    ldh a, [hSkyX]
    ldh [rSCX], a
    ldh a, [hSkyY]
    ldh [rSCY], a
    ldh a, [hKickBase]
    ldh [hKick], a
    ldh [rLYC], a
    ld a, STAT_LYC
    ldh [rSTAT], a
    ; a STAT write during VBlank can raise a spurious request on DMG: discard it
    ld hl, rIF
    res 1, [hl]
    ld a, 1
    ldh [hVBlankFlag], a
    ld hl, hFrame
    inc [hl]
    ; music keeps time from here even if the main loop is busy.
    ; interrupts are re-enabled first so the raster handler is never delayed.
    ldh a, [hInSound]
    or a
    jr nz, .nosound
    inc a
    ldh [hInSound], a
    ei
    call SoundUpdate
    xor a
    ldh [hInSound], a
.nosound
    pop hl
    pop de
    pop bc
    pop af
    reti

; ---------------------------------------------------------------- helpers
WaitVBlank::
.wait
    ldh a, [hVBlankFlag]
    or a
    jr nz, .got
    halt
    jr .wait
.got
    xor a
    ldh [hVBlankFlag], a
    ret

; wait for the next VBlank and mark the (static) frame as presentable
NextFrame::
    ld a, 1
    ldh [hFrameReady], a
    call WaitVBlank
    jp ReadJoypad

ReadJoypad::
    ld a, $20               ; select direction keys
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    swap a
    ld b, a
    ld a, $10               ; select buttons
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    or b
    ld b, a
    ld a, $30
    ldh [rP1], a
    ldh a, [hKeys]
    cpl
    and b
    ldh [hKeysNew], a
    ld a, b
    ldh [hKeys], a
    ret

; hl = dest, bc = count
MemClear::
    xor a
MemFill::
    ld d, a
.loop
    ld a, d
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .loop
    ret

; hl = source, de = dest, bc = count
MemCopy::
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, MemCopy
    ret

ClearOAM::
    ld hl, wOAM
    ld b, 160
    xor a
.loop
    ld [hl+], a
    dec b
    jr nz, .loop
    ret

; turn the LCD off safely (waits for VBlank). Interrupt handlers stay installed.
; Any VBlank line will do: waiting for one exact line can miss it forever when
; the VBlank interrupt handler happens to be running during that line.
LcdOff::
    ldh a, [rLCDC]
    add a
    ret nc
.wait
    ldh a, [rLY]
    cp 144
    jr c, .wait
    xor a
    ldh [rLCDC], a
    ret

DMARoutine:
    ld a, HIGH(wOAM)
    ldh [rDMA], a
    ld a, 40
.wait
    dec a
    jr nz, .wait
    ret
DMARoutineEnd:

INCLUDE "sound.asm"
INCLUDE "road.asm"
INCLUDE "objects.asm"
INCLUDE "game.asm"
INCLUDE "data.asm"
