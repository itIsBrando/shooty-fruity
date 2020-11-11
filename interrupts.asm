SECTION "vblank", ROM0[$40]
; v-blank interrupt at 40h
    jp vblank
    
SECTION "STAT", ROM0[$48]
; services scanline interrupt
    jp scrollBottomRow

SECTION "timer", ROM0[$50]
    reti

SECTION "serial", ROM0[$58]
    reti

SECTION "joypad", ROM0[$60]
    reti

SECTION "interrupt routines", ROM0

vblank:
    push af
    push hl
    push de
    push bc

    ; increase fruit timer
    ld hl, fruitSpawnTimer
    ld a, [hl]
    inc a
    and a, $1F
    ld [hl], a

    ; increase bird timer
    ld hl, birdSpawnTimer
    ld a, [hl]
    inc a
    and $3F
    ld [hl], a


    ; increase timer since last bullet was shot
    ld hl, lastBullet
    inc [hl]
	call drawScore

    call DMATransfer

    
    pop bc
    pop de
    pop hl
	pop af
    reti

scrollBottomRow:
    push af
    push hl
    
    ld hl, titleScreenScroll
    dec [hl]

    ; check scanline
    ldh a, [rLY]
    cp 143 - 8    ; first interrupt
    jr z, .setSCX
    cp 144      ; second interrupt
    jr z, .restoreSCX
    
.return:
    pop hl
    pop af
    reti

.setSCX:
    ; save the BG X position
    ldh a, [rSCX]
    ld [rSCXBackup], a

    ; set BG X to the scroll register
    ld a, [titleScreenScroll]
    sra a
    ld [rSCX], a

    ; set new scanline interrupt
    ld a, 144
    ldh [rLYC], a
    jr .return

.restoreSCX:
    ; restore BG X
    ld a, [rSCXBackup]
    ldh [rSCX], a

    ; reset LCD interrupt scanline
    ld a, 143 - 8
    ldh [rLYC], a
    jr .return