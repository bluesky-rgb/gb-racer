; ORBIT LANCE - an original vertical shooter for the Game Boy (DMG)
; Entry point, interrupt handlers, memory layout and small helpers.

INCLUDE "hardware.inc"
INCLUDE "assets.inc"
INCLUDE "charmap.inc"
INCLUDE "defs.inc"

SECTION "VBlankVec", ROM0[$0040]
    jp VBlankISR

; Title screen only: in HBlank, load SCX for the next line from wLineX.
; This ripples the logo one scanline at a time.
SECTION "StatVec", ROM0[$0048]
    push af
    push hl
    ldh a, [rLY]
    inc a
    ld l, a
    ld h, HIGH(wLineX)
    ld a, [hl]
    ldh [rSCX], a
    pop hl
    pop af
    reti

SECTION "Header", ROM0[$0100]
    nop
    jp Start
    ds $150 - @, 0

; ---------------------------------------------------------------- memory
SECTION "ShadowOAM", WRAM0[$C000]
wOAM::          ds 160

SECTION "LineX", WRAM0[$C100]
wLineX::        ds 256          ; title ripple: SCX per scanline

SECTION "Objects", WRAM0[$C200]
wEnemies::      ds MAX_EN * OBJ_SIZE
wPShots::       ds MAX_PSHOT * 4

SECTION "EnemyShots", WRAM0[$C300]
wEShots::       ds MAX_ESHOT * OBJ_SIZE

SECTION "HRAM", HRAM
hDMA::          ds 10
hFrame::        db
hKeys::         db
hKeysNew::      db
hVBlankFlag::   db
hFrameReady::   db
hBGP::          db
hOBP0::         db
hOBP1::         db
hSCX::          db
hSCY::          db
hPendSCY::      db              ; installed with the next finished frame
hHudOn::        db
hInSound::      db
hLagFrames::    db              ; frames the main loop missed (debug)
hAttr::         db              ; xor-ed into sprite attributes by EmitFrame
hCount::        db
hTmp::          ds 4

; ---------------------------------------------------------------- start
SECTION "Main", ROM0

Start:
    di
    ld sp, $E000
.waitvb
    ldh a, [rLY]
    cp 144
    jr c, .waitvb
    xor a
    ldh [rLCDC], a
    ldh [rIF], a
    ldh [rIE], a
    ; clear WRAM and HRAM (inline: the stack lives in the memory being cleared)
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
.clearh
    ld [hl+], a
    dec b
    jr nz, .clearh
    ld sp, $E000

    ld a, 1
    ld [rROMB0], a
    ld hl, DMARoutine
    ld de, hDMA
    ld bc, DMARoutineEnd - DMARoutine
    call MemCopy
    call SoundInit
    ; tiles that never change: HUD font and all sprites
    ld hl, FontTiles
    ld de, $9000
    ld bc, FONT_TILES * 16
    call MemCopy
    ld hl, ObjTiles
    ld de, $8000
    ld bc, OBJ_TILES * 16
    call MemCopy
    ld a, %11100100
    ldh [hBGP], a
    ld a, %11010000         ; sprites: white, light gray, black
    ldh [hOBP0], a
    xor a                   ; palette 1: solid white (hit flash)
    ldh [hOBP1], a
    ld a, 7
    ldh [rWX], a
    ld a, HUD_LINE
    ldh [rWY], a
    ld a, $35
    ld [wRand], a
    ; high score to beat
    ld a, $50
    ld [wHiScore + 1], a
    ld a, IE_VBLANK
    ldh [rIE], a
    ei
    jp TitleInit

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
    call hDMA
    ldh a, [hPendSCY]
    ldh [hSCY], a
    ldh a, [hHudOn]
    or a
    call nz, HudCopy
    jr .flipped
.noflip
    ld hl, hLagFrames
    inc [hl]
.flipped
    ldh a, [hSCY]
    ldh [rSCY], a
    ld a, [wLineX]
    ldh [rSCX], a
    ldh a, [hBGP]
    ldh [rBGP], a
    ldh a, [hOBP0]
    ldh [rOBP0], a
    ldh a, [hOBP1]
    ldh [rOBP1], a
    ld a, 1
    ldh [hVBlankFlag], a
    ld hl, hFrame
    inc [hl]
    ldh a, [hInSound]
    or a
    jr nz, .nosound
    inc a
    ldh [hInSound], a
    ei                      ; the title's HBlank interrupt must not wait for the music
    call SoundUpdate
    xor a
    ldh [hInSound], a
.nosound
    pop hl
    pop de
    pop bc
    pop af
    reti

HudCopy:
    ld hl, wHud
    ld de, $9C00
    REPT 20
        ld a, [hl+]
        ld [de], a
        inc e
    ENDR
    ret

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

ReadJoypad::
    ld a, $20
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    swap a
    ld b, a
    ld a, $10
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

; hl = dest, bc = count, a = value
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

; any VBlank line will do (see the racing game's notes on why not one exact line)
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

; Switch the LCD on. A real DMG shows nothing for the first frame after the LCD
; is enabled, so the first two frames are shown with blank palettes everywhere.
LcdOn::
    push af
    ldh a, [hBGP]
    ldh [hTmp], a
    ldh a, [hOBP0]
    ldh [hTmp + 1], a
    xor a
    ldh [hBGP], a
    ldh [hOBP0], a
    ldh [rBGP], a
    ldh [rOBP0], a
    ldh [rOBP1], a
    ldh [hVBlankFlag], a
    pop af
    ldh [rLCDC], a
    call WaitVBlank
    ldh a, [hTmp]
    ldh [hBGP], a
    ldh a, [hTmp + 1]
    ldh [hOBP0], a
    ret

; a = random byte
Random::
    ld a, [wRand]
    ld b, a
    add a
    add a
    add b
    add 37
    ld [wRand], a
    swap a
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

DEF CUSTOM_SFX EQU 1
INCLUDE "sound.asm"
INCLUDE "game.asm"
INCLUDE "data.asm"
