; Sound driver: 4-channel music sequencer, sound effects and the engine drone.
; Called once per frame from the VBlank handler.
;
; Stream bytes:  $00-$47 note (C2 upward)   $48 rest
;                $80-$BF set length (n+1 ticks)   $C0-$CF instrument   $D0-$D7 arpeggio type
;                $F0 addr  jump   $F1 stop   $F2 addr  call pattern   $F3 return

DEF CH_PTR      EQU 0
DEF CH_RET      EQU 2
DEF CH_LEN      EQU 4
DEF CH_REMAIN   EQU 5
DEF CH_INSTR    EQU 6
DEF CH_NOTE     EQU 7
DEF CH_ARP      EQU 8
DEF CH_ON       EQU 9
DEF CH_SIZE     EQU 10
DEF NOTE_REST   EQU $48

DEF SFX_BEEP    EQU 1
DEF SFX_GO      EQU 2
DEF SFX_CHECK   EQU 3
DEF SFX_CRASH   EQU 4
DEF SFX_SKID    EQU 5
DEF SFX_SELECT  EQU 6

SECTION "SoundVars", WRAM0[$C500]
wChan::         ds CH_SIZE * 4
wTempo::        db
wTick::         db
wSongOn::       db
wCurChan::      db
wEngineOn::     db              ; channel 3 belongs to the engine instead of the music
wEngineGas::    db              ; throttle held
wSfxPtr1::      dw              ; pulse effect in progress (0 = none)
wSfxTime1::     db
wSfxPtr4::      dw              ; noise effect in progress
wSfxTime4::     db
wArpPhase::     db
wSongReq::      dw
wSongReqFlag::  db              ; 1 = start wSongReq, 2 = stop
wEngineReq::    db              ; 1 = on, 2 = off
wSfxReq::       db

SECTION "Sound", ROM0

SoundInit::
    ld a, $80
    ldh [rNR52], a
    ld a, $77
    ldh [rNR50], a
    ld a, $FF
    ldh [rNR51], a
    xor a
    ldh [rNR12], a
    ldh [rNR22], a
    ldh [rNR30], a
    ldh [rNR42], a
    ld [wSongOn], a
    ld [wEngineOn], a
    ld hl, wSfxPtr1
    ld b, 12
.clr
    ld [hl+], a
    dec b
    jr nz, .clr
    ret

; hl -> 16 bytes of wave RAM contents
LoadWave:
    xor a
    ldh [rNR30], a
    ld c, LOW(rWAVE)
    ld b, 16
.loop
    ld a, [hl+]
    ldh [c], a
    inc c
    dec b
    jr nz, .loop
    ret

; ---- requests from the main program. They are single-byte handshakes that the
; driver (which runs inside the VBlank interrupt) picks up, so the main program never
; has to disable interrupts while the raster effect is running.

; hl -> song header: start playing it at the next frame
SongPlay::
    ld a, l
    ld [wSongReq], a
    ld a, h
    ld [wSongReq + 1], a
    ld a, 1
    ld [wSongReqFlag], a
    ret

SongStop::
    ld a, 2
    ld [wSongReqFlag], a
    ret

; a = 1 engine drone on (takes over channel 3), 2 = off
EngineSet::
    ld [wEngineReq], a
    ret

; a = effect number
SfxPlay::
    ld [wSfxReq], a
    ret

; hl -> song header (tempo, 4 channel pointers)
SongStart:
    ld a, [hl+]
    ld [wTempo], a
    ld a, 1
    ld [wTick], a
    ld de, wChan
    ld b, 4
.chan
    ld a, [hl+]
    ld [de], a              ; ptr
    inc de
    ld c, a
    ld a, [hl+]
    ld [de], a
    inc de
    or c                    ; null pointer: channel unused
    push hl
    ld h, d
    ld l, e
    ld [hl], 0              ; ret
    inc hl
    ld [hl], 0
    inc hl
    ld [hl], 1              ; len
    inc hl
    ld [hl], 1              ; remain
    inc hl
    ld [hl], 0              ; instr
    inc hl
    ld [hl], NOTE_REST
    inc hl
    ld [hl], 0              ; arp
    inc hl
    ld [hl], 0
    jr z, .off
    ld [hl], 1
.off
    inc hl
    ld d, h
    ld e, l
    pop hl
    dec b
    jr nz, .chan
    ld a, 1
    ld [wSongOn], a
    ; music uses the wave channel only when the engine is silent
    ld a, [wEngineOn]
    or a
    ret nz
    ld hl, WaveBass
    jp LoadWave

SongHalt:
    xor a
    ld [wSongOn], a
    ldh [rNR12], a
    ldh [rNR22], a
    ldh [rNR42], a
    ld a, [wEngineOn]
    or a
    ret nz
    xor a
    ldh [rNR30], a
    ret

EngineStart:
    ld a, 1
    ld [wEngineOn], a
    ld hl, WaveEngine
    call LoadWave
    ld a, $80
    ldh [rNR30], a
    ld a, $40
    ldh [rNR32], a
    ld a, LOW(700)
    ldh [rNR33], a
    ld a, HIGH(700) | $80
    ldh [rNR34], a
    ret

EngineStop:
    xor a
    ld [wEngineOn], a
    ldh [rNR30], a
    ret

SfxStart:
    dec a
    add a
    ld e, a
    ld d, 0
    ld hl, SfxTable
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [hl+]             ; 1 = pulse, 4 = noise
    cp 4
    jr z, .noise
    ld a, l
    ld [wSfxPtr1], a
    ld a, h
    ld [wSfxPtr1 + 1], a
    ld a, 1
    ld [wSfxTime1], a
    ret
.noise
    ld a, l
    ld [wSfxPtr4], a
    ld a, h
    ld [wSfxPtr4 + 1], a
    ld a, 1
    ld [wSfxTime4], a
    ret

SoundUpdate::
    ; ---- requests
    ld a, [wEngineReq]
    or a
    jr z, .noengreq
    push af
    xor a
    ld [wEngineReq], a
    pop af
    dec a
    push af
    call z, EngineStart
    pop af
    call nz, EngineStop
.noengreq
    ld a, [wSongReqFlag]
    or a
    jr z, .nosongreq
    push af
    xor a
    ld [wSongReqFlag], a
    pop af
    dec a
    jr nz, .halt
    ld hl, wSongReq
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    call SongStart
    jr .nosongreq
.halt
    call SongHalt
.nosongreq
    ld a, [wSfxReq]
    or a
    jr z, .nosfxreq
    push af
    xor a
    ld [wSfxReq], a
    pop af
    call SfxStart
.nosfxreq
    ; ---- pulse effect: (frames, note) pairs, 0 ends
    ld hl, wSfxPtr1
    ld a, [hl+]
    or [hl]
    jr z, .nosfx1
    ld hl, wSfxTime1
    dec [hl]
    jr nz, .nosfx1
    ld hl, wSfxPtr1
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [hl+]
    or a
    jr nz, .step1
    ld [wSfxPtr1], a        ; finished: silence until the music's next note
    ld [wSfxPtr1 + 1], a
    ldh [rNR12], a
    jr .nosfx1
.step1
    ld [wSfxTime1], a
    ld a, [hl+]
    ld e, a
    ld a, l
    ld [wSfxPtr1], a
    ld a, h
    ld [wSfxPtr1 + 1], a
    ld a, $80
    ldh [rNR11], a
    ld a, $F1
    ldh [rNR12], a
    ld a, e
    call NoteFreq
    ld a, e
    ldh [rNR13], a
    ld a, d
    or $80
    ldh [rNR14], a
.nosfx1
    ; ---- noise effect: (frames, envelope, poly) triples, 0 ends
    ld hl, wSfxPtr4
    ld a, [hl+]
    or [hl]
    jr z, .nosfx4
    ld hl, wSfxTime4
    dec [hl]
    jr nz, .nosfx4
    ld hl, wSfxPtr4
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [hl+]
    or a
    jr nz, .step4
    ld [wSfxPtr4], a
    ld [wSfxPtr4 + 1], a
    jr .nosfx4
.step4
    ld [wSfxTime4], a
    ld a, [hl+]
    ldh [rNR42], a
    ld a, [hl+]
    ldh [rNR43], a
    ld a, $80
    ldh [rNR44], a
    ld a, l
    ld [wSfxPtr4], a
    ld a, h
    ld [wSfxPtr4 + 1], a
.nosfx4
    ; ---- engine: pitch follows speed, louder under throttle
    ld a, [wEngineOn]
    or a
    jr z, .noengine
    ld a, [wSpeed]
    ld l, a
    ld a, [wSpeed + 1]
    ld h, a
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l                    ; speed / 8
    ld d, h
    ld e, l
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l                    ; speed / 64
    ld a, e
    sub l
    ld e, a
    ld a, d
    sbc h
    ld d, a
    ld hl, 760
    add hl, de
    ; a little wobble so the drone is not perfectly static
    ldh a, [hFrame]
    and 3
    add l
    ldh [rNR33], a
    ld a, h
    adc 0
    ldh [rNR34], a
    ld a, [wEngineGas]
    or a
    ld a, $40               ; 50%
    jr nz, .vol
    ld a, $60               ; 25% when coasting
.vol
    ldh [rNR32], a
.noengine
    ; ---- music
    ld a, [wSongOn]
    or a
    ret z
    ld hl, wTick
    dec [hl]
    jr nz, .arps
    ld a, [wTempo]
    ld [hl], a
    xor a
.chans
    ld [wCurChan], a
    call ChanTick
    ld a, [wCurChan]
    inc a
    cp 4
    jr nz, .chans
.arps
    ; arpeggios: rotate through chord offsets every other frame
    ld hl, wArpPhase
    inc [hl]
    ld a, [hl]
    cp 6
    jr c, .phaseok
    xor a
    ld [hl], a
.phaseok
    rrca
    ret c                   ; odd frames: nothing to do
    xor a
    call ArpChan
    ld a, 1
    ; fall through

; a = pulse channel (0/1): re-pitch it if it is playing an arpeggio
ArpChan:
    ld [wCurChan], a
    call ChanPtr
    ld de, CH_NOTE
    add hl, de
    ld a, [hl+]
    cp NOTE_REST
    ret z
    ld b, a
    ld a, [hl]              ; arp type
    or a
    ret z
    dec a
    ld e, a
    add a
    add e                   ; * 3
    ld e, a
    ld a, [wArpPhase]
    srl a
    add e
    ld e, a
    ld d, 0
    ld hl, ArpTable
    add hl, de
    ld a, [hl]
    add b
    call NoteFreq
    ld a, [wCurChan]
    or a
    jr nz, .ch2
    ld a, [wSfxPtr1]
    ld hl, wSfxPtr1 + 1
    or [hl]
    ret nz
    ld a, e
    ldh [rNR13], a
    ld a, d
    ldh [rNR14], a
    ret
.ch2
    ld a, e
    ldh [rNR23], a
    ld a, d
    ldh [rNR24], a
    ret

; -> hl = channel struct of wCurChan
ChanPtr:
    ld a, [wCurChan]
    ld l, a
    add a
    add a
    add l
    add a                   ; * 10
    add LOW(wChan)
    ld l, a
    ld h, HIGH(wChan)
    ret

; a = note -> de = frequency register value
NoteFreq:
    add a
    ld e, a
    ld d, 0
    ld hl, FreqTable
    add hl, de
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    ret

; advance one channel by a tick
ChanTick:
    call ChanPtr
    push hl
    ld de, CH_ON
    add hl, de
    ld a, [hl]
    pop hl
    or a
    ret z
    push hl
    ld de, CH_REMAIN
    add hl, de
    dec [hl]
    pop hl
    ret nz
    ; fetch events until a note or rest
    ld a, [hl+]
    ld e, a
    ld a, [hl-]
    ld d, a                 ; de = stream pointer, hl = struct
.fetch
    ld a, [de]
    inc de
    cp NOTE_REST + 1
    jr c, .note
    cp $C0
    jr c, .length
    cp $D0
    jr c, .instr
    cp $D8
    jr c, .arp
    cp $F0
    jr z, .jump
    cp $F2
    jr z, .call
    cp $F3
    jr z, .return
    ; $F1 or anything else: stop
    push hl
    ld bc, CH_ON
    add hl, bc
    ld [hl], 0
    pop hl
    ld a, NOTE_REST
    jr .note
.length
    and $3F
    inc a
    push hl
    ld bc, CH_LEN
    add hl, bc
    ld [hl], a
    pop hl
    jr .fetch
.instr
    and $0F
    push hl
    ld bc, CH_INSTR
    add hl, bc
    ld [hl], a
    pop hl
    jr .fetch
.arp
    and 7
    push hl
    ld bc, CH_ARP
    add hl, bc
    ld [hl], a
    pop hl
    jr .fetch
.jump
    ld a, [de]
    ld c, a
    inc de
    ld a, [de]
    ld d, a
    ld e, c
    jr .fetch
.call
    ld a, [de]
    ld c, a
    inc de
    ld a, [de]
    ld b, a
    inc de
    push hl
    inc hl
    inc hl
    ld a, e
    ld [hl+], a
    ld [hl], d
    pop hl
    ld d, b
    ld e, c
    jr .fetch
.return
    push hl
    inc hl
    inc hl
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    pop hl
    jr .fetch
.note
    ; store the stream position, note and reload the duration
    ld b, a
    ld a, e
    ld [hl+], a
    ld a, d
    ld [hl+], a
    inc hl
    inc hl
    ld a, [hl+]             ; length
    ld [hl+], a             ; remain
    ld a, [hl+]             ; instrument
    ld c, a
    ld [hl], b              ; note
    ; ---- key on, per channel type
    ld a, [wCurChan]
    cp 2
    jr z, .wave
    cp 3
    jr z, .drum
    or a
    jr nz, .pulse2
    ; pulse 1 (yields to sound effects)
    ld a, [wSfxPtr1]
    ld hl, wSfxPtr1 + 1
    or [hl]
    ret nz
    ld a, b
    cp NOTE_REST
    jr nz, .p1on
    xor a
    ldh [rNR12], a
    ret
.p1on
    call InstrPtr
    ld a, [hl+]
    ldh [rNR11], a
    ld a, [hl]
    ldh [rNR12], a
    ld a, b
    call NoteFreq
    ld a, e
    ldh [rNR13], a
    ld a, d
    or $80
    ldh [rNR14], a
    ret
.pulse2
    ld a, b
    cp NOTE_REST
    jr nz, .p2on
    xor a
    ldh [rNR22], a
    ret
.p2on
    call InstrPtr
    ld a, [hl+]
    ldh [rNR21], a
    ld a, [hl]
    ldh [rNR22], a
    ld a, b
    call NoteFreq
    ld a, e
    ldh [rNR23], a
    ld a, d
    or $80
    ldh [rNR24], a
    ret
.wave
    ld a, [wEngineOn]
    or a
    ret nz
    ld a, b
    cp NOTE_REST
    jr nz, .won
    xor a
    ldh [rNR32], a
    ret
.won
    ld a, $80
    ldh [rNR30], a
    ld a, $20
    ldh [rNR32], a
    ld a, b
    call NoteFreq
    ld a, e
    ldh [rNR33], a
    ld a, d
    or $80
    ldh [rNR34], a
    ret
.drum
    ld a, b
    cp NOTE_REST
    ret z
    ld a, [wSfxPtr4]
    ld hl, wSfxPtr4 + 1
    or [hl]
    ret nz
    ld a, b
    add a
    ld e, a
    ld d, 0
    ld hl, DrumTable
    add hl, de
    ld a, [hl+]
    ldh [rNR42], a
    ld a, [hl]
    ldh [rNR43], a
    ld a, $80
    ldh [rNR44], a
    ret

; c = instrument -> hl = (duty, envelope)
InstrPtr:
    ld a, c
    add a
    ld e, a
    ld d, 0
    ld hl, InstrTable
    add hl, de
    ret

; ---------------------------------------------------------------- data
InstrTable:
    db $80, $C2     ; 0 lead: 50% duty, quick decay
    db $40, $A3     ; 1 soft: 25% duty
    db $80, $93     ; 2 bass: 50%, medium
    db $00, $82     ; 3 thin: 12.5% (arpeggios)
    db $80, $F1     ; 4 stab: loud and short
    db $40, $C5     ; 5 long lead
    db $C0, $A4     ; 6 hollow: 75%
    db $80, $74     ; 7 pad: quiet 50%

ArpTable:
    db 0, 4, 7      ; 1 major
    db 0, 3, 7      ; 2 minor
    db 0, 12, 0     ; 3 octave
    db 0, 5, 7      ; 4 sus4
    db 0, 4, 9      ; 5 sixth
    db 0, 3, 8      ; 6 minor sixth / first inversion
    db 0, 7, 12     ; 7 power

DrumTable:
    db $F1, $55     ; 0 kick
    db $C1, $34     ; 1 snare
    db $61, $11     ; 2 closed hat
    db $82, $22     ; 3 open hat
    db $D2, $46     ; 4 tom

WaveBass:
    db $02, $46, $8A, $CE, $FF, $FE, $DC, $BA, $98, $76, $54, $32, $10, $00, $01, $12
WaveEngine:
    db $FF, $C8, $F4, $0B, $D5, $39, $E2, $06, $AC, $51, $F0, $28, $B3, $07, $94, $10

SfxTable:
    dw SfxBeep, SfxGo, SfxCheck, SfxCrash, SfxSkid, SfxSelect
; pulse effects: type 1, then (frames, note)..., 0
SfxBeep:    db 1, 7, 45, 0
SfxGo:      db 1, 26, 57, 0
SfxCheck:   db 1, 5, 52, 5, 55, 5, 60, 10, 64, 0
SfxSelect:  db 1, 4, 48, 6, 55, 0
; noise effects: type 4, then (frames, envelope, poly)..., 0
SfxCrash:   db 4, 6, $F2, $5D, 8, $D2, $6C, 14, $A3, $7A, 0
SfxSkid:    db 4, 5, $72, $33, 0

INCLUDE "music.asm"
