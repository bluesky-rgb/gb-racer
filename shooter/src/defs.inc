; shared constants
DEF HUD_LINE    EQU 136          ; the window (one row of text) starts here
DEF LCDC_PLAY   EQU LCDC_ON | LCDC_WINMAP | LCDC_WINON | LCDC_OBJ16 | LCDC_OBJON | LCDC_BGON

DEF MAX_EN      EQU 8
DEF MAX_ESHOT   EQU 12
DEF MAX_PSHOT   EQU 8
DEF OBJ_SIZE    EQU 16

; object fields (enemies and enemy shots share the movement layout)
DEF O_TYPE      EQU 0            ; 0 = free slot
DEF O_XS        EQU 1            ; x: OAM coordinate (left edge + 8), 8.8
DEF O_X         EQU 2
DEF O_YS        EQU 3            ; y: OAM coordinate (top edge + 16), 8.8
DEF O_Y         EQU 4
DEF O_VXL       EQU 5            ; velocity, signed 8.8 pixels per frame
DEF O_VXH       EQU 6
DEF O_VYL       EQU 7
DEF O_VYH       EQU 8
DEF O_HP        EQU 9
DEF O_T         EQU 10           ; age in frames (stops at 255)
DEF O_PAT       EQU 11
DEF O_FIRE      EQU 12           ; frames until the next shot
DEF O_FLASH     EQU 13
DEF O_X0        EQU 14
DEF O_ARG       EQU 15

DEF T_DART      EQU 1
DEF T_SAUCER    EQU 2
DEF T_HEAVY     EQU 3
DEF T_BOSS      EQU 4
DEF T_BOOM      EQU 5
DEF T_POWER     EQU 6
DEF T_ESHOT     EQU 7

DEF P_STRAIGHT  EQU 0
DEF P_WEAVE     EQU 1
DEF P_DIVE      EQU 2
DEF P_SWEEPL    EQU 3
DEF P_SWEEPR    EQU 4
DEF P_HOVER     EQU 5
DEF P_BOSS      EQU 6

DEF ST_TITLE    EQU 0
DEF ST_PLAY     EQU 1
DEF ST_OVER     EQU 2

DEF SFX_SHOT    EQU 1
DEF SFX_BOOM    EQU 2
DEF SFX_BIGBOOM EQU 3
DEF SFX_POWER   EQU 4
DEF SFX_BOMB    EQU 5
DEF SFX_ALARM   EQU 7
