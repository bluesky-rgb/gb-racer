; Road renderer: turns the player's position on the track into per-scanline
; SCX/SCY tables for the HBlank handler.
;
;  pass 1  CurveLoop  walks the 72 texture rows from the bottom of the screen to
;                     the horizon accumulating the curve (second-order) and the
;                     player's sideways offset (first-order) into wRowX.
;  pass 2  LineLoop   walks the screen lines of the current hill profile, picking
;                     the texture row each one shows (hills stretch or squash the
;                     row sequence) and the light/dark variant for the stripe phase.
;
; Both inner loops live in RAM so their per-frame constants can be patched in as
; immediate operands.

SECTION "RoadVars", WRAM0
wPlayerX::      dw      ; 8.8 signed, pixels at the bottom of the screen (+ = right of centre)
wSpeed::        dw      ; 8.8, stripe-phase units per frame
wPosFrac::      db      ; distance travelled: fraction, phase (256 = one stripe period), periods
wPosPhase::     db
wPosPer::       dw
wSegPtr::       dw      ; current track segment
wSegRemFrac::   db      ; distance left in the current segment
wSegRemPhase::  db
wSegRemPer::    db
wTrackPtr::     dw      ; first segment
wTrackEnd::     dw      ; one past the last segment
wCurCurve::     db      ; curve of the current segment (signed)
wPitch::        db      ; hill profile 0..16 (8 = flat)
wPitchAcc::     db
wSkyFrac::      db
wSkyX::         db
wHorizon::      db      ; first road line on screen this frame
wMapStart::     db
wMapPage::      db
wSegList::      ds 4 * 3 ; limit row, -curve lo, -curve hi
wSegCount::     db
wPrevLimit::    db
wSkyLock::      db      ; non-zero: fixed sky scroll (title logo)

SECTION "RamCodeSrc", ROM0
RamCodeSrc::
LOAD "RamCode", WRAM0[$C200]
RamCodeStart::
; hl = SCX accumulator (8.8), de = step, bc -> wRowX[row]. Four rows per pass,
; so limits are always one below a multiple of four. Runs until c == limit.
CurveLoop::
    FOR N, 4
        ld a, h
        ld [bc], a
        add hl, de
        ld a, e
        add a, 0
        DEF pCurveLo{d:N} EQU @ - 1
        ld e, a
        ld a, d
        adc a, 0
        DEF pCurveHi{d:N} EQU @ - 1
        ld d, a
        dec c
    ENDR
    ld a, c
    cp $FF
DEF pCurveLimit EQU @ - 1
    jr nz, CurveLoop
    ret

; de -> hill line map (ends on a page boundary, even length), b = table page, c = table index
LineLoop::
    FOR N, 2
        ld a, [de]
        ld l, a
        ld h, HIGH(wRowX)
        ld a, [hl]
        ld [bc], a              ; SCX
        ld h, HIGH(StripeTab)
        DEF pStripePage{d:N} EQU @ - 1
        res 7, l
        DEF pStripeBit{d:N} EQU @ - 1
        ld a, [hl]
        sub c
        inc b
        ld [bc], a              ; SCY = source line - screen line
        dec b
        dec c
        inc e
    ENDR
    jr nz, LineLoop
    ret
RamCodeEnd::
ENDL

SECTION "Road", ROM0

; b = periods, c = phase  ->  a = row at that distance
;   0..71 visible row, 72..127 nearer than the bottom of the screen, $FF beyond the horizon
RowLookup:
    ld a, b
    cp 32
    jr nc, .far
    add a
    add a
    add a
    ld e, a
    ld a, c
    swap a
    rrca
    and 7
    or e
    ld e, a
    ld d, HIGH(RowNear)
    ld a, [de]
    ret
.far
    cp 127
    jr nc, .beyond
    ld e, a
    ld d, 0
    ld hl, RowFar
    add hl, de
    ld a, [hl]
    ret
.beyond
    ld a, $FF
    ret

; List the segment boundaries visible ahead as (limit row, curve) pairs.
BuildSegList:
    ld hl, wSegPtr
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [wSegRemPer]
    ld b, a
    ld a, [wSegRemPhase]
    ld c, a
    ld de, wSegList
    xor a
    ld [wSegCount], a
    ld a, 71
    ld [wPrevLimit], a
.loop                       ; bc = distance to the next boundary
    push hl
    push de
    push bc
    call RowLookup
    pop bc
    pop de
    pop hl
    cp ROAD_ROWS
    jr c, .quant
    cp $FF
    jr nz, .next            ; boundary is closer than the bottom of the screen
.quant
    inc a                   ; the curve loop works in groups of four rows
    and $FC
    dec a
    cp $FF
    jr z, .emit
    push hl
    ld hl, wPrevLimit
    cp [hl]
    pop hl
    jr nc, .next            ; boundary not above the rows already covered
.emit
    ld [wPrevLimit], a
    ld [de], a
    inc de
    push hl
    inc hl
    ld a, [hl]              ; curve
    pop hl
    cpl
    inc a
    ld [de], a
    inc de
    add a                   ; sign extend
    sbc a
    ld [de], a
    inc de
    ld a, [wSegCount]
    inc a
    ld [wSegCount], a
    cp 4
    jr z, .cap
    ld a, [wPrevLimit]
    inc a
    ret z                   ; reached the horizon
.next
    ; advance to the following segment
    ld a, l
    add SEG_SIZE
    ld l, a
    adc h
    sub l
    ld h, a
    ld a, [wTrackEnd]
    cp l
    jr nz, .nowrap
    ld a, [wTrackEnd + 1]
    cp h
    jr nz, .nowrap
    ld a, [wTrackPtr]
    ld l, a
    ld a, [wTrackPtr + 1]
    ld h, a
.nowrap
    ld a, [hl]
    add b
    ld b, a
    jr nc, .loop
    ld b, $FF
    jr .loop
.cap
    ld a, $FF               ; the fourth entry always runs to the horizon
    ld [wSegList + 3 * 3], a
    ret

MACRO curve_seg
    ld a, [wSegList + \1 * 3 + 1]
    ld [pCurveLo0], a
    ld [pCurveLo1], a
    ld [pCurveLo2], a
    ld [pCurveLo3], a
    ld a, [wSegList + \1 * 3 + 2]
    ld [pCurveHi0], a
    ld [pCurveHi1], a
    ld [pCurveHi2], a
    ld [pCurveHi3], a
    ld a, [wSegList + \1 * 3]
    ld [pCurveLimit], a
    call CurveLoop
    inc a
    jr z, .curvesDone
ENDM

BuildRoad::
    call BuildSegList

    ; hill profile
    ld a, [wPitch]
    ld e, a
    ld d, 0
    ld hl, HillMapStart
    add hl, de
    ld a, [hl]
    ld [wMapStart], a
    ld hl, HillHorizon
    add hl, de
    ld a, [hl]
    ld [wHorizon], a
    ld a, e
    add HIGH(HillPages)
    ld [wMapPage], a

    ; s = SCX_CENTER + px at the bottom row, stepping by -px/72 per row
    ld hl, wPlayerX
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    ld hl, SCX_CENTER << 8
    add hl, de
    push hl
    ld h, d
    ld l, e
    REPT 6
        sra h
        rr l
    ENDR
    ld b, h
    ld c, l                 ; bc = px / 64
    REPT 3
        sra h
        rr l
    ENDR                    ; hl = px / 512
    ld a, l
    sub c
    ld e, a
    ld a, h
    sbc b
    ld d, a                 ; de = -(px/64 - px/512) ~ -px/72
    pop hl
    ld bc, (HIGH(wRowX) << 8) | 71
    curve_seg 0
    curve_seg 1
    curve_seg 2
    curve_seg 3
.curvesDone

    ; stripe phase selects one of 64 source-line tables
    ld a, [wPosPhase]
    srl a
    srl a
    srl a
    ld b, a
    ld a, $BD               ; res 7, l
    jr nc, .even
    ld a, $FD               ; set 7, l
.even
    ld [pStripeBit0], a
    ld [pStripeBit1], a
    ld a, b
    add HIGH(StripeTab)
    ld [pStripePage0], a
    ld [pStripePage1], a

    ld a, [wMapPage]
    ld d, a
    ld a, [wMapStart]
    ld e, a
    ldh a, [hTabPage]
    xor HIGH(wTab0X) ^ HIGH(wTab1X)
    ld b, a
    ld c, HUD_LINE - 2
    call LineLoop

    ; c = horizon - 2: the kick line. It keeps the sky's scroll values.
    ld a, c
    ldh [hPendKick], a
    ld a, [wSkyLock]
    or a
    jr nz, .locked          ; the title card must not slide away
    ld a, [wSkyX]
.locked
    ld [bc], a
    ldh [hPendSkyX], a
    inc b
    ld a, [wHorizon]
    ld l, a
    ld a, SKY_ROWS
    sub l
    ld [bc], a
    ldh [hPendSkyY], a
    dec b
    ld a, b
    ldh [hPendPage], a
    ret
