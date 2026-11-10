; ORBIT LANCE game logic: title, stages, player, enemies, shots, collisions, HUD.

SECTION "GameVars", WRAM0
wHud::          ds 20
wState::        db
wStage::        db              ; 0..2
wLoop::         db              ; times the three stages have been cleared
wScript::       dw              ; next stage event
wScriptWait::   db
wScriptHold::   db              ; waiting for the screen to clear
wScriptDone::   db
wPXS::          db              ; player position, 8.8 OAM coordinates
wPX::           db
wPYS::          db
wPY::           db
wPInv::         db              ; invulnerability frames
wPDead::        db              ; frames until respawn (0 = alive)
wFireCool::     db
wPower::        db              ; 0 single, 1 double, 2 triple
wLives::        db
wBombs::        db
wFlash::        db
wScore::        ds 3            ; points / 10, BCD, little-endian
wHiScore::      ds 3
wBanner::       dw
wBannerT::      db
wStateT::       db
wRot::          db
wClearT::       db
wRand::         db
wOamEnd::       db
wBossBoomT::    db
wBossX::        db
wBossY::        db
wShotSpeed::    db              ; aimed shot speed, 1/16 px per frame
wDartsFire::    db
wScT::          dw
wScN::          db
wScM::          dw

SECTION "GameHRAM", HRAM
hPCX::          db              ; player centre (OAM coordinates)
hPCY::          db
hTmp2::         ds 4
hCount2::       db
hCount3::       db
hSign::         db
hM::            db

SECTION "Game", ROM0

; ================================================================ main loop
MainLoop:
    call WaitVBlank
    call ReadJoypad
    ld a, [wState]
    or a
    jr nz, .nottitle
    call TitleFrame
    jr MainLoop
.nottitle
    dec a
    jr nz, .over
    call PlayFrame
    jr MainLoop
.over
    call OverFrame
    jr MainLoop

; ================================================================ title
TitleInit::
    ld sp, $E000
    call LcdOff
    xor a
    ldh [rSTAT], a
    ld a, IE_VBLANK
    ldh [rIE], a
    ld a, ST_TITLE
    ld [wState], a
    xor a
    ld [wStage], a          ; SELECT on the title picks the starting stage
    ld a, 3
    call LoadScene
    call ClearObjects
    call ClearOAMBuf
    xor a
    ldh [hSCY], a
    ldh [hPendSCY], a
    ld [wStateT], a
    ld [wBannerT], a
    ld hl, wLineX
    ld bc, 256
    xor a
    call MemFill
    ld hl, TxtPress
    call SetHud
    ld hl, SongTitle
    call SongPlay
    ld a, %11100100
    ldh [hBGP], a
    ld a, 1
    ldh [hHudOn], a
    ldh [hFrameReady], a
    ld a, LCDC_PLAY
    call LcdOn
    ; the ripple runs from the HBlank interrupt
    ld a, STAT_MODE0
    ldh [rSTAT], a
    xor a
    ldh [rIF], a
    ld a, IE_VBLANK | IE_STAT
    ldh [rIE], a
    jp MainLoop

TitleFrame:
    ; logo ripple: each scanline of the logo gets its own horizontal offset
    ldh a, [hFrame]
    add a
    ld c, a
    ld hl, wLineX
    ld b, 0
.line
    ld a, b
    cp 10
    jr c, .zero
    cp 82
    jr nc, .zero
    add a
    add a
    add a
    add c
    ld e, a
    ld d, HIGH(SinTab)
    ld a, [de]
    sra a
    sra a
    sra a
    jr .put
.zero
    xor a
.put
    ld [hl+], a
    inc b
    ld a, b
    cp 145
    jr nz, .line
    ; SELECT: choose the starting stage
    ldh a, [hKeysNew]
    bit KEYB_SELECT, a
    jr z, .noselect
    ld a, [wStage]
    inc a
    cp 3
    jr c, .stageok
    xor a
.stageok
    ld [wStage], a
    ld a, SFX_SELECT
    call SfxPlay
    ld hl, TxtFrom
    call SetHud
    ld a, [wStage]
    inc a
    ld [wHud + 15], a
    ldh a, [hFrame]
    and $C0
    inc a
    ldh [hFrame], a         ; keep this text up for a full cycle
.noselect
    ; alternate between PRESS START and the high score
    ldh a, [hFrame]
    and 63
    jr nz, .keys
    ldh a, [hFrame]
    bit 6, a
    jr nz, .hi
    ld hl, TxtPress
    call SetHud
    jr .keys
.hi
    call HudHi
.keys
    ld a, 1
    ldh [hFrameReady], a
    ldh a, [hKeysNew]
    and KEY_START | KEY_A
    ret z
    ld a, SFX_SELECT
    call SfxPlay
    ; fall through

; ================================================================ stages
GameStart:
    xor a
    ld [wLoop], a
    ld [wPower], a
    ld hl, wScore
    ld [hl+], a
    ld [hl+], a
    ld [hl], a
    ld a, 3
    ld [wLives], a
    ld a, 2
    ld [wBombs], a
    ; fall through

StageInit:
    ld sp, $E000
    call LcdOff
    xor a
    ldh [rSTAT], a
    ld a, IE_VBLANK
    ldh [rIE], a
    ld hl, wLineX
    ld bc, 256
    xor a
    call MemFill
    ld a, ST_PLAY
    ld [wState], a
    ld a, [wStage]
    call LoadScene
    call ClearObjects
    call ClearOAMBuf
    call PlayerSpawn
    ld a, 60
    ld [wPInv], a
    ; stage script
    ld a, [wStage]
    ld hl, StageTable
    call TableWord
    ld a, l
    ld [wScript], a
    ld a, h
    ld [wScript + 1], a
    ld a, [hl]
    ld [wScriptWait], a
    xor a
    ld [wScriptHold], a
    ld [wScriptDone], a
    ld [wClearT], a
    ld [wBossBoomT], a
    ld [wFlash], a
    ; difficulty: faster aimed shots on every loop; darts shoot from stage 2
    ld a, [wLoop]
    ld b, a
    add a
    add b
    add a
    add 24
    cp 48
    jr c, .speed
    ld a, 48
.speed
    ld [wShotSpeed], a
    ld a, [wStage]
    ld b, a
    ld a, [wLoop]
    or b
    ld [wDartsFire], a
    ; banner and music
    ld a, [wStage]
    ld hl, StageBanners
    call TableWord
    ld a, 150
    call ShowBanner
    ld a, [wStage]
    ld hl, StageSongs
    call TableWord
    call SongPlay
    xor a
    ldh [hSCY], a
    ldh [hPendSCY], a
    ld a, %11100100
    ldh [hBGP], a
    call UpdateHud
    call BuildOAM
    ld a, 1
    ldh [hHudOn], a
    ldh [hFrameReady], a
    ld a, LCDC_PLAY
    call LcdOn
    jp MainLoop

; a = index, hl = table of words -> hl = entry
TableWord:
    add a
    add l
    ld l, a
    adc h
    sub l
    ld h, a
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ret

PlayFrame:
    call UpdatePlayer
    call UpdatePShots
    call RunScript
    call UpdateEnemies
    call UpdateEShots
    call Collide
    call BossBooms
    ld hl, wBannerT
    ld a, [hl]
    or a
    jr z, .nobanner
    dec [hl]
.nobanner
    ; stage clear: count down, then on to the next stage
    ld a, [wClearT]
    or a
    jr z, .noclear
    dec a
    ld [wClearT], a
    jr nz, .noclear
    ld a, [wBombs]
    cp 3
    jr nc, .bombsfull
    inc a
    ld [wBombs], a
.bombsfull
    ld a, [wStage]
    inc a
    cp 3
    jr c, .nextstage
    ld hl, wLoop
    inc [hl]
    xor a
.nextstage
    ld [wStage], a
    jp StageInit
.noclear
    ; bomb flash
    ld b, %11100100
    ld a, [wFlash]
    or a
    jr z, .pal
    dec a
    ld [wFlash], a
    bit 1, a
    jr z, .pal
    ld b, %00011011
.pal
    ld a, b
    ldh [hBGP], a
    ldh a, [hPendSCY]
    dec a
    ldh [hPendSCY], a
    call BuildOAM
    call UpdateHud
    ld a, 1
    ldh [hFrameReady], a
    ret

GameOverInit:
    ld a, ST_OVER
    ld [wState], a
    ld a, 255
    ld [wPDead], a          ; keeps the ship hidden
    ld hl, TxtOver
    call ShowBanner
    ld hl, SongOver
    call SongPlay
    xor a
    ld [wStateT], a
    ; new high score?
    ld a, [wScore + 2]
    ld b, a
    ld a, [wHiScore + 2]
    cp b
    jr c, .new
    ret nz
    ld a, [wScore + 1]
    ld b, a
    ld a, [wHiScore + 1]
    cp b
    jr c, .new
    ret nz
    ld a, [wScore]
    ld b, a
    ld a, [wHiScore]
    cp b
    ret nc
.new
    ld a, [wScore]
    ld [wHiScore], a
    ld a, [wScore + 1]
    ld [wHiScore + 1], a
    ld a, [wScore + 2]
    ld [wHiScore + 2], a
    ret

OverFrame:
    call UpdatePShots
    call UpdateEnemies
    call UpdateEShots
    call BossBooms
    ldh a, [hPendSCY]
    dec a
    ldh [hPendSCY], a
    call BuildOAM
    call UpdateHud
    ld a, 1
    ldh [hFrameReady], a
    ld hl, wStateT
    inc [hl]
    ld a, [hl]
    cp 255
    jp z, TitleInit
    cp 90
    ret c
    ldh a, [hKeysNew]
    and KEY_START | KEY_A
    ret z
    jp TitleInit

; hl -> banner text, a = frames to show it
ShowBanner:
    ld [wBannerT], a
    ld a, l
    ld [wBanner], a
    ld a, h
    ld [wBanner + 1], a
    ret

; ================================================================ stage script
RunScript:
    ld a, [wScriptDone]
    or a
    ret nz
    ld a, [wScriptHold]
    or a
    jr z, .timer
    call CountHostiles
    or a
    ret nz
    xor a
    ld [wScriptHold], a
.timer
    ld hl, wScriptWait
    ld a, [hl]
    or a
    jr z, .run
    dec [hl]
    ret nz
.run
    ld hl, wScript
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    inc hl                  ; wait byte
    ld a, [hl+]
    ld b, a                 ; command
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    ld d, a
    ld a, [hl+]
    ld e, a
    push hl
    ld a, b
    call DoEvent
    pop hl
    ld a, l
    ld [wScript], a
    ld a, h
    ld [wScript + 1], a
    ld a, [wScriptDone]
    or a
    ret nz
    ld a, [hl]
    ld [wScriptWait], a
    ld a, [wScriptHold]
    or a
    ret nz
    ld a, [hl]
    or a
    jr z, .run
    ret

; a = command, c/d/e = arguments
DoEvent:
    or a
    ret z
    cp T_POWER + 1
    jr nc, .special
    ld b, a
    jp SpawnEnemy
.special
    cp $F0
    jp z, SpawnBoss
    cp $F1
    jr z, .warning
    cp $F2
    jr z, .hold
    ; end of the stage
    ld a, 1
    ld [wScriptDone], a
    ld a, 210
    ld [wClearT], a
    ld hl, TxtClear
    ld a, 200
    call ShowBanner
    ld hl, SongClear
    jp SongPlay
.hold
    ld a, 1
    ld [wScriptHold], a
    ret
.warning
    ld hl, TxtWarning
    ld a, 150
    call ShowBanner
    ld a, SFX_ALARM
    call SfxPlay
    ld hl, SongBoss
    jp SongPlay

CountHostiles:
    ld hl, wEnemies
    ld bc, (MAX_EN << 8)
.loop
    ld a, [hl]
    or a
    jr z, .next
    cp T_BOOM
    jr nc, .next
    inc c
.next
    ld a, l
    add OBJ_SIZE
    ld l, a
    dec b
    jr nz, .loop
    ld a, c
    ret

; ================================================================ player
PlayerSpawn:
    ld a, 80
    ld [wPX], a
    ld a, 126
    ld [wPY], a
    xor a
    ld [wPXS], a
    ld [wPYS], a
    ld [wPDead], a
    ld [wFireCool], a
    ld a, 120
    ld [wPInv], a
    ret

UpdatePlayer:
    ld a, [wPDead]
    or a
    jr z, .alive
    dec a
    ld [wPDead], a
    ret nz
    ld a, [wLives]
    or a
    jp z, GameOverInit
    jp PlayerSpawn
.alive
    ld a, [wPInv]
    or a
    jr z, .noinv
    dec a
    ld [wPInv], a
.noinv
    ldh a, [hKeys]
    ld b, a
    ; ---- move 1.5 px per frame inside the playfield
    ld hl, wPXS
    bit KEYB_RIGHT, b
    jr z, .noright
    ld a, [hl]
    add $80
    ld [hl+], a
    ld a, [hl]
    adc 1
    cp 153
    jr c, .r
    ld a, 152
.r
    ld [hl-], a
.noright
    bit KEYB_LEFT, b
    jr z, .noleft
    ld a, [hl]
    sub $80
    ld [hl+], a
    ld a, [hl]
    sbc 1
    cp 8
    jr nc, .l
    ld a, 8
.l
    ld [hl-], a
.noleft
    ld hl, wPYS
    bit KEYB_DOWN, b
    jr z, .nodown
    ld a, [hl]
    add $80
    ld [hl+], a
    ld a, [hl]
    adc 1
    cp 137
    jr c, .d
    ld a, 136
.d
    ld [hl-], a
.nodown
    bit KEYB_UP, b
    jr z, .noup
    ld a, [hl]
    sub $80
    ld [hl+], a
    ld a, [hl]
    sbc 1
    cp 16
    jr nc, .u
    ld a, 16
.u
    ld [hl-], a
.noup
    ; ---- fire (hold A for continuous fire)
    ld hl, wFireCool
    ld a, [hl]
    or a
    jr z, .ready
    dec [hl]
    jr .nofire
.ready
    bit KEYB_A, b
    jr z, .nofire
    ld [hl], 7
    ld a, [wPY]
    sub 8
    ld c, a
    ld a, [wPower]
    or a
    jr nz, .p1
    ld a, [wPX]
    add 4
    ld d, a
    ld e, 0
    call AddPShot
    jr .fired
.p1
    dec a
    jr nz, .p2
    ld a, [wPX]
    ld d, a
    ld e, 0
    call AddPShot
    ld a, [wPX]
    add 8
    ld d, a
    ld e, 0
    call AddPShot
    jr .fired
.p2
    ld a, [wPX]
    add 4
    ld d, a
    ld e, 0
    call AddPShot
    ld a, [wPX]
    ld d, a
    ld e, -1
    call AddPShot
    ld a, [wPX]
    add 8
    ld d, a
    ld e, 1
    call AddPShot
.fired
    ld a, SFX_SHOT
    call SfxPlay
.nofire
    ; ---- bomb: clears enemy shots and damages everything on screen
    ldh a, [hKeysNew]
    bit KEYB_B, a
    ret z
    ld a, [wBombs]
    or a
    ret z
    dec a
    ld [wBombs], a
    ld a, 24
    ld [wFlash], a
    ld a, [wPInv]
    cp 60
    jr nc, .inv
    ld a, 60
    ld [wPInv], a
.inv
    ld hl, wEShots
    ld b, MAX_ESHOT
.clr
    ld [hl], 0
    ld a, l
    add OBJ_SIZE
    ld l, a
    dec b
    jr nz, .clr
    ld hl, wEnemies
    ld b, MAX_EN
.dmg
    ld a, [hl]
    or a
    jr z, .dnext
    cp T_BOOM
    jr nc, .dnext
    push hl
    ld a, l
    add O_Y
    ld l, a
    ld a, [hl]
    pop hl
    cp 16
    jr c, .dnext            ; not on screen yet
    push bc
    push hl
    ld a, 10
    call HitEnemy
    pop hl
    pop bc
.dnext
    ld a, l
    add OBJ_SIZE
    ld l, a
    dec b
    jr nz, .dmg
    ld a, SFX_BOMB
    jp SfxPlay

; d = x, c = y, e = sideways speed (px per frame)
AddPShot:
    ld hl, wPShots
    ld b, MAX_PSHOT
.find
    ld a, [hl]
    or a
    jr z, .got
    inc l
    inc l
    inc l
    inc l
    dec b
    jr nz, .find
    ret
.got
    ld a, c
    ld [hl+], a
    ld a, d
    ld [hl+], a
    ld a, e
    ld [hl], a
    ret

UpdatePShots:
    ld hl, wPShots
    ld b, MAX_PSHOT
.loop
    ld a, [hl]
    or a
    jr z, .next
    sub 5
    jr c, .kill
    cp 8
    jr c, .kill
    ld [hl+], a
    ld a, [hl+]             ; x
    ld c, a
    ld a, [hl]              ; sideways speed
    add c
    dec hl
    ld [hl-], a
    cp 168
    jr c, .next
.kill
    ld [hl], 0
.next
    ld a, l
    and $FC
    add 4
    ld l, a
    dec b
    jr nz, .loop
    ret

PlayerHit:
    ld a, [wPInv]
    or a
    ret nz
    ld a, [wPDead]
    or a
    ret nz
    ld a, [wPX]
    ld b, a
    ld a, [wPY]
    ld c, a
    call SpawnBoom
    ld a, 100
    ld [wPDead], a
    ld hl, wLives
    dec [hl]
    ld a, [wPower]
    or a
    jr z, .p
    dec a
    ld [wPower], a
.p
    ld a, 2
    ld [wBombs], a
    ld a, SFX_BIGBOOM
    jp SfxPlay

; ================================================================ enemies
; a = type -> bc = its row in TypeTab
TypeInfo:
    add a
    add a
    add a
    ld c, a
    ld b, HIGH(TypeTab)
    ret

; -> hl = a free, cleared enemy slot (carry set if none)
FindEnemySlot:
    ld hl, wEnemies
    ld b, MAX_EN
.find
    ld a, [hl]
    or a
    jr z, .got
    ld a, l
    add OBJ_SIZE
    ld l, a
    dec b
    jr nz, .find
    scf
    ret
.got
    push hl
    xor a
    ld b, OBJ_SIZE
.clear
    ld [hl+], a
    dec b
    jr nz, .clear
    pop hl
    ret

; b = type, c = x, d = pattern, e = parameter
SpawnEnemy:
    ld a, b
    ldh [hTmp], a
    ld a, c
    ldh [hTmp + 1], a
    ld a, d
    ldh [hTmp + 2], a
    ld a, e
    ldh [hTmp + 3], a
    ld a, b
    cp T_POWER
    jr nz, .notpower
    ld a, P_WEAVE
    ldh [hTmp + 2], a
    ld a, 10
    ldh [hTmp + 3], a
.notpower
    call FindEnemySlot
    ret c
    ld d, h
    ld e, l
    ldh a, [hTmp]
    ld [de], a
    ld a, e
    add O_X
    ld l, a
    ldh a, [hTmp + 1]
    ld [hl], a
    ld a, e
    add O_X0
    ld l, a
    ldh a, [hTmp + 1]
    ld [hl+], a
    ldh a, [hTmp + 3]
    ld [hl], a              ; O_ARG
    ld a, e
    add O_PAT
    ld l, a
    ldh a, [hTmp + 2]
    ld [hl], a
    ldh a, [hTmp]
    call TypeInfo
    ld a, [bc]
    ld l, e
    ld a, e
    add O_HP
    ld l, a
    ld a, [bc]
    ld [hl], a
    ld a, c
    add 7
    ld c, a
    ld a, e
    add O_FIRE
    ld l, a
    ld a, [bc]
    ld [hl], a
    ; starting velocity for the pattern
    ldh a, [hTmp + 2]
    cp P_DIVE
    jr z, .dive
    cp P_SWEEPL
    jr z, .sweepl
    cp P_SWEEPR
    jr z, .sweepr
    cp P_HOVER
    jr z, .hover
    cp P_BOSS
    jr z, .boss
    ; straight and weave: parameter = speed down, 1/16 px
    ldh a, [hTmp + 3]
    call V16
    jr .setvy
.dive
    ld bc, $0180
    jr .setvy
.hover
    ld bc, $0100
    jr .setvy
.boss
    ld bc, $0080
    jr .setvy
.sweepl
    ld bc, $0180
    jr .sweep
.sweepr
    ld bc, -$0180
.sweep
    ld a, e
    add O_VXL
    ld l, a
    ld [hl], c
    inc l
    ld [hl], b
    ld a, e
    add O_Y
    ld l, a
    ldh a, [hTmp + 3]
    ld [hl], a              ; sweeps enter at the given height
    ld bc, $0030
.setvy
    ld a, e
    add O_VYL
    ld l, a
    ld [hl], c
    inc l
    ld [hl], b
    ret

SpawnBoss:
    ld b, T_BOSS
    ld c, 64
    ld d, P_BOSS
    ld e, 0
    jp SpawnEnemy

; b = x, c = y
SpawnBoom:
    ld a, b
    ldh [hTmp2 + 2], a
    ld a, c
    ldh [hTmp2 + 3], a
    call FindEnemySlot
    ret c
    ld [hl], T_BOOM
    ld d, h
    ld e, l
    ld a, e
    add O_X
    ld l, a
    ldh a, [hTmp2 + 2]
    ld [hl], a
    ld a, e
    add O_Y
    ld l, a
    ldh a, [hTmp2 + 3]
    ld [hl], a
    ld a, e
    add O_VYL
    ld l, a
    ld [hl], $60            ; drifts down with the scenery
    ld a, SFX_BOOM
    jp SfxPlay

; hl -> object + O_XS: add the velocity to the position. Returns a = new Y.
MoveObj:
    ld b, h
    ld a, l
    add 4
    ld c, a                 ; bc -> velocity
    ld a, [bc]
    add [hl]
    ld [hl+], a
    inc c
    ld a, [bc]
    adc [hl]
    ld [hl+], a
    inc c
    ld a, [bc]
    add [hl]
    ld [hl+], a
    inc c
    ld a, [bc]
    adc [hl]
    ld [hl], a
    ret

UpdateEnemies:
    ld hl, wEnemies
    ld a, MAX_EN
    ldh [hCount], a
.loop
    ld a, [hl]
    or a
    call nz, EnemyTick
    ld a, l
    add OBJ_SIZE
    ld l, a
    ldh a, [hCount]
    dec a
    ldh [hCount], a
    jr nz, .loop
    ret

; hl = enemy slot (preserved)
EnemyTick:
    push hl
    ld d, h
    ld e, l
    ld a, e
    add O_T
    ld l, a
    ld a, [hl]
    inc a
    jr z, .agesat
    ld [hl], a
.agesat
    ld a, e
    add O_FLASH
    ld l, a
    ld a, [hl]
    or a
    jr z, .noflash
    dec [hl]
.noflash
    ld a, [de]
    cp T_BOOM
    jr nz, .notboom
    ld a, e
    add O_T
    ld l, a
    ld a, [hl]
    cp 18
    jp c, .move
    xor a
    ld [de], a
    jp .done
.notboom
    ld a, e
    add O_PAT
    ld l, a
    ld a, [hl]
    cp P_WEAVE
    jr z, .weave
    cp P_DIVE
    jr z, .dive
    cp P_HOVER
    jp z, .hover
    cp P_BOSS
    jp z, .boss
    jp .move

.weave
    ; x = start x + sine(age)
    ld a, e
    add O_T
    ld l, a
    ld a, [hl]
    ld b, a
    add a
    add b
    ld c, a
    ld b, HIGH(SinTab)
    ld a, [bc]
    sra a
    ld b, a
    ld a, e
    add O_X0
    ld l, a
    ld a, [hl]
    add b
    ld b, a
    ld a, e
    add O_X
    ld l, a
    ld [hl], b
    jp .move

.dive
    ; after a short descent, swoop toward the player
    ld a, e
    add O_T
    ld l, a
    ld a, [hl]
    cp 40
    jp nz, .move
    ld a, e
    add O_X
    ld l, a
    ld a, [wPX]
    cp [hl]
    ld bc, $0140
    jr nc, .diveright
    ld bc, -$0140
.diveright
    ld a, e
    add O_VXL
    ld l, a
    ld [hl], c
    inc l
    ld [hl], b
    inc l
    ld [hl], $80
    inc l
    ld [hl], $02
    jp .move

.hover
    ld a, e
    add O_T
    ld l, a
    ld a, [hl]
    cp 240
    jr nz, .stay
    ; time to leave
    ld a, e
    add O_VXL
    ld l, a
    xor a
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl], 1
    jp .move
.stay
    jp nc, .move            ; already leaving
    ld a, e
    add O_VYL
    ld l, a
    ld a, [hl+]
    or [hl]
    jr z, .strafe
    ld a, e
    add O_ARG
    ld l, a
    ld b, [hl]
    ld a, e
    add O_Y
    ld l, a
    ld a, [hl]
    cp b
    jp c, .move
    ld a, e
    add O_VYL
    ld l, a
    xor a
    ld [hl+], a
    ld [hl], a
    ld a, e
    add O_VXL
    ld l, a
    ld [hl], $80
    inc l
    ld [hl], 0
    jp .move
.strafe
    ld a, e
    add O_X
    ld l, a
    ld a, [hl]
    cp 24
    jr nc, .notleft
    ld a, e
    add O_VXL
    ld l, a
    ld [hl], $80
    inc l
    ld [hl], 0
    jp .move
.notleft
    cp 137
    jp c, .move
    ld a, e
    add O_VXL
    ld l, a
    ld [hl], $80
    inc l
    ld [hl], $FF
    jp .move

.boss
    ld a, e
    add O_Y
    ld l, a
    ld a, [hl]
    cp 40
    jr c, .move             ; still descending
    ld a, e
    add O_VYL
    ld l, a
    xor a
    ld [hl+], a
    ld [hl], a
    ; sway from side to side
    ldh a, [hFrame]
    ld c, a
    ld b, HIGH(SinTab)
    ld a, [bc]
    ld b, a
    ld a, e
    add O_X0
    ld l, a
    ld a, [hl]
    add b
    ld b, a
    ld a, e
    add O_X
    ld l, a
    ld [hl], b

.move
    ld a, e
    inc a
    ld l, a
    call MoveObj
    ld a, e
    add O_Y
    ld l, a
    ld a, [hl]
    cp 168
    jr nc, .free
    ld a, e
    add O_X
    ld l, a
    ld a, [hl]
    cp 180
    jr nc, .free
    call EnemyFire
    jr .done
.free
    xor a
    ld [de], a
.done
    pop hl
    ret

; de = enemy slot
EnemyFire:
    ld h, d
    ld a, [de]
    cp T_POWER
    ret nc
    ld a, e
    add O_Y
    ld l, a
    ld a, [hl]
    cp 24
    ret c
    cp 120
    ret nc
    ld a, e
    add O_FIRE
    ld l, a
    ld a, [hl]
    or a
    ret z                   ; 0 = does not shoot (any more)
    dec [hl]
    ret nz
    ld a, [de]
    cp T_DART
    jr nz, .reload
    ld a, [wDartsFire]      ; darts fire a single shot, from stage 2 on
    or a
    ret z
    jp FireAimed
.reload
    push af
    call TypeInfo
    ld a, c
    add 6
    ld c, a
    ld a, [bc]
    ld b, a
    ld h, d
    ld a, e
    add O_FIRE
    ld l, a
    ld [hl], b
    pop af
    cp T_SAUCER
    jp z, FireAimed
    cp T_HEAVY
    jp z, FireSpread3
    ; boss: alternate aimed shots and a fan, faster when damaged
    ld a, e
    add O_HP
    ld l, a
    ld a, [hl]
    cp 70
    jr nc, .calm
    ld a, e
    add O_FIRE
    ld l, a
    ld [hl], 30
.calm
    ld a, e
    add O_ARG
    ld l, a
    inc [hl]
    bit 0, [hl]
    jp z, FireSpread5
    jp FireAimed

; de = enemy -> b, c = top-left of a shot fired from its centre
ShotOrigin:
    ld a, [de]
    call TypeInfo
    ld a, c
    add 3
    ld c, a
    ld a, [bc]
    sub 4
    ldh [hM], a
    ld h, d
    ld a, e
    add O_X
    ld l, a
    ldh a, [hM]
    add [hl]
    ld b, a
    ld a, e
    add O_Y
    ld l, a
    ldh a, [hM]
    add [hl]
    ld c, a
    ret

; de = enemy: one shot at the player
FireAimed:
    call ShotOrigin
    ld a, b
    ldh [hTmp], a
    ld a, c
    ldh [hTmp + 1], a
    ld a, [wPDead]
    or a
    jr nz, .down
    ; half the distance to the player's centre, as signed bytes
    ld a, [wPX]
    add 4
    sub b
    rra
    ldh [hTmp + 2], a
    ld a, [wPY]
    add 4
    sub c
    rra
    ldh [hTmp + 3], a
    ; speed is normalised by the larger of |dx| and |dy|
    ldh a, [hTmp + 2]
    call Abs
    ld b, a
    ldh a, [hTmp + 3]
    call Abs
    cp b
    jr nc, .max
    ld a, b
.max
    or a
    jr z, .down
    ldh [hM], a
    ldh a, [hTmp + 2]
    call Scale
    ldh [hTmp + 2], a
    ldh a, [hTmp + 3]
    call Scale
    ld e, a
    ldh a, [hTmp + 2]
    ld d, a
    jr .spawn
.down
    ld d, 0
    ld a, [wShotSpeed]
    ld e, a
.spawn
    ldh a, [hTmp]
    ld b, a
    ldh a, [hTmp + 1]
    ld c, a
    jp SpawnEShot

; a = signed value -> a = value * shot speed / [hM] (signed)
Scale:
    ldh [hSign], a
    call Abs
    ld e, a
    ld a, [wShotSpeed]
    call Mul8
    ldh a, [hM]
    ld c, a
    ld b, 0
.div
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc 0
    ld h, a
    jr c, .done
    inc b
    jr .div
.done
    ldh a, [hSign]
    bit 7, a
    ld a, b
    ret z
    cpl
    inc a
    ret

; hl = a * e (unsigned)
Mul8:
    ld hl, 0
    ld d, 0
    ld b, 8
.loop
    add hl, hl
    rla
    jr nc, .skip
    add hl, de
.skip
    dec b
    jr nz, .loop
    ret

Abs:
    bit 7, a
    ret z
    cpl
    inc a
    ret

FireSpread5:
    ld hl, Spread5
    ld a, 5
    jr FireSpread
FireSpread3:
    ld hl, Spread3
    ld a, 3
FireSpread:
    ldh [hCount2], a
    push hl
    call ShotOrigin
    pop hl
.loop
    ld a, [hl+]
    ld d, a
    ld a, [hl+]
    ld e, a
    push hl
    push bc
    call SpawnEShot
    pop bc
    pop hl
    ldh a, [hCount2]
    dec a
    ldh [hCount2], a
    jr nz, .loop
    ret

; a = signed 1/16 px -> bc = the same as signed 8.8
V16:
    ld b, a
    swap a
    ld c, a
    and $0F
    bit 7, b
    jr z, .pos
    or $F0
.pos
    ld b, a
    ld a, c
    and $F0
    ld c, a
    ret

; b = x, c = y, d = vx, e = vy (signed 1/16 px per frame)
SpawnEShot:
    ld hl, wEShots
    ld a, MAX_ESHOT
    ldh [hCount3], a
.find
    ld a, [hl]
    or a
    jr z, .got
    ld a, l
    add OBJ_SIZE
    ld l, a
    ldh a, [hCount3]
    dec a
    ldh [hCount3], a
    jr nz, .find
    ret
.got
    ld [hl], T_ESHOT
    inc l
    xor a
    ld [hl+], a
    ld [hl], b
    inc l
    ld [hl+], a
    ld [hl], c
    inc l
    ld a, d
    call V16
    ld [hl], c
    inc l
    ld [hl], b
    inc l
    ld a, e
    call V16
    ld [hl], c
    inc l
    ld [hl], b
    ret

UpdateEShots:
    ld hl, wEShots
    ld a, MAX_ESHOT
    ldh [hCount], a
.loop
    ld a, [hl]
    or a
    jr z, .next
    push hl
    inc l
    call MoveObj
    pop hl
    cp 152
    jr nc, .kill
    cp 8
    jr c, .kill
    inc l
    inc l
    ld a, [hl]
    dec l
    dec l
    cp 168
    jr c, .next
.kill
    ld [hl], 0
.next
    ld a, l
    add OBJ_SIZE
    ld l, a
    ldh a, [hCount]
    dec a
    ldh [hCount], a
    jr nz, .loop
    ret

; hl = enemy, a = damage
HitEnemy:
    ld b, a
    ld d, h
    ld e, l
    ld a, [de]
    cp T_BOOM
    ret nc
    ld a, e
    add O_HP
    ld l, a
    ld a, [hl]
    sub b
    jr c, .dead
    jr z, .dead
    ld [hl], a
    ld a, e
    add O_FLASH
    ld l, a
    ld [hl], 4
    ret
.dead
    ld a, [de]
    push af
    call TypeInfo
    ld a, c
    add 4
    ld c, a
    ld a, [bc]
    ld l, a
    inc c
    ld a, [bc]
    ld h, a
    call AddScore
    ld h, d
    pop af
    cp T_BOSS
    jr nz, .boom
    ; boss: a chain of explosions and the screen is cleared of shots
    ld a, e
    add O_X
    ld l, a
    ld a, [hl]
    ld [wBossX], a
    add 8
    ld [hl], a
    ld a, e
    add O_Y
    ld l, a
    ld a, [hl]
    ld [wBossY], a
    add 8
    ld [hl], a
    ld a, 56
    ld [wBossBoomT], a
    ld hl, wEShots
    ld b, MAX_ESHOT
.clr
    ld [hl], 0
    ld a, l
    add OBJ_SIZE
    ld l, a
    dec b
    jr nz, .clr
    ld h, d
    ld a, SFX_BIGBOOM
    call SfxPlay
.boom
    ld a, T_BOOM
    ld [de], a
    ld a, e
    add O_VXL
    ld l, a
    xor a
    ld [hl+], a
    ld [hl+], a
    ld [hl], $60
    inc l
    ld [hl+], a
    inc l                   ; skip HP
    ld [hl], a              ; age
    ld a, e
    add O_FLASH
    ld l, a
    xor a
    ld [hl], a
    ld a, SFX_BOOM
    jp SfxPlay

; hl = points / 10 in BCD (h = high byte)
AddScore:
    ld a, [wScore]
    add l
    daa
    ld [wScore], a
    ld a, [wScore + 1]
    adc h
    daa
    ld [wScore + 1], a
    ld a, [wScore + 2]
    adc 0
    daa
    ld [wScore + 2], a
    ret

BossBooms:
    ld a, [wBossBoomT]
    or a
    ret z
    dec a
    ld [wBossBoomT], a
    and 7
    ret nz
    call Random
    and 15
    ld hl, wBossX
    add [hl]
    ldh [hTmp], a
    call Random
    and 15
    ld hl, wBossY
    add [hl]
    ld c, a
    ldh a, [hTmp]
    ld b, a
    jp SpawnBoom

; ================================================================ collisions
Collide:
    ; ---- player shots against enemies
    ld hl, wPShots
    ld a, MAX_PSHOT
    ldh [hCount], a
.shots
    ld a, [hl]
    or a
    jr z, .shotnext
    add 6
    ld c, a
    inc l
    ld a, [hl]
    dec l
    add 4
    ld b, a
    push hl
    call ShotVsEnemies
    pop hl
    jr nc, .shotnext
    ld [hl], 0
.shotnext
    ld a, l
    and $FC
    add 4
    ld l, a
    ldh a, [hCount]
    dec a
    ldh [hCount], a
    jr nz, .shots
    ; ---- everything else involves the player
    ld a, [wPDead]
    or a
    ret nz
    ld a, [wPX]
    add 8
    ldh [hPCX], a
    ld a, [wPY]
    add 8
    ldh [hPCY], a
    ld a, [wPInv]
    or a
    jr nz, .bodies
    ld hl, wEShots
    ld a, MAX_ESHOT
    ldh [hCount2], a
.eshots
    ld a, [hl]
    or a
    jr z, .eshotnext
    push hl
    inc l
    inc l
    ld a, [hl]
    add 4
    ld b, a
    inc l
    inc l
    ld a, [hl]
    add 4
    ld c, a
    pop hl
    ldh a, [hPCX]
    sub b
    call Abs
    cp 4
    jr nc, .eshotnext
    ldh a, [hPCY]
    sub c
    call Abs
    cp 4
    jr nc, .eshotnext
    ld [hl], 0
    jp PlayerHit
.eshotnext
    ld a, l
    add OBJ_SIZE
    ld l, a
    ldh a, [hCount2]
    dec a
    ldh [hCount2], a
    jr nz, .eshots
.bodies
    ; ---- enemy bodies and power capsules
    ld hl, wEnemies
    ld a, MAX_EN
    ldh [hCount2], a
.body
    ld a, [hl]
    or a
    jr z, .bodynext
    cp T_BOOM
    jr z, .bodynext
    push hl
    ld d, h
    ld e, l
    call TypeInfo
    inc c
    ld a, [bc]
    add 3
    ldh [hTmp2], a
    inc c
    ld a, [bc]
    add 3
    ldh [hTmp2 + 1], a
    inc c
    ld a, [bc]
    ldh [hTmp2 + 2], a
    ld h, d
    ld a, e
    add O_X
    ld l, a
    ldh a, [hTmp2 + 2]
    add [hl]
    ld l, a
    ldh a, [hPCX]
    sub l
    call Abs
    ld l, a
    ldh a, [hTmp2]
    ld h, a
    ld a, l
    cp h
    jr nc, .miss
    ld h, d
    ld a, e
    add O_Y
    ld l, a
    ldh a, [hTmp2 + 2]
    add [hl]
    ld l, a
    ldh a, [hPCY]
    sub l
    call Abs
    ld l, a
    ldh a, [hTmp2 + 1]
    ld h, a
    ld a, l
    cp h
    jr nc, .miss
    pop hl
    ld a, [hl]
    cp T_POWER
    jr z, .collect
    cp T_BOSS
    jp z, PlayerHit
    push hl
    call PlayerHit
    pop hl
    ld a, [wPDead]
    or a
    ret z
    ld a, 6
    jp HitEnemy
.collect
    ld [hl], 0
    ld a, SFX_POWER
    call SfxPlay
    ld a, [wPower]
    cp 2
    jr nc, .bonus
    inc a
    ld [wPower], a
    ret
.bonus
    ld hl, $0100            ; 1000 points
    jp AddScore
.miss
    pop hl
.bodynext
    ld a, l
    add OBJ_SIZE
    ld l, a
    ldh a, [hCount2]
    dec a
    ldh [hCount2], a
    jp nz, .body
    ret

; b, c = centre of a player shot -> carry set if it hit something
ShotVsEnemies:
    ld hl, wEnemies
    ld a, MAX_EN
    ldh [hCount2], a
.loop
    ld a, [hl]
    or a
    jr z, .next
    cp T_BOOM
    jr nc, .next
    push hl
    push bc
    ld d, h
    ld e, l
    call TypeInfo
    inc c
    ld a, [bc]
    inc a
    ldh [hTmp2], a
    inc c
    ld a, [bc]
    add 5
    ldh [hTmp2 + 1], a
    inc c
    ld a, [bc]
    ldh [hTmp2 + 2], a
    pop bc
    ld h, d
    ld a, e
    add O_X
    ld l, a
    ldh a, [hTmp2 + 2]
    add [hl]
    ld l, a
    ld a, b
    sub l
    call Abs
    ld l, a
    ldh a, [hTmp2]
    ld h, a
    ld a, l
    cp h
    jr nc, .miss
    ld h, d
    ld a, e
    add O_Y
    ld l, a
    ldh a, [hTmp2 + 2]
    add [hl]
    ld l, a
    ld a, c
    sub l
    call Abs
    ld l, a
    ldh a, [hTmp2 + 1]
    ld h, a
    ld a, l
    cp h
    jr nc, .miss
    pop hl
    ld a, 1
    call HitEnemy
    scf
    ret
.miss
    pop hl
.next
    ld a, l
    add OBJ_SIZE
    ld l, a
    ldh a, [hCount2]
    dec a
    ldh [hCount2], a
    jp nz, .loop
    and a
    ret

; ================================================================ sprites
; hl -> frame, b = y, c = x, de = OAM cursor
EmitFrame:
    ld a, [hl+]
    ldh [hCount], a
.loop
    ld a, e
    cp 160
    ret nc
    ld a, [hl+]
    add b
    ld [de], a
    inc e
    ld a, [hl+]
    add c
    ld [de], a
    inc e
    ld a, [hl+]
    ld [de], a
    inc e
    ldh a, [hAttr]
    xor [hl]
    inc hl
    ld [de], a
    inc e
    ldh a, [hCount]
    dec a
    ldh [hCount], a
    jr nz, .loop
    ret

BuildOAM:
    ld de, wOAM
    xor a
    ldh [hAttr], a
    ld a, [wBannerT]
    or a
    call nz, DrawBanner
    ; player, blinking while invulnerable
    ld a, [wPDead]
    or a
    jr nz, .noship
    ld a, [wPInv]
    and 4
    jr nz, .noship
    ld hl, FrShip0
    ldh a, [hFrame]
    and 4
    jr z, .flame
    ld hl, FrShip1
.flame
    ld a, [wPY]
    ld b, a
    ld a, [wPX]
    ld c, a
    call EmitFrame
.noship
    ; enemy shots come early so they are never the sprites that drop out
    ld hl, wEShots
    ld a, MAX_ESHOT
    ldh [hCount2], a
.eshots
    ld a, [hl]
    or a
    jr z, .eshotnext
    push hl
    inc l
    inc l
    ld c, [hl]
    inc l
    inc l
    ld b, [hl]
    ld hl, FrEShot
    call EmitFrame
    pop hl
.eshotnext
    ld a, l
    add OBJ_SIZE
    ld l, a
    ldh a, [hCount2]
    dec a
    ldh [hCount2], a
    jr nz, .eshots
    ; enemies start at a different slot every frame: when a line has too many
    ; sprites they take turns to flicker instead of one vanishing for good
    ld a, [wRot]
    add 3
    and 7
    ld [wRot], a
    swap a
    ld l, a
    ld h, HIGH(wEnemies)
    ld a, MAX_EN
    ldh [hCount2], a
.enemies
    ld a, [hl]
    or a
    call nz, DrawEnemy
    ld a, l
    add OBJ_SIZE
    and $7F
    ld l, a
    ldh a, [hCount2]
    dec a
    ldh [hCount2], a
    jr nz, .enemies
    ; player shots
    ld hl, wPShots
    ld a, MAX_PSHOT
    ldh [hCount2], a
.pshots
    ld a, [hl]
    or a
    jr z, .pshotnext
    push hl
    ld b, a
    inc l
    ld c, [hl]
    ld hl, FrShot
    call EmitFrame
    pop hl
.pshotnext
    inc l
    inc l
    inc l
    inc l
    ldh a, [hCount2]
    dec a
    ldh [hCount2], a
    jr nz, .pshots
    ; hide what is left over from the previous frame
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

; hl = enemy slot (preserved), de = OAM cursor
DrawEnemy:
    push hl
    ld a, l
    add O_FLASH
    ld l, a
    ld a, [hl]
    or a
    jr z, .noflash
    ld a, $10               ; object palette 1: solid white
.noflash
    ldh [hAttr], a
    ld a, l
    sub O_FLASH - O_X
    ld l, a
    ld c, [hl]
    inc l
    inc l
    ld b, [hl]
    ld a, l
    sub O_Y
    ld l, a
    ld a, [hl]
    push bc
    cp T_SAUCER
    jr nz, .notsaucer
    ld a, l
    add O_T
    ld l, a
    ld a, [hl]
    and 8
    ld hl, FrSaucer0
    jr z, .go
    ld hl, FrSaucer1
    jr .go
.notsaucer
    cp T_BOOM
    jr nz, .other
    ld a, l
    add O_T
    ld l, a
    ld a, [hl]
    ld hl, FrBoom0
    cp 6
    jr c, .go
    ld hl, FrBoom1
    cp 12
    jr c, .go
    ld hl, FrBoom2
    jr .go
.other
    ld hl, TypeFrames
    call TableWord
.go
    pop bc
    call EmitFrame
    xor a
    ldh [hAttr], a
    pop hl
    ret

; banner: start x, then letter tiles ($FE space, $FF end), drawn across the middle
DrawBanner:
    ld hl, wBanner
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [hl+]
    ld c, a
.loop
    ld a, [hl+]
    cp $FF
    ret z
    cp $FE
    jr z, .space
    ld b, a
    ld a, e
    cp 160
    ret nc
    ld a, 80
    ld [de], a
    inc e
    ld a, c
    ld [de], a
    inc e
    ld a, b
    ld [de], a
    inc e
    xor a
    ld [de], a
    inc e
.space
    ld a, c
    add 8
    ld c, a
    jr .loop

; ================================================================ HUD and scenes
; hl -> 20 characters
SetHud:
    ld de, wHud
    ld b, 20
.copy
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .copy
    ret

; hl -> 3-byte BCD score, de -> destination: 6 digits and the trailing zero
PutScore:
    inc hl
    inc hl
    ld b, 3
.loop
    ld a, [hl-]
    ld c, a
    swap a
    and $0F
    ld [de], a
    inc de
    ld a, c
    and $0F
    ld [de], a
    inc de
    dec b
    jr nz, .loop
    xor a
    ld [de], a
    inc de
    ret

HudHi:
    ld hl, TxtHi
    call SetHud
    ld hl, wHiScore
    ld de, wHud + 8
    jp PutScore

UpdateHud:
    ld hl, wScore
    ld de, wHud
    call PutScore
    ld h, d
    ld l, e
    ld a, ' '
    ld [hl+], a
    ld [hl+], a
    ld a, 'p'
    ld [hl+], a
    ld a, [wLives]
    ld [hl+], a
    ld a, ' '
    ld [hl+], a
    ld a, 'b'
    ld [hl+], a
    ld a, [wBombs]
    ld [hl+], a
    ld a, ' '
    ld [hl+], a
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'T'
    ld [hl+], a
    ld a, [wStage]
    inc a
    ld [hl+], a
    ld a, [wLoop]
    or a
    ld a, ' '
    jr z, .noloop
    ld a, '+'
.noloop
    ld [hl], a
    ret

ClearObjects:
    ld hl, wEnemies
    ld bc, MAX_EN * OBJ_SIZE + MAX_PSHOT * 4
    xor a
    call MemFill
    ld hl, wEShots
    ld bc, MAX_ESHOT * OBJ_SIZE
    xor a
    jp MemFill

ClearOAMBuf:
    ld hl, wOAM
    ld bc, 160
    xor a
    call MemFill
    ld a, 160
    ld [wOamEnd], a
    ret

; a = scene: background tiles and map (LCD off)
LoadScene:
    add a
    add a
    add a
    ld l, a
    ld h, 0
    ld de, SceneTable
    add hl, de
    ld a, [hl+]
    ld [wScT], a
    ld a, [hl+]
    ld [wScT + 1], a
    ld a, [hl+]
    ld [wScN], a
    ld a, [hl+]
    ld [wScM], a
    ld a, [hl+]
    ld [wScM + 1], a
    ld hl, wScT
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, $9000 + FONT_TILES * 16
    ld a, [wScN]
    ld b, a
    ld c, FONT_TILES
.tile
    ld a, c
    cp 128
    jr nz, .same
    ld de, $8800            ; indices 128+ live in the shared block
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
    ld hl, wScM
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, $9800
    ld bc, 32 * 32
    call MemCopy
    ld hl, $9C00
    ld bc, 32
    ld a, ' '
    jp MemFill
