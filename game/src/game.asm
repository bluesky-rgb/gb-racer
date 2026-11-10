; Game flow: title / course select / race, the player's car physics, timers and HUD.

DEF ST_TITLE     EQU 0
DEF ST_SELECT    EQU 1
DEF ST_RACE      EQU 2

DEF RS_COUNT     EQU 0           ; 3-2-1 countdown
DEF RS_RACING    EQU 1
DEF RS_FINISHED  EQU 2
DEF RS_TIMEUP    EQU 3
DEF RS_ATTRACT   EQU 4           ; self-driving backdrop for the menus

DEF LAPS         EQU 3
DEF PAD_GAS      EQU KEY_A
DEF COURSE_NAME  EQU 15          ; offset of the name inside a course header

SECTION "GameVars", WRAM0
wHud::          ds 40           ; two rows of 20 tiles shown in the HUD window
wTmp::          ds 8
wState::        db
wCourse::       db              ; selected course 0..2
wCoursePtr::    dw
wRaceState::    db
wCountTimer::   db
wLap::          db
wTimeLeft::     db              ; seconds on the clock
wTimeFrame::    db
wBonus::        db
wLtFrame::      db              ; current lap time
wLtSec::        db
wLtMin::        db
wTotFrame::     db              ; whole race time
wTotSec::       db
wTotMin::       db
wMsgPtr::       dw              ; 8-character message shown in the HUD
wMsgTimer::     db
wPad::          db              ; buttons driving the car (player or autopilot)
wPaused::       db
wStateTimer::   dw
wRivalMove::    db
wRivalsOn::     db
wBlink::        db

SECTION "Game", ROM0

GameStart::
    ei
    ld a, %11100000         ; object palettes: white, mid, black
    ldh [hOBP1], a
    ld a, %11010000
    ldh [hOBP0], a
    xor a
    ld [wCourse], a
    call LcdOff
    call LoadCommonSprites
    ; fall through

; ---------------------------------------------------------------- title
TitleInit:
    ld a, ST_TITLE
    ld [wState], a
    ld a, 3
    call StartCourse        ; attract loop behind the logo
    ld a, SCX_CENTER
    ld [wSkyLock], a
    ld hl, SongTitle
    call SongPlay
    ld a, 2
    call EngineSet
    call TitleHud
    call ShowScreen

MainLoop:
    call WaitVBlank
    call ReadJoypad
    ld a, [wState]
    cp ST_RACE
    jr z, .race
    ; ---- menus: the road keeps rolling under autopilot
    call MenuUpdate
    call Autopilot
    call RaceFrame
    jr MainLoop
.race
    call RaceUpdate
    jr MainLoop

; build one frame of the 3D view from the current state
RaceFrame:
    call UpdatePlayer
    call BuildRoad
    call BuildSprites
    ld a, 1
    ldh [hFrameReady], a
    ret

MenuUpdate:
    ld hl, wBlink
    inc [hl]
    ld a, [wState]
    cp ST_SELECT
    jr z, .select
    ; title: blink PRESS START
    ld a, [hl]
    and 31
    jr nz, .keys
    bit 5, [hl]
    ld de, TextPressStart
    jr z, .put
    ld de, TextBlank
.put
    ld hl, wHud
    call PutText20
.keys
    ldh a, [hKeysNew]
    and KEY_START | KEY_A
    ret z
    ld a, ST_SELECT
    ld [wState], a
    ld a, SFX_SELECT
    call SfxPlay
    jp SelectHud
.select
    ldh a, [hKeysNew]
    ld b, a
    bit KEYB_RIGHT, b
    jr z, .noright
    ld a, [wCourse]
    inc a
    cp 3
    jr c, .set
    xor a
    jr .set
.noright
    bit KEYB_LEFT, b
    jr z, .noleft
    ld a, [wCourse]
    sub 1
    jr nc, .set
    ld a, 2
.set
    ld [wCourse], a
    ld a, SFX_BEEP
    call SfxPlay
    jp SelectHud
.noleft
    ld a, b
    and KEY_START | KEY_A
    jr nz, .go
    bit KEYB_B, b
    ret z
    ld a, ST_TITLE
    ld [wState], a
    jp TitleHud
.go
    ld a, SFX_GO
    call SfxPlay
    ; a short beat so the confirm sound is heard, then load the course
    ld b, 20
.wait
    push bc
    call WaitVBlank
    call Autopilot
    call RaceFrame
    pop bc
    dec b
    jr nz, .wait
    pop af                  ; drop the return into MainLoop's menu branch
    jp RaceStart

TitleHud:
    ld hl, wHud
    ld de, TextPressStart
    call PutText20
    ld de, TextControls
    jp PutText20

SelectHud:
    ld hl, wHud
    ld de, TextSelect
    call PutText20
    ld de, TextSelect2
    call PutText20
    ; course name
    ld a, [wCourse]
    call CoursePtr
    ld de, COURSE_NAME
    add hl, de
    ld d, h
    ld e, l
    ld hl, wHud + 2
    ld b, 16
    jp CopyDE

; de -> 20 characters, hl -> destination; advances both
PutText20:
    ld b, 20
CopyDE:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, CopyDE
    ret

TextPressStart: db "    PRESS START     "
TextBlank:      db "                    "
TextControls:   db " A-GAS      B-BRAKE "
TextSelect:     db "<                  >"
TextSelect2:    db "  LEFT/RIGHT  A-GO  "
TextRace0:      db "c00 POS 8/8  LAP 1/3"
TextRace1:      db "  0kh        0'00\"00"
TextFinish:     db "FINISH! "
TextTimeUp:     db "TIME UP!"
TextCheck:      db "EXTEND! "
TextFinal:      db "LAST LAP"
TextLap2:       db " LAP 2  "
TextGo:         db "  GO!   "
TextPause:      db " PAUSE  "
TextOver:       db "GAMEOVER"
TextNone:       db "        "
TextPressSt:    db "PUSH START TO EXIT  "

; a = course number (3 = title loop) -> hl = course header
CoursePtr:
    add a
    ld e, a
    ld d, 0
    ld hl, CourseTable
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ret

; ---------------------------------------------------------------- course setup
; a = course number. Loads its scene with the LCD off and resets all race state.
StartCourse:
    call CoursePtr
    ld a, l
    ld [wCoursePtr], a
    ld a, h
    ld [wCoursePtr + 1], a
    ; clear the per-race variables
    push hl
    ld hl, wPlayerX
    ld b, wSegList - wPlayerX
    xor a
.clr
    ld [hl+], a
    dec b
    jr nz, .clr
    ld hl, wRivals
    ld b, wSteerPose - wRivals + 1
.clr2
    ld [hl+], a
    dec b
    jr nz, .clr2
    ld hl, wRaceState
    ld b, wBlink - wRaceState + 1
.clr3
    ld [hl+], a
    dec b
    jr nz, .clr3
    pop hl
    ; segments
    ld a, [hl+]
    ld [wTrackPtr], a
    ld [wSegPtr], a
    ld e, a
    ld a, [hl+]
    ld [wTrackPtr + 1], a
    ld [wSegPtr + 1], a
    ld d, a
    ld a, [de]
    ld [wSegRemPer], a
    inc de
    ld a, [de]
    ld [wCurCurve], a
    inc de
    ld a, [de]              ; start with the first segment's hill profile
    add PITCH_FLAT
    ld [wPitch], a
    ld a, [hl+]
    ld [wTrackEnd], a
    ld a, [hl+]
    ld [wTrackEnd + 1], a
    ; scenery
    ld a, [hl+]
    ld [wObjStart], a
    ld [wObjFirst], a
    ld a, [hl+]
    ld [wObjStart + 1], a
    ld [wObjFirst + 1], a
    ld a, [hl+]
    ld [wObjEnd], a
    ld a, [hl+]
    ld [wObjEnd + 1], a
    ld a, [hl+]
    ld [wTrackLen], a
    ld a, [hl+]
    ld [wTrackLen + 1], a
    ld a, [hl+]             ; scene
    push hl
    call LoadScene
    pop hl
    ld a, [hl+]
    ld [wTimeLeft], a
    ld a, [hl+]
    ld [wBonus], a
    ld a, 1
    ld [wLap], a
    ld a, 59
    ld [wTimeFrame], a
    ld a, RS_ATTRACT
    ld [wRaceState], a
    ld a, 160
    ld [wOamEnd], a
    xor a
    ld [wShowCount], a
    jp ClearOAM

; Show the first frame. The LCD comes on with blank palettes for one frame (a real
; DMG shows nothing on the first frame after the LCD is enabled) and the real
; palettes are applied by the VBlank handler from then on.
ShowScreen:
    call RaceFrame
    ldh a, [hBGP]
    push af
    ldh a, [hOBP0]
    push af
    ldh a, [hOBP1]
    push af
    xor a
    ldh [hBGP], a
    ldh [hOBP0], a
    ldh [hOBP1], a
    ldh [rBGP], a
    ldh [rOBP0], a
    ldh [rOBP1], a
    ldh [hVBlankFlag], a
    ld a, LCDC_GAME
    ldh [rLCDC], a
    call WaitVBlank
    call RaceFrame
    pop af
    ldh [hOBP1], a
    pop af
    ldh [hOBP0], a
    pop af
    ldh [hBGP], a
    ret

; ---------------------------------------------------------------- race
RaceStart:
    call SongStop
    call WaitVBlank
    call LcdOff
    ld a, [wCourse]
    call StartCourse
    ld a, ST_RACE
    ld [wState], a
    xor a
    ld [wSkyLock], a
    ld [wRaceState], a      ; RS_COUNT
    ld [wPad], a
    ld a, 1
    ld [wRivalsOn], a
    ; rivals on the grid
    ld hl, RivalGrid
    ld de, wRivals
    ld b, N_RIVALS * RIVAL_SIZE
.grid
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .grid
    ; HUD
    ld hl, wHud
    ld de, TextRace0
    call PutText20
    ld de, TextRace1
    call PutText20
    call UpdateHud
    ld a, 200
    ld [wCountTimer], a
    ld a, 1
    call EngineSet
    call ShowScreen
    jp MainLoop

RaceUpdate:
    ; ---- pause
    ld a, [wRaceState]
    cp RS_RACING
    jr nz, .nopause
    ldh a, [hKeysNew]
    bit KEYB_START, a
    jr z, .nopause
    ld a, [wPaused]
    xor 1
    ld [wPaused], a
    ld de, TextPause
    jr nz, .pmsg
    ld de, TextNone
.pmsg
    ld hl, wHud + 25
    ld b, 8
    call CopyDE
    call BuildRoad          ; redraw the same view so the HUD change is presented
    call BuildSprites
    ld a, 1
    ldh [hFrameReady], a
    ld a, SFX_SELECT
    call SfxPlay
.nopause
    ld a, [wPaused]
    or a
    ret nz

    ld a, [wRaceState]
    or a
    jr z, .countdown
    dec a
    jr z, .racing
    dec a
    jp z, .finished
    jp .timeup

.countdown
    xor a
    ld [wPad], a
    ld hl, wCountTimer
    dec [hl]
    ld a, [hl]
    ; digits change every 50 frames: 3 at 150, 2 at 100, 1 at 50, GO at 0
    cp 150
    jr z, .beep3
    cp 100
    jr z, .beep2
    cp 50
    jr z, .beep1
    or a
    jr nz, .frame
    ; go!
    ld a, RS_RACING
    ld [wRaceState], a
    ld a, 1
    ld [wRivalMove], a
    ld a, 4
    ld [wShowCount], a
    ld a, 45
    ld [wCountTimer], a
    ld a, SFX_GO
    call SfxPlay
    ld hl, wCoursePtr
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, 13
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    call SongPlay
    jr .frame
.beep3
    ld a, 1
    jr .beep
.beep2
    ld a, 2
    jr .beep
.beep1
    ld a, 3
.beep
    ld [wShowCount], a
    ld a, SFX_BEEP
    call SfxPlay
    jr .frame

.racing
    ldh a, [hKeys]
    ld [wPad], a
    ; GO sign goes away after a moment
    ld a, [wShowCount]
    or a
    jr z, .clock
    ld hl, wCountTimer
    dec [hl]
    jr nz, .clock
    xor a
    ld [wShowCount], a
.clock
    call TickClocks
.frame
    call RaceFrame
    jp UpdateHud

.finished
    call Autopilot
    call RaceFrame
    jr .ending
.timeup
    xor a
    ld [wPad], a
    call RaceFrame
.ending
    ; after a while (or START) go back to the title
    ld hl, wStateTimer
    inc [hl]
    jr nz, .nohi
    inc hl
    inc [hl]
    dec hl
.nohi
    inc hl
    ld a, [hl-]
    cp 2
    jr nc, .exit            ; ~8.5 s
    or a
    jr nz, .prompt
    ld a, [hl]
    cp 150
    ret c
.prompt
    ldh a, [hKeysNew]
    and KEY_START | KEY_A
    ret z
.exit
    call SongStop
    ld a, 2
    call EngineSet
    call WaitVBlank         ; let the sound driver act on both requests
    call WaitVBlank
    call LcdOff
    ; finishing a course moves the cursor on to the next one
    ld a, [wRaceState]
    cp RS_FINISHED
    jr nz, .same
    ld a, [wCourse]
    inc a
    cp 3
    jr c, .keep
    xor a
.keep
    ld [wCourse], a
.same
    pop af                  ; return address of RaceUpdate
    jp TitleInit

; race clock and lap timers, once per frame while racing
TickClocks:
    ld hl, wLtFrame
    call .tick
    ld hl, wTotFrame
    call .tick
    ld hl, wTimeFrame
    dec [hl]
    ret nz
    ld [hl], 60
    ld hl, wTimeLeft
    dec [hl]
    ld a, [hl]
    cp 6
    jr nc, .ok
    or a
    jr z, .out
    ld a, SFX_BEEP          ; last five seconds tick audibly
    jp SfxPlay
.ok
    ret
.out
    ld a, RS_TIMEUP
    ld [wRaceState], a
    ld a, 2
    call EngineSet          ; the car rolls to a stop in silence
    ld de, TextTimeUp
    call SetMessageHold
    ld hl, SongGameOver
    jp SongPlay
.tick
    inc [hl]
    ld a, [hl]
    cp 60
    ret c
    ld [hl], 0
    inc hl
    inc [hl]
    ld a, [hl]
    cp 60
    ret c
    ld [hl], 0
    inc hl
    inc [hl]
    ret

; de -> 8 characters: show them in the HUD for a couple of seconds
SetMessage:
    ld a, 110
    jr SetMessageA
SetMessageHold:
    ld a, 255
SetMessageA:
    ld [wMsgTimer], a
    ld a, e
    ld [wMsgPtr], a
    ld a, d
    ld [wMsgPtr + 1], a
    ret

; called when the car crosses into a new segment (hl -> segment)
SegmentEvent:
    ld a, [wRaceState]
    cp RS_RACING
    ret nz
    inc hl
    inc hl
    inc hl
    ld a, [hl]
    bit 0, a
    jr nz, .checkpoint
    ; first segment again: a lap is done
    ld a, [wSegPtr]
    ld hl, wTrackPtr
    cp [hl]
    ret nz
    ld a, [wSegPtr + 1]
    inc hl
    cp [hl]
    ret nz
    ld hl, wLap
    inc [hl]
    ld a, [hl]
    cp LAPS + 1
    jr z, .finish
    xor a
    ld [wLtFrame], a
    ld [wLtSec], a
    ld [wLtMin], a
    ld a, [wLap]
    cp LAPS
    ld de, TextFinal
    jr z, .bonus
    ld de, TextLap2
    jr .bonus
.checkpoint
    ld de, TextCheck
.bonus
    call SetMessage
    ld a, [wBonus]
    ld b, a
    ld a, [wTimeLeft]
    add b
    cp 100
    jr c, .cap
    ld a, 99
.cap
    ld [wTimeLeft], a
    ld a, SFX_CHECK
    jp SfxPlay
.finish
    ld [hl], LAPS
    ld a, RS_FINISHED
    ld [wRaceState], a
    ld de, TextFinish
    call SetMessageHold
    ld hl, SongFinish
    jp SongPlay

; simple driver for the attract loop and the lap of honour
Autopilot:
    ld b, 0
    ld a, [wSpeed + 1]
    cp $17
    jr nc, .fast
    ld b, PAD_GAS
.fast
    ; aim for the middle, leaning into the bend
    ld a, [wCurCurve]
    add a
    add a
    ld c, a
    ld a, [wPlayerX + 1]
    sub c
    bit 7, a
    jr nz, .neg
    cp 6
    jr c, .done
    set KEYB_LEFT, b
    jr .done
.neg
    cp -6
    jr nc, .done
    set KEYB_RIGHT, b
.done
    ld a, b
    ld [wPad], a
    ret

; ---------------------------------------------------------------- HUD
; a -> b = tens, a = ones
Div10:
    ld b, 0
.loop
    cp 10
    ret c
    sub 10
    inc b
    jr .loop

UpdateHud:
    ; clock
    ld a, [wTimeLeft]
    call Div10
    ld hl, wHud + 1
    ld [hl], b
    inc hl
    ld [hl], a
    ; position and lap
    ld a, [wPosition]
    ld [wHud + 8], a
    ld a, [wLap]
    ld [wHud + 17], a
    ; speed in km/h = speed / 32
    ld a, [wSpeed]
    ld l, a
    ld a, [wSpeed + 1]
    ld h, a
    add hl, hl
    add hl, hl
    add hl, hl              ; h = speed / 32 (0..300 needs 9 bits: carry holds the top one)
    ld a, h
    ld c, 0
    jr nc, .lt256
    ; 256..300
    add 56
    ld c, 2
    jr .hundreds
.lt256
    cp 200
    jr c, .lt200
    sub 200
    ld c, 2
    jr .hundreds
.lt200
    cp 100
    jr c, .hundreds
    sub 100
    ld c, 1
.hundreds
    cp 100
    jr c, .tens
    sub 100
    inc c
.tens
    call Div10
    ld hl, wHud + 20
    ld d, a
    ld a, c
    or a
    jr nz, .h1
    ld a, ' '
    ld [hl+], a
    ld a, b
    or a
    jr nz, .t1
    ld a, ' '
    jr .t2
.h1
    ld [hl+], a
    ld a, b
    jr .t2
.t1
    ld a, b
.t2
    ld [hl+], a
    ld [hl], d
    ; lap time  m'ss"cc
    ld hl, wHud + 33
    ld a, [wLtMin]
    ld [hl+], a
    inc hl
    ld a, [wLtSec]
    call Div10
    ld [hl], b
    inc hl
    ld [hl+], a
    inc hl
    ld a, [wLtFrame]
    ld e, a
    ld d, 0
    push hl
    ld hl, CentiTable
    add hl, de
    ld a, [hl]
    pop hl
    ld d, a
    swap a
    and $0F
    ld [hl+], a
    ld a, d
    and $0F
    ld [hl], a
    ; message window (row 1, columns 5..12)
    ld a, [wMsgTimer]
    or a
    ret z
    cp 255
    jr z, .show             ; held message
    dec a
    ld [wMsgTimer], a
    jr nz, .show
    ld de, TextNone
    jr .put
.show
    ld hl, wMsgPtr
    ld a, [hl+]
    ld d, [hl]
    ld e, a
.put
    ld hl, wHud + 25
    ld b, 8
    jp CopyDE

CentiTable:                 ; frame within the second -> hundredths, BCD
DEF N = 0
REPT 60
    db ((N * 100 / 60) / 10) << 4 | ((N * 100 / 60) % 10)
DEF N += 1
ENDR

; copy the HUD buffer into the window tilemap (VBlank only)
HudCopy::
    ld hl, wHud
    ld de, $9C00
    REPT 20
        ld a, [hl+]
        ld [de], a
        inc e
    ENDR
    ld e, $20
    REPT 20
        ld a, [hl+]
        ld [de], a
        inc e
    ENDR
    ret

; ---------------------------------------------------------------- graphics loading
LoadCommonSprites:
    ld a, BANK(ObjCommon)
    ld [rROMB0], a
    ld hl, ObjCommon
    ld de, $8000
    ld bc, OBJ_COMMON_TILES * 16
    call MemCopy
    ld a, BANK(FontTiles)
    ld [rROMB0], a
    ld hl, FontTiles
    ld de, $9000
    ld bc, FONT_TILES * 16
    call MemCopy
    ld a, 1
    ld [rROMB0], a
    ret

DEF SCENE_SIZE EQU 16
; a = scene number: load BG tiles + map + scenery sprites (LCD must be off)
LoadScene::
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, SceneTable
    add hl, de
    ld a, [hl+]
    ld [wTmp], a            ; bank
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a                 ; de = tiles
    ld a, [hl+]
    ld [wTmp + 1], a        ; tile count
    ld a, [hl+]
    ld [wTmp + 2], a        ; indices skipped after tile 127
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    ld b, a                 ; bc = map
    ld a, [hl+]
    ldh [hBGP], a
    push hl
    push bc
    ld a, [wTmp]
    ld [rROMB0], a
    ; tiles FONT_TILES..127 live at $9000+, the rest at $8800 + skip
    ld h, d
    ld l, e
    ld de, $9000 + FONT_TILES * 16
    ld a, [wTmp + 1]
    ld b, a                 ; tiles remaining
    ld c, FONT_TILES        ; current tile index
.tile
    ld a, c
    cp 128
    jr nz, .same
    push hl
    ld a, [wTmp + 2]
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, $8800
    add hl, de
    ld d, h
    ld e, l
    pop hl
.same
    push bc
    ld b, 16
.byte
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .byte
    pop bc
    inc c
    dec b
    jr nz, .tile
    ; map: 28 rows of 32
    pop hl
    ld de, $9800
    ld bc, 32 * 28
    call MemCopy
    ; scenery sprites follow the common set
    pop hl
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a                 ; source
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    ld b, a                 ; byte count
    ld a, [hl+]
    ld [wSceneFrames], a
    ld a, [hl+]
    ld [wSceneFrames + 1], a
    ld h, d
    ld l, e
    ld de, $8000 + OBJ_COMMON_TILES * 16
    call MemCopy
    ld a, 1
    ld [rROMB0], a
    ; window: blank HUD bar
    ld hl, $9C00
    ld bc, 64
    ld a, ' '
    call MemFill
    ld a, 7
    ldh [rWX], a
    ld a, HUD_LINE
    ldh [rWY], a
    ld a, 1
    ldh [hHudOn], a
    ret

; ---------------------------------------------------------------- car physics
; a = signed multiplier (|a| <= 15), e = unsigned multiplicand -> hl = a * e (signed 16-bit)
MulSmall::
    ld d, 0
    ld hl, 0
    or a
    ret z
    bit 7, a
    jr nz, .neg
    ld b, a
.pos
    add hl, de
    dec b
    jr nz, .pos
    ret
.neg
    cpl
    inc a
    ld b, a
.loop
    add hl, de
    dec b
    jr nz, .loop
    xor a
    sub l
    ld l, a
    sbc a
    sub h
    ld h, a
    ret

UpdatePlayer::
    ld a, [wBump]
    or a
    jr z, .nobump
    dec a
    ld [wBump], a
.nobump
    ; ---- throttle / brake
    ld hl, wSpeed
    ld a, [hl+]
    ld h, [hl]
    ld l, a                 ; hl = speed
    ld a, [wPad]
    ld b, a
    and PAD_GAS
    ld [wEngineGas], a
    jr z, .coast
    ; strong pull at low speed, tapering toward the top
    ld de, $0038
    ld a, h
    cp $10
    jr c, .accel
    ld de, $0024
    cp $1C
    jr c, .accel
    ld de, $0012
.accel
    add hl, de
    jr .braking
.coast
    ld de, -$0018
    add hl, de
    jr c, .braking
    ld hl, 0
.braking
    bit KEYB_B, b
    jr z, .nobrake
    ld de, -$0070
    add hl, de
    jr c, .nobrake
    ld hl, 0
.nobrake
    ; off the road: drag down to a crawl
    ld a, [wPlayerX + 1]
    bit 7, a
    jr z, .absx
    cpl
    inc a
.absx
    cp ROAD_EDGE
    jr c, .onroad
    ld a, h
    cp HIGH(SPEED_OFFROAD)
    jr c, .onroad
    ld de, -$0060
    add hl, de
    ldh a, [hFrame]
    and 7
    jr nz, .onroad
    ld a, SFX_SKID
    call SfxPlay
.onroad
    ; clamp to top speed
    ld a, h
    cp HIGH(SPEED_MAX)
    jr c, .speedok
    jr nz, .clamp
    ld a, l
    cp LOW(SPEED_MAX)
    jr c, .speedok
.clamp
    ld hl, SPEED_MAX
.speedok
    ld a, l
    ld [wSpeed], a
    ld a, h
    ld [wSpeed + 1], a

    ; ---- advance along the track
    ld d, h
    ld e, l                 ; de = speed
    ld hl, wPosFrac
    ld a, [hl]
    add e
    ld [hl+], a
    ld a, [hl]
    adc d
    ld [hl+], a
    jr nc, .nocarry
    inc [hl]
    jr nz, .nocarry
    inc hl
    inc [hl]
.nocarry
    ; distance since the start line (the fraction is shared with wPosFrac)
    ld hl, wLapPhase
    ld a, [wPosPhase]
    ld [hl+], a
    jr nc, .lapsame
    inc [hl]
    jr nz, .lapsame
    inc hl
    inc [hl]
.lapsame
    ld hl, wSegRemFrac
    ld a, [hl]
    sub e
    ld [hl+], a
    ld a, [hl]
    sbc d
    ld [hl+], a
    jr nc, .sameseg
    ld a, [hl]
    sub 1
    ld [hl], a
    jr nc, .sameseg
    call NextSegment
.sameseg

    ; ---- steering: faster car, quicker response
    ld a, [wSpeed]
    ld l, a
    ld a, [wSpeed + 1]
    ld h, a
    REPT 5
        srl h
        rr l
    ENDR                    ; hl = speed / 32 (pixels per frame, 8.8)
    ld d, h
    ld e, l
    ld hl, wPlayerX
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    xor a
    ld [wSteerPose], a
    ld a, [wPad]
    ld b, a
    bit KEYB_RIGHT, b
    jr z, .noright
    add hl, de
    ld a, 2
    ld [wSteerPose], a
.noright
    bit KEYB_LEFT, b
    jr z, .noleft
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a
    ld a, 1
    ld [wSteerPose], a
.noleft
    ld a, d
    or e
    jr nz, .moving
    ld [wSteerPose], a      ; no leaning while standing still
.moving
    push hl
    ; ---- curves push the car outwards and slide the scenery
    ld a, [wSpeed + 1]
    ld e, a
    ld a, [wCurCurve]
    call MulSmall           ; hl = curve * speed (8.8 pixels)
    ld d, h
    ld e, l
    ld hl, wSkyFrac
    ld a, [hl]
    add e
    ld [hl+], a
    ld a, [hl]
    adc d
    ld [hl], a
    pop hl
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a
    ; clamp x to +-100
    ld a, h
    cp 100
    jr c, .xok
    cp -100
    jr nc, .xok
    bit 7, a
    ld hl, 100 << 8
    jr z, .xok
    ld hl, -100 << 8
.xok
    ld a, l
    ld [wPlayerX], a
    ld a, h
    ld [wPlayerX + 1], a

    ; ---- hill profile eases toward the current segment's value as we drive
    ld a, [wSpeed + 1]
    ld b, a
    ld a, [wPitchAcc]
    add b
    cp 96
    jr c, .pitchdone
    sub 96
    ld [wPitchAcc], a
    ld hl, wSegPtr
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    inc hl
    inc hl
    ld a, [hl]              ; hill -8..8
    add PITCH_FLAT
    ld b, a
    ld a, [wPitch]
    cp b
    ret z
    jr c, .up
    dec a
    ld [wPitch], a
    ret
.up
    inc a
    ld [wPitch], a
    ret
.pitchdone
    ld [wPitchAcc], a
    ret

; step wSegPtr to the next segment and add its length to the remaining distance
NextSegment::
    ld hl, wSegPtr
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, SEG_SIZE
    add hl, de
    ld a, [wTrackEnd]
    cp l
    jr nz, .nowrap
    ld a, [wTrackEnd + 1]
    cp h
    jr nz, .nowrap
    ; lap boundary: the distance since the start line starts over
    ld a, [wTrackLen]
    ld e, a
    ld a, [wTrackLen + 1]
    ld d, a
    ld a, [wLapPer]
    sub e
    ld [wLapPer], a
    ld a, [wLapPer + 1]
    sbc d
    ld [wLapPer + 1], a
    ; scenery list starts over as well
    ld a, [wObjStart]
    ld [wObjFirst], a
    ld a, [wObjStart + 1]
    ld [wObjFirst + 1], a
    ld a, [wTrackPtr]
    ld l, a
    ld a, [wTrackPtr + 1]
    ld h, a
.nowrap
    ld a, l
    ld [wSegPtr], a
    ld a, h
    ld [wSegPtr + 1], a
    ld a, [wSegRemPer]
    add [hl]
    ld [wSegRemPer], a
    inc hl
    ld a, [hl]
    ld [wCurCurve], a
    dec hl
    jp SegmentEvent
