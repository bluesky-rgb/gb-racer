; Data: sprite frames, tables, texts, sound effects and graphics

INCLUDE "frames.asm"
INCLUDE "stages.asm"

SECTION "TypeTab", ROM0, ALIGN[8]
; hp, half width, half height, centre offset, score (BCD, points/10: low, high), reload, first shot
TypeTab::
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 1, 7, 7, 8, $10, $00, 0, 45      ; dart
    db 3, 7, 5, 8, $20, $00, 100, 40    ; saucer
    db 14, 8, 8, 8, $50, $00, 70, 50    ; heavy
    db 150, 14, 14, 16, $00, $10, 45, 90 ; boss
    db 0, 0, 0, 8, 0, 0, 0, 0           ; explosion
    db 1, 7, 7, 8, 0, 0, 0, 0           ; power capsule
    db 0, 0, 0, 4, 0, 0, 0, 0           ; enemy shot

SECTION "Tables", ROM0
TypeFrames:
    dw 0, FrDart, FrSaucer0, FrHeavy, FrBoss, FrBoom0, FrPower
; shot fans, 1/16 px per frame (vx, vy)
Spread3: db -8, 22,  0, 24,  8, 22
Spread5: db -16, 16,  -8, 22,  0, 24,  8, 22,  16, 16

StageSongs:   dw SongStage1, SongStage2, SongStage3
StageBanners: dw TxtStage1, TxtStage2, TxtStage3

SceneTable:   ; tiles, tile count, map
    dw BgStage1
    db BG_STAGE1_TILES
    dw MapStage1
    ds 3
    dw BgStage2
    db BG_STAGE2_TILES
    dw MapStage2
    ds 3
    dw BgStage3
    db BG_STAGE3_TILES
    dw MapStage3
    ds 3
    dw BgTitle
    db BG_TITLE_TILES
    dw MapTitle
    ds 3

; banners: OAM x of the first letter, letters ($FE space), $FF
TxtStage1:  db 60, LETTER_S, LETTER_T, LETTER_A, LETTER_G, LETTER_E, $FE, LETTER_1, $FF
TxtStage2:  db 60, LETTER_S, LETTER_T, LETTER_A, LETTER_G, LETTER_E, $FE, LETTER_2, $FF
TxtStage3:  db 60, LETTER_S, LETTER_T, LETTER_A, LETTER_G, LETTER_E, $FE, LETTER_3, $FF
TxtWarning: db 60, LETTER_W, LETTER_A, LETTER_R, LETTER_N, LETTER_I, LETTER_N, LETTER_G, $FF
TxtClear:   db 64, LETTER_C, LETTER_L, LETTER_E, LETTER_A, LETTER_R, LETTER_BANG, $FF
TxtOver:    db 52, LETTER_G, LETTER_A, LETTER_M, LETTER_E, $FE, LETTER_O, LETTER_V, LETTER_E, LETTER_R, $FF

TxtPress:   db "    PRESS  START    "
TxtHi:      db "    HI              "
TxtFrom:    db "    START STAGE     "

; sound effects (same format as the racing game's driver)
SfxTable:
    dw SfxShot, SfxBoom, SfxBigBoom, SfxPower, SfxBomb, SfxSelect, SfxAlarm
SfxShot:    db 1, 2, 55, 2, 50, 2, 45, 0
SfxPower:   db 1, 4, 48, 4, 52, 4, 55, 8, 60, 0
SfxSelect:  db 1, 4, 48, 6, 55, 0
SfxAlarm:   db 1, 8, 57, 8, 52, 8, 57, 8, 52, 0
SfxBoom:    db 4, 4, $C1, $45, 8, $A2, $56, 0
SfxBigBoom: db 4, 6, $F2, $5D, 8, $D2, $6C, 16, $A3, $7A, 0
SfxBomb:    db 4, 8, $F4, $4C, 20, $E5, $7F, 0

SECTION "Gfx", ROMX, BANK[1]
FontTiles:: INCBIN "font.bin"
ObjTiles::  INCBIN "obj.bin"
BgStage1:   INCBIN "bg_stage1.bin"
MapStage1:  INCBIN "map_stage1.bin"
BgStage2:   INCBIN "bg_stage2.bin"
MapStage2:  INCBIN "map_stage2.bin"
BgStage3:   INCBIN "bg_stage3.bin"
MapStage3:  INCBIN "map_stage3.bin"
BgTitle:    INCBIN "bg_title.bin"
MapTitle:   INCBIN "map_title.bin"
