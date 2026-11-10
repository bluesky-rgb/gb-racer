; shared constants
DEF ROAD_ROWS    EQU 72
DEF SKY_ROWS     EQU 80
DEF HUD_LINE     EQU 128         ; first screen line of the HUD window
DEF SCX_CENTER   EQU 48          ; SCX that centres the road texture on screen
DEF PITCH_FLAT   EQU 8

DEF SPEED_MAX    EQU $2580       ; 37.5 stripe-phase units per frame (shown as 300 km/h)
DEF SPEED_OFFROAD EQU $0C00
DEF ROAD_EDGE    EQU 76          ; |player x| beyond this is off the road

DEF LCDC_GAME    EQU LCDC_ON | LCDC_WINMAP | LCDC_WINON | LCDC_OBJ16 | LCDC_OBJON | LCDC_BGON
DEF LCDC_MENU    EQU LCDC_ON | LCDC_OBJ16 | LCDC_OBJON | LCDC_BGON

DEF SEG_SIZE     EQU 4           ; bytes per track segment: length, curve, hill, flags
