; Data: lookup tables, courses, sprite frames and graphics

INCLUDE "tables.asm"
INCLUDE "tracks.asm"

SECTION "SpriteFrames", ROM0
INCLUDE "frames.asm"

SECTION "SceneTable", ROM0
MACRO scene ; bank label, tiles, count, skip, map, BGP, objects, object tile count, frame table
    db BANK(\1)
    dw \1
    db \2, \3
    dw \4
    db \5
    dw \6, (\7) * 16, \8
    ds 2
ENDM
SceneTable::
    scene BgCoast,  BG_COAST_TILES,  BG_COAST_SKIP,  MapCoast,  %11100100, ObjCoast,  OBJ_COAST_TILES,  SceneFrames_coast
    scene BgCanyon, BG_CANYON_TILES, BG_CANYON_SKIP, MapCanyon, %11100100, ObjCanyon, OBJ_CANYON_TILES, SceneFrames_canyon
    scene BgNight,  BG_NIGHT_TILES,  BG_NIGHT_SKIP,  MapNight,  %11111000, ObjNight,  OBJ_NIGHT_TILES,  SceneFrames_night
    scene BgTitle,  BG_TITLE_TILES,  BG_TITLE_SKIP,  MapTitle,  %11100100, ObjTitle,  OBJ_TITLE_TILES,  SceneFrames_title

SECTION "Gfx2", ROMX, BANK[2]
FontTiles::  INCBIN "font.bin"
ObjCommon::  INCBIN "obj_common.bin"
BgCoast::    INCBIN "bg_coast.bin"
MapCoast::   INCBIN "map_coast.bin"
ObjCoast::   INCBIN "obj_coast.bin"
BgCanyon::   INCBIN "bg_canyon.bin"
MapCanyon::  INCBIN "map_canyon.bin"
ObjCanyon::  INCBIN "obj_canyon.bin"

SECTION "Gfx3", ROMX, BANK[3]
BgNight::    INCBIN "bg_night.bin"
MapNight::   INCBIN "map_night.bin"
ObjNight::   INCBIN "obj_night.bin"
BgTitle::    INCBIN "bg_title.bin"
MapTitle::   INCBIN "map_title.bin"
ObjTitle::   INCBIN "obj_title.bin"
