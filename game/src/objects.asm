; Sprites: the player's car, rival cars and roadside scenery, all placed on the
; same per-row geometry the road renderer just produced (wRowX and the hill map).

DEF N_RIVALS     EQU 7
DEF RIVAL_SIZE   EQU 8
; rival fields
DEF RV_FRAC      EQU 0           ; distance: fraction, phase, periods (16-bit)
DEF RV_PHASE     EQU 1
DEF RV_PER       EQU 2
DEF RV_SPEED     EQU 4           ; 8.8 phase units per frame
DEF RV_LAT       EQU 6           ; lateral position, eighths of the road half-width
DEF RV_FLAGS     EQU 7           ; bit 0: light paint, bits 1-7: weave timer

DEF OBJ_RANGE    EQU 42          ; periods ahead at which scenery starts to be drawn
DEF PLAYER_Y     EQU 122         ; screen line of the player's car (bottom)
DEF PLAYER_ROW   EQU 66

SECTION "ObjVars", WRAM0[$C400]
wRivals::       ds N_RIVALS * RIVAL_SIZE
wRivalRow::     ds N_RIVALS      ; row each rival is drawn at this frame ($FF = not visible)
wObjFirst::     dw               ; first scenery entry not yet passed
wObjStart::     dw
wObjEnd::       dw
wLapPhase::     db               ; distance since the start line
wLapPer::       dw
wTrackLen::     dw               ; lap length in periods
wOamEnd::       db               ; low byte of the first unused OAM slot last frame
wPosition::     db               ; race position (1 = leading)
wBump::         db               ; frames of collision shake left
wSteerPose::    db               ; 0 straight, 1 left, 2 right
wSceneFrames::  dw               ; frame pointer table of the loaded scene
wShowCount::    db               ; countdown sprite: 0 none, 1-3 digits, 4 GO

SECTION "Objects", ROM0

; hl -> frame pieces (after the count byte), de -> OAM slot, b = base Y + 16, c = centre x + 64
; Pieces that fall outside the screen are skipped so they do not use up the
; ten-sprites-per-line budget.
EmitPieces:
    ld a, [hl+]             ; dy
    cp $80
    ret z
    add b
    ld [de], a
    ld a, [hl+]             ; dx + 72
    add c
    xor $80
    dec a
    cp 167
    jr nc, .skip
    inc a
    inc e
    ld [de], a
    inc e
    ld a, [hl+]
    ld [de], a
    inc e
    ld a, [hl+]
    ld [de], a
    inc e
    jr EmitPieces
.skip
    inc hl
    inc hl
    jr EmitPieces

; hl -> frame (count byte first). Emits it if OAM has room. de = OAM cursor.
EmitFrame:
    ld a, [hl+]
    add a
    add a
    add e
    cp 161
    ret nc                  ; no room left
    jr EmitPieces

; a = row (0..71), c = lateral offset in pixels, carry = right-hand side
; -> b = OAM Y of the base line, c = centre x + 64. Carry set when off screen.
PlaceAtRow:
    ld l, a
    ld a, [wMapPage]
    ld h, a
    ld a, [hl]              ; screen line where this row is drawn
    ld b, a
    ld h, HIGH(wRowX)
    ld a, SCX_CENTER
    jr c, .right
    sub [hl]                ; road centre relative to the middle of the screen (signed)
    xor $80
    add 16                  ; + 144 as a 9-bit number: carry is the high bit
    ld l, a
    ld a, 0
    adc a
    ld h, a
    ld a, l
    sub c
    ld c, a
    ld a, h
    sbc 0
    jr .check
.right
    sub [hl]
    xor $80
    add 16
    ld l, a
    ld a, 0
    adc a
    ld h, a
    ld a, l
    add c
    ld c, a
    ld a, h
    adc 0
.check
    ld a, b
    jr nz, .off
    add 16
    ld b, a
    ret                     ; (carry clear: lines are below 240)
.off
    scf
    ret

; ---------------------------------------------------------------- per frame
BuildSprites::
    ld de, wOAM

    ; countdown digits float above the car
    ld a, [wShowCount]
    or a
    jr z, .nocount
    dec a
    add a
    ld l, a
    ld h, 0
    ld bc, CountFrames
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld b, 70 + 16
    ld c, 80 + 64
    call EmitFrame
.nocount

    ; ---- player
    ld hl, FramePlayer0
    ld a, [wSteerPose]
    or a
    jr z, .pose
    ld hl, FramePlayerL
    dec a
    jr z, .pose
    ld hl, FramePlayerR
.pose
    ld b, PLAYER_Y + 16
    ld c, 80 + 64
    ld a, [wBump]
    or a
    jr z, .steady
    rrca
    jr nc, .steady
    inc c
    inc c
    dec b
.steady
    call EmitFrame

    ; ---- rivals: nearest (largest row) first
    push de
    call RivalRows
    pop de
    ld a, [wTmp]            ; index of the nearest visible rival, $FF if none
    cp $FF
    jr z, .scenery
    call DrawRival
    xor a
.rloop
    ld hl, wTmp
    cp [hl]
    jr z, .rnext
    push af
    call DrawRival
    pop af
.rnext
    inc a
    cp N_RIVALS
    jr nz, .rloop

.scenery
    call DrawScenery

    ; ---- hide whatever is left over from the previous frame
    ld a, [wOamEnd]
    ld b, a
    ld a, e
    ld [wOamEnd], a
    ld h, d
    ld l, e
.clear
    ld a, l
    cp b
    ret nc
    ld [hl], 0
    inc l
    inc l
    inc l
    inc l
    jr .clear

; Advance every rival and work out which row it is at; also race position and
; collisions. Leaves the index of the nearest visible rival in wTmp.
RivalRows:
    ld a, $FF
    ld [wTmp], a
    xor a
    ld [wTmp + 1], a        ; best row so far
    ld a, 1
    ld [wPosition], a
    ld a, [wRivalsOn]
    or a
    jr nz, .on
    ld hl, wRivalRow
    ld a, $FF
    ld b, N_RIVALS
.none
    ld [hl+], a
    dec b
    jr nz, .none
    ret
.on
    ld hl, wRivals
    ld c, 0                 ; index
.loop
    ; advance (only once the race is under way)
    ld a, [wRivalMove]
    or a
    jr z, .parked
    push hl
    ld d, h
    ld a, l
    add RV_SPEED
    ld e, a                 ; de -> speed
    ld a, [de]
    add [hl]
    ld [hl+], a
    inc e
    ld a, [de]
    adc [hl]
    ld [hl+], a
    jr nc, .nocarry
    inc [hl]
    jr nz, .nocarry
    inc l
    inc [hl]
.nocarry
    pop hl
.parked
    ; distance ahead of the player: rival - player (phase, periods)
    push hl
    inc l                   ; -> phase
    ld a, [wPosPhase]
    ld b, a
    ld a, [hl+]
    sub b
    ld e, a                 ; e = phase difference
    ld a, [wPosPer]
    ld b, a
    ld a, [hl+]
    sbc b
    ld d, a                 ; d = periods low
    ld a, [wPosPer + 1]
    ld b, a
    ld a, [hl]
    sbc b                   ; a = periods high
    pop hl
    ld b, $FF               ; row: not visible
    bit 7, a
    jr nz, .store           ; behind the player
    push hl
    ld hl, wPosition
    inc [hl]
    pop hl
    or a
    jr nz, .store           ; far ahead
    ld a, d
    cp 32
    jr nc, .store
    add a
    add a
    add a
    ld d, a
    ld a, e
    swap a
    rrca
    and 7
    or d
    ld e, a
    ld d, HIGH(RowNear)
    ld a, [de]
    cp ROAD_ROWS
    jr nc, .store           ; alongside or just passed: off the bottom of the screen
    ld b, a
.store
    ld d, HIGH(wRivalRow)
    ld a, c
    add LOW(wRivalRow)
    ld e, a
    ld a, b
    ld [de], a
    cp $FF
    jr z, .next
    ; nearest so far?
    ld de, wTmp + 1
    ld a, [de]
    cp b
    jr nc, .notbest
    ld a, b
    ld [de], a
    ld a, c
    ld [wTmp], a
.notbest
    ; collision: the rival is right in front of our bumper
    ld a, b
    cp 60
    jr c, .next
    push hl
    push bc
    call RivalHit
    pop bc
    pop hl
.next
    ld a, l
    add RIVAL_SIZE
    ld l, a
    inc c
    ld a, c
    cp N_RIVALS
    jp nz, .loop
    ret

; hl -> rival that is level with the front of the player's car: bump if the lanes overlap
RivalHit:
    push hl
    ld de, RV_LAT
    add hl, de
    ld a, [hl]              ; eighths of the half-width; 9 px each at the car's row
    ld b, a
    add a
    add a
    add a
    add b                   ; * 9 (fits: |lat| <= 12)
    ld b, a
    ld a, [wPlayerX + 1]
    sub b                   ; player - rival, pixels
    ld c, a
    bit 7, a
    jr z, .abs
    cpl
    inc a
.abs
    pop hl
    cp 27
    ret nc
    ; hit: drop to a little under the rival's speed and bounce sideways
    ld de, RV_SPEED
    add hl, de
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    ld a, d
    sub 6
    ld d, a
    ld a, [wSpeed + 1]
    cp d
    ret c                   ; already slower than the rival
    ld a, e
    ld [wSpeed], a
    ld a, d
    ld [wSpeed + 1], a
    ld a, 24
    ld [wBump], a
    ld a, SFX_CRASH
    call SfxPlay
    ld hl, wPlayerX + 1
    ld a, c
    bit 7, a
    jr nz, .left
    ld a, [hl]
    add 5
    ld [hl], a
    ret
.left
    ld a, [hl]
    sub 5
    ld [hl], a
    ret

; a = rival index, de = OAM cursor
DrawRival:
    ld c, a
    add LOW(wRivalRow)
    ld l, a
    ld h, HIGH(wRivalRow)
    ld a, [hl]
    cp $FF
    ret z
    ld b, a                 ; row
    push de
    ; frame for this row's size level
    add 128
    ld e, a
    ld d, HIGH(LevelTab)
    ld a, [de]
    cp 6
    jr nc, .none
    add a
    ld e, a
    ; lateral position and paint
    ld a, c
    add a
    add a
    add a
    add LOW(wRivals + RV_LAT)
    ld l, a
    ld h, HIGH(wRivals)
    ld a, [hl+]
    ld c, a                 ; signed lateral, eighths
    ld a, [hl]
    rrca
    ld hl, RivalFrames
    jr nc, .dark
    ld hl, RivalFramesB
.dark
    ld d, 0
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    push hl
    ; pixels: LatTab[|lat| - 1][row]
    ld a, c
    or a
    jr nz, .offcentre
    ld c, 0
    jr .place
.offcentre
    bit 7, a
    jr z, .mag
    cpl
    inc a
.mag
    dec a
    srl a
    ld e, b
    jr nc, .even
    set 7, e
.even
    add HIGH(LatTab)
    ld d, a
    ld a, [de]
    ld e, a
    ld a, c
    ld c, e
    add a                   ; carry = left side (negative)
    ccf                     ; carry = right side
.place
    ld a, b
    call PlaceAtRow
    pop hl
    pop de
    ret c
    jp EmitFrame
.none
    pop de
    ret

; Scenery entries are sorted by distance from the start line:
;   dw position (periods), db frame-table offset, db lateral - 1 (bit 7 = right side)
DrawScenery:
    ld a, e
    ldh [hOamLo], a
    ; distances are measured from the lap position rounded up to a whole period
    ld a, [wLapPhase]
    cpl
    inc a
    ld e, a
    ld a, [wLapPer]
    ld c, a
    ld a, [wLapPer + 1]
    ld b, a
    ld a, e
    or a
    jr z, .whole
    inc bc
.whole
    swap a
    rrca
    and 7
    ldh [hScP3], a          ; fraction of a period, in eighths
    ld a, 7
    ldh [hScCount], a       ; at most this many objects per frame
    ld hl, wObjFirst
    ld a, [hl+]
    ld h, [hl]
    ld l, a
.loop
    ld a, [hl+]
    sub c
    ld e, a
    ld a, [hl+]
    sbc b
    jr nc, .ahead
    ; the entry is beyond the start line: add a lap
    ld d, a
    ld a, [wTrackLen]
    add e
    ld e, a
    ld a, [wTrackLen + 1]
    adc d
.ahead
    jp nz, .done            ; more than 255 periods away
    ld a, e
    cp 32
    jp nc, .done
    add a
    add a
    add a
    ld e, a
    ldh a, [hScP3]
    or e
    ld e, a
    ld d, HIGH(RowNear)
    ld a, [de]
    cp ROAD_ROWS
    jr nc, .passed
    ldh [hRow], a
    ld e, a
    ld d, HIGH(LevelTab)
    ld a, [de]
    cp 7
    jp nc, .done            ; too small to draw, and so is everything beyond it
    add a
    add [hl]                ; + frame table offset
    inc hl
    ldh [hType], a
    ; lateral pixels
    ld a, [hl+]
    push hl
    push bc
    ld d, a                 ; keep the side bit
    and $7F
    srl a
    jr nc, .even
    set 7, e
.even
    add HIGH(LatTab)
    ld h, a
    ld l, e
    ld c, [hl]
    ld a, d
    add a                   ; carry = right side
    ldh a, [hRow]
    call PlaceAtRow
    jr c, .skip
    ; frame pointer
    ldh a, [hType]
    ld e, a
    ld d, 0
    ld hl, wSceneFrames
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld d, HIGH(wOAM)
    ldh a, [hOamLo]
    ld e, a
    call EmitFrame
    ld a, e
    ldh [hOamLo], a
.skip
    pop bc
    pop hl
    jr .advance
.passed
    ; this entry is now behind the camera: it stops being the first one
    inc hl
    inc hl
    call .wrap
    ld a, l
    ld [wObjFirst], a
    ld a, h
    ld [wObjFirst + 1], a
    jr .count
.advance
    call .wrap
.count
    ldh a, [hScCount]
    dec a
    ldh [hScCount], a
    jp nz, .loop
.done
    ld d, HIGH(wOAM)
    ldh a, [hOamLo]
    ld e, a
    ret
; hl = entry pointer, wrapped back to the start of the list at its end
.wrap
    ld a, [wObjEnd]
    cp l
    ret nz
    ld a, [wObjEnd + 1]
    cp h
    ret nz
    ld a, [wObjStart]
    ld l, a
    ld a, [wObjStart + 1]
    ld h, a
    ret
