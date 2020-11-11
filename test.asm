	INCLUDE "../hardware.inc"
	
;					TO-DO
;	- add bird/bullet collision
;	- add title screen bounce
;	- add name entry
;	- add the ability for entry of multiple highscores
;	- force death screen for lose
;	- maybe have sprites 'fade out' when a bird is shot
;	- pimp up highscore screen
; GAME MUST END WHEN BIRD IS HIT OTHERWISE THEY WILL STOP SPAWNING!!!!


; ==============================================
; Register constants
; ==============================================
DMA_ADDRESS		EQU $C100
WINDOW_LOCATION	EQU $9C00
; routine put in HRAM that copies sprite objs to OAM
; - Destroys: AF
DMATransfer 	EQU _HRAM
; 00 is lightest and 11 is darkest
PALETTE			EQU %11100100 

; ==============================================
; Tile constants
; ==============================================
SPRITE_GROUND		EQU $02
SPRITE_GROUND_CGB	EQU $0D
SPRITE_CHAR			EQU $01
SPRITE_FRUIT		EQU $04
SPRITE_BIRD			EQU $0E
SPRITE_BULLET		EQU $0F
SPRITE_UP_ARROW		EQU $2C
SPRITE_DOWN_ARROW	EQU $2D

; value that the number is in the character set
NUMBER_BASE			EQU $20
; value that the capital letters is in the character set
ALPHABET_BASE		EQU $31

; starting stack address
STACK_BASE			EQU $D000

; ==============================================
; Some defines that affect game data
; ==============================================
; number of highscores to display in menus
MAX_HIGHSCORES		EQU 4
; max number of fruits on screen at a time
MAX_FRUITS			EQU 17
; max number of birds on screen at a time
MAX_BIRDS			EQU 5
; default character position
CHAR_Y				EQU 144 - 8
; determines how many times the screen shake routine shakes the screen
SCREEN_SHAKE_LENGTH EQU 30
; the speed of `scrollWindowUp` and `scrollWindowDown`
SCROLL_SPEED		EQU $23

; ==============================================
; Save RAM offsets
; ==============================================
C_RAM_BASE 		EQU $A000
rsset C_RAM_BASE ; set up structure
; each entry has four bytes for name followed by six for BCD number
C_RAM_HIGHSCORE rb MAX_HIGHSCORES * (6 + 4)
; only used for `C_RAM_SIZEOF`
C_RAM_ENDADDR	rb 0
; singular byte used as a checksum
C_RAM_CHECKSUM	rb 1
; exlucdes the 8-bit checksum byte
C_RAM_SIZEOF	EQU C_RAM_ENDADDR - C_RAM_BASE

KEY_DOWN		EQU 7
KEY_UP			EQU 6
KEY_LEFT		EQU 5
KEY_RIGHT		EQU 4
KEY_START		EQU 3
KEY_SELECT		EQU 2
KEY_B			EQU 1
KEY_A			EQU 0

CART_NAME		EQUS "\"SHOOTY FRUITY\""

HOOT = $20
; set up CHARMAP
ALPHABET EQUS "\"0123456789:>^<?abABCDEFGHIJKLMNOPQRSTUVWXYZ\""
letter EQUS "strsub(ALPHABET, HOOT - $1F, 1)"

REPT strlen(ALPHABET) - 1
CHARMAP letter, HOOT
HOOT = HOOT + 1
ENDR

CHARMAP "a", $2F	; the A button sprite
CHARMAP "b", $30	; the B button sprite
CHARMAP "s", $5D	; the START button sprite
CHARMAP "t", $5E
CHARMAP "r", $5F
CHARMAP "l", $4B
CHARMAP "d", $4C
CHARMAP " ", $7F	; 7F is some random blank tile


INCLUDE "interrupts.asm"


; ==============================================
; turns off the screen
;	- Inputs: NONE
;	- Parameters: `NONE`
;	- Destroys: `ALL`
; ==============================================
disableScreen: MACRO
	xor a
	ld [rLCDC], a
ENDM


; ==============================================
; this macro returns the DMA base address of index `A`
;	- Inputs: `A` = index,
;	- Output: `HL` = address
;	- Destroys: `AF`, `DE`
; ==============================================
GET_DMA_ADDRESS: MACRO
	ld hl, DMA_ADDRESS
	sla a
	sla a
	ld d, 0
	ld e, a
	add hl, de
ENDM

; ==============================================
; Copies `HL` into `DE`
;	- Inputs: `HL`
;	- Output: `DE` = `HL`
;	- Destroys: `NONE`
; ==============================================
LOAD_DE_HL: MACRO
	ld d, h
	ld e, l
ENDM


; ==============================================
; this macro copies memory using memCpy
;	- Inputs: `NONE`
;	- Parameters: source, destination, size of block
;	- Destroys: `ALL`
; ==============================================
MCOPY: MACRO
	ld hl, \1
	ld de, \2
	ld bc, \3
	call memCpy
ENDM

; ==============================================
; this macro sets a chunk of data to a specific value
;	- Inputs: `NONE`
;	- Parameters: 8-bit value, destination, size of block
;	- Destroys: `AF`, `BC`, `D`, `HL`
; ==============================================
MSET: MACRO
	IF \1 == 0
		xor a
	ELSE
		ld a, \1
	ENDC
	ld hl, \2
	ld bc, \3
	call memSet
ENDM


; ==============================================
; this macro draws string in `HL` at (x, y). DOES check for v-blank
;	- Inputs: `HL` pointer to string
;	- Parameters: string, x, y
;	- Destroys: `AF`, `DE`, `HL`
; ==============================================
stringAT: MACRO
	ld de, $9800 + ((\3) * 32) + \2
	ld hl, \1
	call drawString
ENDM


; ==============================================
; this macro draws string in `HL` at (x, y) on window. DOES check for v-blank
;	- Inputs: `HL` pointer to string
;	- Parametres: string, x, y
;	- Destroys: `AF`, `DE`, `HL`
; ==============================================
stringATWindow: MACRO
	ld hl, \1
	ld de, WINDOW_LOCATION + (\3 * 32) + \2
	call drawString
ENDM

; ==============================================
; plays a sound using a pointer to register values
;	- Inputs: NONE
;	- Parameters: starting NR`XX` register, pointer to sound effect
;	- Destroys: `ALL`
; ==============================================
playSoundEffect: MACRO
	ld hl, \2
	ld de, rNR\1
	IF \1 == 41
		ld bc, 4
	ELSE
		ld bc, 5
	ENDC
	call memCpy
ENDM

; ==============================================
; Multiplies A by 10
;	- Inputs: `A`
;	- Outputs: `A` multiplied by 10
;	- Parameters: `NONE`
;	- Destroys: `E`
; ==============================================
A_TIMES_10: MACRO
	ld e, a
	add a, a ;x2
	add a, a ;x4
	add a, a ;x8
	add a, e ;x9
	add a, e ;x10
ENDM


SECTION "BEGIN", ROM0[$100]
	di
	jp Start

ds $134-$104

SECTION "HEADER", ROM0[$134]

	db CART_NAME, 0, 0 ; 134-142 is name
	db $80 ; CGB compatibility flag
	db "OK" ; new license code
	db 0 ; SGB compatibility flag
	db CART_ROM_MBC1_RAM_BAT
	db CART_ROM_256K
	db CART_RAM_16K
	db 1 ; INTERNATIONAL
	db $33 ; LICENSE CODE
	db 0 ; ROM VERISION
	db 0, 0, 0

SECTION "MAIN", ROM0
mainStart:

INCLUDE "cgb.asm"
Start:
	; load `isCGB` with nonzero if we have a CGB
	cp $11 ; check if CGB
	jr nz, .notCGB
	; if CGB do this hoot
	ld [isCGB], a

	ld a, 4
	ld [maxMenu], a
	jr .skip
.notCGB
	xor a
	ld [isCGB], a
	
	ld a, 3
	ld [maxMenu], a
.skip:

	ld sp, STACK_BASE
	call waitVBlank

	; enable timer at 4096hz
	ld hl, rTAC
	set 2, [hl]

	; disable screen
	xor a
	ld [rLCDC], a

	; reset theme
	ld [currentTheme], a

	; only in CGB but nothing should happen in regular GB
	set 7, a
	ldh [$FF68], a ; background palettes
	ldh [$FF6A], a ; objects pallette
	

	; clear VRAM
	MSET 0, $8000, $9FFF - $8000

	; clear DMA RAM
	MSET 0, DMA_ADDRESS, 160 * 2

	; load tiles into VRAM
	MCOPY tileData, _VRAM, tileDataEnd - tileData
		
	; set up OAM routine in HRAM
	MCOPY dma_routine, DMATransfer, dma_routine_end - dma_routine

	; sets up a layer of ground
	MSET SPRITE_GROUND,  $9800 + (23 * 32) + 0, 32

	; looks better with this than a second row of ground
	stringAT TXT_FRUITS, 0, 24

	; load map
	ld de, mapData
	call loadMap

	; set up background
	ld a, 6 * 8
	ldh [rSCX], a
	ld [rSCXBackup], a
	ld a, 7 * 8
	ldh [rSCY], a
		
	; initialize gameboy color special stuff
	ld a, [isCGB]
	or a
	call nz, CGBMode

	; no interrupts rn
	xor a
	ldh [rIE], a
	
	call enableScreen
	
	jp titleScreen

; turn on screen
; - enable bg, window, & sprite
; - bg tiles at 8000-8FFF
; - bg map at 9800-9BFF
; - window map at 9C00-9FFF
enableScreen::
	ld a, %11110011
	ld [rLCDC], a
	ret

mainLoop:
	call scanJoypad



	push af
	bit KEY_RIGHT, a
	call nz, moveRight
	pop af

	push af
	bit KEY_LEFT, a
	call nz, moveLeft
	pop af

	push af
	bit KEY_A, a
	call nz, createBullet
	pop af

	bit KEY_START, a
	call nz, pauseGame

	; create fruits
	call spawnFruit
	call spawnBird

	call moveBullets
	call moveFruits ; if fruits are hit, make 'em fall
	call moveBirds	; move them flying dudes

	halt ; to keep 60 FPS
	
	jr mainLoop


; delete later or just reform because it's kinda neat
gameOver::
	call clearDMA
	
	; gotta check if we even got a highscore
	call enableRAM

	; compare with the lowest highscore
	ld hl, score
	ld de, C_RAM_HIGHSCORE + (MAX_HIGHSCORES * 10) - 6
	call cpBCDNumber
	; if 'score' is smaller than the last entry, then your score sux and skip name entering
	jr c, .noHighScore
	call disableRAM

	call stringMenu

	; enable RAM writing
	call enableRAM

	call addHighScore

	; skip if the highscore we are adding is the last
	cp MAX_HIGHSCORES
	jr z, .skip

	push af
	; gotta move the other high scores down
	; B = number of times to move score
	; A = starting score address
	ld a, b
	A_TIMES_10
	ld e, a
	ld d, 0
	push de
	
	ld hl, C_RAM_HIGHSCORE + 9
	add hl, de
	push hl
	ld de, 10
	call sub_HL_DE;add hl, de
	pop de

	pop bc ; C = index * 10, B = 0
	ld a, 40
	sub c
	
	call memCpyDecrement

	pop af
.skip:

	A_TIMES_10
	
	ld e, a
	ld d, 0
	; DE = offset to highscore entry
	ld hl, C_RAM_HIGHSCORE
	add hl, de
	LOAD_DE_HL

	; 'currentName' and 'score' are consecutive
	ld bc, 10
	ld hl, currentName
	call memCpy
	

	; create and copy the new checksum data
	ld hl, C_RAM_BASE
	ld bc, C_RAM_SIZEOF
	call createCheckSum
	ld [C_RAM_CHECKSUM], a

.noHighScore:

	; disable writing/reading RAM
	call disableRAM

	; reset stack
	ld sp, STACK_BASE
	
	jp titleScreen

mainEnd:

SECTION "OBJECT", ROM0

objectStart:

; ==============================================
; creates a bird if it can
;	- Destroys: `ALL`
; ==============================================
spawnBird:
	ld a, [birdSpawnTimer]
	or a
	ret nz
	
	ld hl, birdNumber
	ld a, [hl]
	cp MAX_BIRDS
	ret z

	inc [hl]

	ld a, [DMAIndex]
	inc a
	ld c, a
	ld b, 2
	call setSpriteFlag
	ld a, c


	; this will be the Y coordinate
	; if it's even, the X coord will be 0, else 168
	call xrnd
	
	ld b, 0 ; x pos

	bit 0, a
	jr z, spawnBird.isEven


	ld c, a
	ld a, [DMAIndex]
	inc a
	ld b, OAMF_XFLIP | 2; set x flip
	call setSpriteFlag
	ld a, c

	ld b, 168

spawnBird.isEven:
	and $1F
	add a, $1F
	ld c, a ; y pos

	ld hl, DMAIndex
	inc [hl]
	ld a, [hl]

	push af
	call setSpritePos
	pop af

	ld b, SPRITE_BIRD
	jp setSpriteTile


; ==============================================
; creates a fruit
;	- Destroys: `ALL`
; ==============================================
spawnFruit:
	; return if it is not a good time
	ld a, [fruitSpawnTimer]
	cp $E ; this is just some random number
	ret nz
	; return if there is max fruits
	ld hl, fruitNumber
	ld a, [hl]
	cp MAX_FRUITS
	ret z
	
	inc [hl]

	ld de, DMAIndex
	ld a, [de]
	inc a
	and $1F
	ld [de], a


	; randomize fruit sprite
	call xrnd
	and a, $07
	add a, SPRITE_FRUIT
	ld b, a ; fruit sprite
	ld a, [de]
	
	push af ; save index

	call setSpriteTile

	; get the palette for each fruit
	ld c, b
	ld b, 0
REPT SPRITE_FRUIT
	dec c
ENDR
	ld hl, fruitPaletteLUT
	add hl, bc
	ld b, [hl]

	pop af
	push af
	
	; actually set sprite palette
	call setSpriteFlag


	; randomize y position
	call xrnd
	and 63
	add 24
	ld c, a

	; randomize x position
	call xrnd
	and 127
	add 16
	ld b, a
	
	pop af ; restore A with the index


	jp setSpritePos

fruitPaletteLUT:
	db OBJPAL_0, OBJPAL_4, OBJPAL_3, OBJPAL_6, \
	 OBJPAL_7, OBJPAL_0, OBJPAL_6, OBJPAL_5

; ==============================================
;	creates a bullet at player x & y
;	- Destroys: `AF`, `BC`, `HL`, `DE`
; ==============================================
createBullet:
	ld hl, lastBullet
	ld a, 10
	cp [hl]
	ret nc

	xor a
	ld [lastBullet], a

	playSoundEffect 10, SOUND_BULLET


	ld hl, DMA_ADDRESS + 3
	ld de, DMAIndex

	; set bullet direction
	ld a, [hl-] ; direction
	dec hl
	;or OBJPAL_1 ; set palette. unneeded rn cuz its already character palette
	ld b, a
	ld a, [de]
	inc a ; we increment A later in the routine but need it +1 now

	push hl
	push de
	call setSpriteFlag
	pop de
	pop hl
	

	ld a, [hl] ; x position
	ld b, a
	ld c, CHAR_Y

	; increment DMAIndex
	ld a, [de]
	inc a
	cp $1F
	ret z
	ld [de], a

	; set sprite position
	push af
	call setSpritePos

	pop af

	;set sprite tile
	ld b, SPRITE_BULLET
	jp setSpriteTile

; ==============================================
;	moves all the birds
;	searching all of DMA
;	- Destroys: `ALL`
; ==============================================
moveBirds:
	ld hl, DMA_ADDRESS + 4 + 2
	; skip over first entry
	; look at the tile byte

	ld a, [DMAIndex]
	or a
	ret z

	ld b, a
moveBirds.loop:
	push hl

	; skip if not a bird
	ld a, [hl]
	cp SPRITE_BIRD
	jr nz, moveBirds.skip
	; move bird

	dec hl

	push hl
	; X position
	ld a, [hl]

	cp 240
	jr z, .deleteBird
	sra a
	sra a
	and $1F
	ld hl, sinLUT
	ld d, 0
	ld e, a
	add hl, de
	ld e, [hl]
	pop hl
	dec hl
	; Y position
	ld a, [hl]
	add a, e ; add displacement
	ld [hl], a

	inc hl
	inc hl
	inc hl
	ld a, [hl-]
	dec hl ; point to the X byte

	bit OAMB_XFLIP, a ; check x-flip
	jr z, moveBirds.right
	; move left
	dec [hl]
	jr moveBirds.skip
moveBirds.right:
	; move right
	inc [hl]

moveBirds.skip:
	pop hl
	ld de, 4
	add hl, de
	dec b
	jr nz, moveBirds.loop
	ret 

.deleteBird:
	dec hl ; point to the beginning of the entry


	push bc
	call deleteElement
	pop bc
	pop hl

	ld hl, birdNumber
	dec [hl]

	;dec b ; is this needed???????

	jr moveBirds.skip


; ==============================================
;	makes all the fruits, that are upside down, fall.
;	however, it really only checks to see if a sprite is upside down
;	searching all of DMA
;	- Destroys: `ALL`
; ==============================================
moveFruits:
	ld hl, DMA_ADDRESS + 4 + 3
	; skip over first entry, which is character
	; looking at flags byte
	
	ld a, [DMAIndex]
	or a
	ret z

	ld b, a
moveFruits.loop:

	push hl
	; checks if Y-flip bit is set
	bit OAMB_YFLIP, [hl]
	jr z, moveFruits.skip

	dec hl
	dec hl
	dec hl

	; increase Y position
	ld a, [hl]
	inc a
	inc a
	ld [hl], a


	; if on screen, then skip deletion
	cp 144
	jr c, moveFruits.skip

	inc hl ; X
	inc hl ; tile
	ld a, [hl]
	; Game Over logic
	cp SPRITE_BIRD
	jp z, gameOver
	
	dec hl
	dec hl
	
	push bc
	call deleteElement
	pop bc

	ld hl, fruitNumber
	dec [hl]

	ld hl, score + 5
	call incBCDNumber
	
	pop hl

	dec b
	jr nz, moveFruits.loop
	push hl
	inc b

moveFruits.skip:
	pop hl
	ld de, 4
	add hl, de
	dec b
	jr nz, moveFruits.loop
	ret




; ==============================================
;	moves all the bullets upwards
;	searching all of DMA
;	- Destroys: `AF`, `B`, `HL`, `DE`
; ==============================================
moveBullets:
	ld hl, DMA_ADDRESS + 4 + 2 ; skip over first entry, which is character
	
	ld a, [DMAIndex]
	or a
	ret z

	ld b, a
	;HL points to tile of each sprite
.loopBullets:
	ld a, [hl]
	or a
	ret z
	cp SPRITE_BULLET
	jr nz, .skip ; skip if not bullet


	inc hl ; flags
	ld a, [hl]

	dec hl ; tile

	dec hl ; x
	dec hl ; y
	
	; HL = address of Y
	
	dec [hl]
	dec [hl]

	bit OAMB_YFLIP, a
	jr nz, .deleteBullet


	ld a, [hl]

	; check if y = 0
	or a
	jr z, .deleteBullet

	; chk collisions
	call chkCollisions
	
.returnfromDelete:
	inc hl
	inc hl
.skip:
	ld de, 4
	add hl, de
	dec b
	jr nz, .loopBullets
	ret

.deleteBullet:
	push hl
	call deleteElement
	pop hl
	jr .returnfromDelete


; ==============================================
;	Checks to see if any collision happens with fruit
;	- Inputs: `HL` = pointer to Y coord of DMA
;	- Destroys: `AF`, `DE`
; ==============================================
chkCollisions:
	push bc
	push hl
	
	ld hl, DMA_ADDRESS + 6 ; look at type
	ld a, [DMAIndex]
	ld b, a
chkCollisions.loop:
	pop de
	push de
	; DE = pointer to Y coord of bullet
	
	push hl ; save current DMA entry
	ld a, [hl]
	or a
	jr z, chkCollisions.skip
	;cp SPRITE_BIRD
	;jr z, chkCollisions.skip
	cp SPRITE_BULLET
	jr z, chkCollisions.skip
	; if its a fruit or bird

	dec hl ; x
	inc de ; x

	; check x Pos
	ld c, [hl]
	ld a, [de] ; x coord of bullet
	add a,3
	cp c
	jr c, chkCollisions.skip
	sub 8 + 3
	cp c
	jr nc, chkCollisions.skip
	
	dec hl
	dec de

	; now check Y coords
	ld c, [hl] ; y coord of object
	ld a, [de] ; y coord of bullet
	cp c
	jr c, chkCollisions.skip
	sub 10
	cp c
	jr nc, chkCollisions.skip
	
	; found collision
	
	inc hl ; x
	inc hl ; tile

	; set the bullet to upside down too
	inc de ; x
	inc de ; tile
	inc de ; flags


	inc hl ; flags
	; check if already hit, if so skip it
	bit OAMB_YFLIP, [hl]
	jr nz, chkCollisions.skip

	set OAMB_YFLIP, [hl] ; flip sprite on Y axis

	
	ld a, [de]
	or OAMF_YFLIP
	ld [de], a

	dec hl ; tile
	; do hoot with birds
	ld a, [hl]
	cp SPRITE_BIRD
	jr z, hitBird

chkCollisions.skip:
	pop hl
	ld de, 4
	add hl, de
	dec b
	jr nz, chkCollisions.loop
	pop hl
	pop bc
	ret

; ==============================================
;	Routine gets called from `chkCollision`
;		when a bird is striken
;	- Inputs: `NONE` 
;	- Destroys: `ALL`
; ==============================================
hitBird:
	inc hl
	set OAMB_YFLIP, [hl] ; make bird upside down

	ld hl, birdNumber
	dec [hl]


	playSoundEffect 41, SOUND_BIRD_HIT

	call waitVRAMReadable
	di
	; delete all sprites that are not birds
	; should do a fade out thing first
	ld hl, DMA_ADDRESS + 2 + 4 ; point to tile
	ld de, 4
	ld a, [DMAIndex]
	ld b, a
hitBird.loop:
	ld a, [hl]
	
	cp SPRITE_BIRD
	jr z, hitBird.skipDelete


	push hl
	push bc
	
	dec hl
	dec hl
	call deleteElement

	pop bc
	pop hl
	dec b
hitBird.skipDelete:

	dec b
	jr nz, hitBird.loop

	call waitVRAMReadable
	call DMATransfer
	ei
	call screenShake

	jr chkCollisions.skip

; ==============================================
;	Shakes the screen. enables interrupts
;	- Inputs: `NONE`
;	- Destroys: `ALL`
; ==============================================
screenShake:
	di
	;wait until scanline is back at 0
screenShake.wait:
	ld a, [rLY]
	or a
	jr nz, screenShake.wait

	ld c, SCREEN_SHAKE_LENGTH
screenShake.loop1
	ld b, 0 ; this is number of scanlines. remove the future 'sra a' if you want all scanlines to move
	ld a, c
	; goes through all scan lines
screenShake.loop2:
	inc a
	and $1F
	push af

	;call screenShake.waitScanline

	pop af

	push af
	sra a
	sra a ; this one
	ld hl, smallCurveLUT
	ld d, 0
	ld e, a
	add hl, de


	call waitHBlank
	
	ld a, [rSCX]
	add a, [hl]
	ld [rSCX], a
	pop af


	dec b
	jr nz, screenShake.loop2

	call wait
	call wait
	dec c
	jr nz, screenShake.loop1

	reti

	; waits until B = scanline
	; - Destroys: `AF`
screenShake.waitScanline:
	ld a, [rLY]
	cpl
	add a, 144
	cp b
	jr nz, screenShake.waitScanline
	ret


; ==============================================
;	Does nothing until the CPU enters H-Blank
;	- Inputs: `NONE`
;	- Destroys: `AF`
; ==============================================
waitHBlank:
	ld a, [rSTAT] ; lowest two bits are 00 in HBlank
	and %00000011
	jr nz, waitHBlank
	ret


; ==============================================
;	Deletes an element in DMA. Updates `DMAIndex`
;	- Inputs: `HL` = address to delete, 
;	- Destroys: `ALL`
; ==============================================
deleteElement:
	;GET_DMA_ADDRESS
	; get dest address
	di
	ld d, h
	ld e, l

	; get source address
	ld bc, 4	; is this quicker than 4 INC HL???
	add hl, bc

	; get BC size in future
	push hl

	; decrement index
	ld hl, DMAIndex
	dec [hl]
	ld bc, (-DMA_ADDRESS) & $FFFF
	add hl, bc ; essentially subtract
	ld b, h
	ld c, l
	pop hl

	; crappy way to do it
	ld bc, 160

	call memCpy
	reti
 

objectEnd:

SECTION "MENU", ROM0

menuStart:

; ==============================================
;	Pauses the game until the start button is pressed.
;	should replace with interrupt
;	- Destroys: `ALL`
; ==============================================
pauseGame::
	stringATWindow TXT_PAUSED, 7, 1

	playSoundEffect 10, SOUND_MENU_OPEN

	; scroll pause window
	di
	ld b, 8
	call scrollWindowUp
	ei

	call waitKey
	; main pause loop, i should condense this to use interrupts
pauseGame.loop:
	call scanJoypad
	halt
	bit KEY_START, a
	jr z, pauseGame.loop
	call waitKey

	; scroll pause window back to normal
	di
	ld b, 8
	call scrollWindowDown


	playSoundEffect 10, SOUND_MENU_OPEN
	reti

; ==============================================
;	Loops until all keys are not pressed.
;	must have interrupts enabled
;	- Destroys: `AF`, `C`
; ==============================================
waitKey:
	halt 
	halt
	call scanJoypad
	or a
	jr nz, waitKey
	ret

; ==============================================
;	uses the window to get a 4-byte longs string,
;	expects the window to be hidden and ENABLES interrupts
;	- Destroys: `ALL`
; ==============================================
stringMenu::
	; gotta disable so we don't redraw the score
	di

	; set up window
	ld a, 144
	ld [rWY], a

	; reset menu cursor
	xor a
	ld [cursorOffset], a
	
	call clearWindow
	
	stringATWindow TXT_HIGHSCORE, 1, 1
	stringATWindow TXT_START_CONFIRM, 20 - 10, 4

	; fills string with A
	MSET ALPHABET_BASE, stringBuffer, 4

	; zero the last byte
	xor a
	ld [stringBuffer + 3], a

	; draw stuff
	call stringMenu.draw

	call wait
	; draw bottom border
	MSET $5B, WINDOW_LOCATION + 5 * 32, 160 / 8
	
	; draw the top border
	MSET $5B, WINDOW_LOCATION, 160 / 8
	
	; scroll window into view
	ld b, 48
	call scrollWindowUp


stringMenu.loop:

	ld a, [rTIMA]
	bit 7, a
	call nz, stringMenu.flashText

	call scanJoypad

	bit KEY_RIGHT, a
	jr nz, stringMenu.right

	bit KEY_LEFT, a
	jr nz, stringMenu.left

	bit KEY_UP, a
	jp nz, stringMenu.up

	bit KEY_DOWN, a
	jp nz, stringMenu.down

	; if B, don't save
	bit KEY_B, a
	jr nz, .break

	bit KEY_START, a
	jr z, stringMenu.loop

	MCOPY stringBuffer, currentName, 4

	ld b, 48
	call scrollWindowDown
	reti

stringMenu.break:
	pop hl ; eat stack
	;lower window
	ld b, 48
	call scrollWindowDown
	; do nothing
	jp titleScreen

stringMenu.right:
	ld a, [cursorOffset]
	cp 2
	jr z, stringMenu.loop

	inc a
	ld [cursorOffset], a

	call waitKey
	call stringMenu.draw
	jr stringMenu.loop

stringMenu.left:
	ld a, [cursorOffset]
	or a
	jr z, stringMenu.loop
	dec a

	ld [cursorOffset], a
	call waitKey
	call stringMenu.draw
	
	jr stringMenu.loop

stringMenu.down:
	call stringMenu.helper
	
	ld a, [hl]
	cp ALPHABET_BASE + 28
	jr nc, stringMenu.loop

	inc a
	ld [hl], a

	call scanJoypad

	
	call stringMenu.delay

	call stringMenu.draw
	jp stringMenu.loop


; stinky wait loop
; destroys C and AF
stringMenu.delay:
	call scanJoypad

	ld c, 10
	; speed up if A button is pressed
	bit KEY_A, a
	jr nz, stringMenu.delayLoop
	ld c, 35
stringMenu.delayLoop:
	call wait
	dec c
	jr nz, stringMenu.delayLoop
	ret

stringMenu.helper:
	ld a, [cursorOffset]
	ld d, 0
	ld e, a

	ld hl, stringBuffer
	add hl, de
	ret

stringMenu.up:
	call stringMenu.helper
	
	ld a, [hl]
	cp ALPHABET_BASE
	jp z, stringMenu.loop

	dec a
	ld [hl], a

	
	call stringMenu.delay
	
	call stringMenu.draw
	jp stringMenu.loop

stringMenu.draw:
	
	; clear bottom arrow area
	call waitVBlank
	MSET 0, WINDOW_LOCATION + 3 + 32*4, 3 

	; clear top arrow area
	call waitVBlank
	MSET 0, WINDOW_LOCATION + 3 + 32*2, 3

	ld hl, WINDOW_LOCATION + 3 + 2*32
	; get arrow draw address
	ld a, [cursorOffset]
	ld d, 0
	ld e, a
	add hl, de ; gets the X coord


	; draws the arrow keys
	ld a, SPRITE_UP_ARROW
	ld [hl], a
	ld de, 32 * 2
	add hl, de
	ld a, SPRITE_DOWN_ARROW
	ld [hl], a

	; draws the final score 
	ld hl, score + 5
	ld de, WINDOW_LOCATION + 13 + 3 * 32
	call drawBCDNumber

	stringATWindow stringBuffer, 3, 3
	ret
	
; flashes some hoot on the screen that says "GAME OVER"
stringMenu.flashText:
	xor a
	ld [rTIMA], a
	
	ld hl, gameoverFlashTimer
	inc [hl]
	ld a, [hl]
	bit 4, a
	ret z

	xor a
	ld [hl], a

	ld hl, TXT_GAME_OVER
	ld de, WINDOW_LOCATION + 32 * 1 + 11
	ld b, 9
stringMenu.flashTextLoop:
	call waitVRAMReadable
	ld a, [de]
	xor [hl]
	ld [de], a
	inc de
	inc hl
	dec b
	ret z
	jr stringMenu.flashTextLoop
	

topRow:
	db $57, $58, $58, $58, $58, $58, $58, $58, $59
topRowEnd:
bottomRow:
	db $5A, $5B, $5B, $5B, $5B, $5B, $5B, $5B, $5C
bottomRowEnd:

sideRow:
	db $56, 0, 0, 0, 0, 0, 0, 0, $56
sideRowEnd:


; ==============================================
;	Draws an 8x8 border around the window.
;	Clears stuff that is already there.
;	Automatically waits for v-blank
;	- Inputs: `B` = height of window + 2
;	- Destroys: `ALL?`
; ==============================================
drawWindowBorder:
	push bc
	call clearWindow

	; draw bottom row
	pop bc
	push bc
	inc b
	sla b
	sla b
	sla b
	ld h, 0
	ld l, b
	add hl, hl ;HL = B * 32
	add hl, hl
	ld de, WINDOW_LOCATION
	add hl, de
	LOAD_DE_HL

	call waitVBlank
	ld hl, bottomRow
	ld bc, bottomRowEnd - bottomRow
	call memCpy

		; draw top row
	MCOPY topRow, WINDOW_LOCATION, topRowEnd - topRow

	call waitVBlank

	pop bc
	; B = number of times to run loop
	ld de, WINDOW_LOCATION + 32
drawWindowBorder.drawSides:
	push bc
	push de
	
	call waitVBlank
	ld bc, sideRowEnd - sideRow
	ld hl, sideRow
	call memCpy

	pop de
	pop bc
	ld hl, 32
	add hl, de
	LOAD_DE_HL
	dec b
	jr nz, drawWindowBorder.drawSides
	ret

STRTY EQU 144+8+24
STRTX EQU 64
titleScreenSprites:
	db STRTY, STRTX+0, $60, 3 ;S
	db STRTY, STRTX+8, $61, 4 ;H
	db STRTY, STRTX+16, $62, 3 ;O
	db STRTY, STRTX+24, $62, 4 ;O
	db STRTY, STRTX+32, $64, 3 ;T
	db STRTY, STRTX+40, $65, 4 ;Y

	db STRTY+10, STRTX+0, $66, 4 ;F
	db STRTY+10, STRTX+8, $67, 3 ;R
	db STRTY+10, STRTX+16, $68, 4 ;U
	db STRTY+10, STRTX+24, $69, 3 ;I
	db STRTY+10, STRTX+32, $64, 4 ;T
	db STRTY+10, STRTX+40, $65, 3 ;Y
titleScreenSpritesEnd:

; B = number of iterations
; A = something
; this is trash and it is undocumented
; how the poo does this work
scrollTitle:
	ld de, 4
.idkloop3:
	push af
.idkloop2:
	ld hl, DMA_ADDRESS

	; load C with the number of sprites
	ld c, (titleScreenSpritesEnd - titleScreenSprites) / 4
	; this loop decrease Y coord of each letter
.idkloop:

	dec [hl]

	add hl, de
	dec c
	jr nz, .idkloop

	push af
	and 1
	jr nz,.idk
	call waitVBlank

	call DMATransfer
.idk:
	pop af

	dec a
	jr nz, .idkloop2

	ld c, 3
	call wait
	dec c
	jr nz, @-4

	pop af
	dec a

	dec b
	jr nz, .idkloop3
	ret

; this routine is magical
; it uses `rTIMA` and updates the title screen.
; probably should be called in an interrupt to ensure smooth movement
; Destroys: `ALL`
animateTitleScreen:
	; if bit 7 is un-set, skip
	ld a, [rTIMA]
	bit 7, a
	ret z

	; reset timer
	xor a
	ld [rTIMA], a

	call waitVBlank

	; if we don't skip, increase some variable
	; the variable is some offset to the sine wave LUT
	ld hl, titleScreenTimer
	ld a, [hl]
	inc a
	and $3F
	ld [hl], a
	
	; rather than stretching f(x) from the 'sra a' instruction,
	; this only adds an offset to the letters if `A` is even
	; this way, we can slow it down without making the letters move drastically
	bit 0, a
	ret z

	; slows down movement
	sra a
	
	; get the Y amount to add to the tiles
	ld d, 0
	ld e, a
	ld hl, sinLUTBig
	add hl, de
	ld b, [hl] ; offset

	; this loop adds offsets to all of the letters in the title
	ld c, 12
	ld hl, DMA_ADDRESS
	ld de, 4
.updateTiles:
	ld a, [hl]
	add a, b
	ld [hl], a
	add hl, de
	dec c
	jr nz, .updateTiles
	
	; copy sprites to OAM
	jp DMATransfer



; ==============================================
;	Start up screen
;	- Destroys: `ALL`
; ==============================================
titleScreen::

	xor a ; no interrupts yet
	ldh [rIE], a

	ld a, 144
	ldh [rLYC], a

	; set up window
	ld a, 160-8*8
	ldh [rWX], a
	ld a, 144
	ldh [rWY], a

	; initialize title sprites
	call waitVBlank
	MCOPY titleScreenSprites, DMA_ADDRESS, titleScreenSpritesEnd - titleScreenSprites
	call DMATransfer
	
	; set scanline comparison
	ld a, 143 - 8
	ld [rLYC], a


	; enable interrupts in LCDSTAT
	ld hl, rSTAT
	set STATB_LYC, [hl]

	; enable LCDSTAT interrupts in IE
	ld a, IEF_LCDC
	ldh [rIE], a

	ei

	ld a, [isCGB]
	or a
	call z, fadeIn ; only works when not in CGB mode

	; draw window 8x8
	ld b, 5
	call drawWindowBorder


	; initialize palette
	call loadTitlePalettes


	
	
	; make them appear on screen
	ld b, 16
	ld a, 16
	call scrollTitle

	call wait

	; draw text
	stringATWindow TXT_PLAY, 2, 1
	stringATWindow TXT_SCORES, 2, 2
	stringATWindow TXT_ERASE, 2, 3
	stringATWindow TXT_HELP, 2, 4

	ld a, [isCGB]
	or a
	call nz, titleScreen.drawTheme


	; reset menu cursor
	xor a
	ld [cursorOffset], a

	; draw cursor
	call titleScreen.drawCursor
	
	xor a
	ld [titleScreenTimer], a
	ldh [rTIMA], a


	; actually show the window
	ld b, 8 * 7
	call scrollWindowUp

titleScreen.loop:

	halt 

	; this routine is such a miracle
	call animateTitleScreen

	call scanJoypad

	bit KEY_UP, a
	jr nz, titleScreen.up
	bit KEY_DOWN, a
	jr nz, titleScreen.down

	bit KEY_A, a
	jr z, titleScreen.loop

	; buzz
	playSoundEffect 10, SOUND_MENU_OPEN

	ld b, 4
	ld a, 18
	call scrollTitle
	
	; move window position
	ld b, 8 * 7
	call scrollWindowDown

	; maybe a LUT?
	ld a, [cursorOffset]
	dec a
	jp z, highscoreScreen
	dec a
	jp z, deleteSaveMenu
	dec a
	jp z, helpMenu
	dec a
	jp z, changeTheme ; only available on CGB
	
	; disable LCDSTAT scanline interrupt
	ld hl, rSTAT
	res STATB_LYC, [hl]

	; do EVERYTHING for the game
	call initGame

	jp mainLoop

titleScreen.down:
	ld hl, cursorOffset
	
	; if too far, then don't move the cursor
	ld a, [maxMenu]
	cp [hl]
	jp z, titleScreen.loop
	
	inc [hl]

	call titleScreen.drawCursor
	call waitKey
	playSoundEffect 10, SOUND_MENU_OPEN
	jp titleScreen.loop

titleScreen.up:
	ld hl, cursorOffset
	; if 0, don't move the cursor
	ld a, [hl]
	or a
	jp z, titleScreen.loop
	
	dec a
	ld [hl], a

	call titleScreen.drawCursor
	call waitKey
	playSoundEffect 10, SOUND_MENU_OPEN
	jp titleScreen.loop

;destroys `HL`, `A`, `DE`
titleScreen.drawCursor:

	call waitVBlank
	
	; clear cursor
	ld hl, WINDOW_LOCATION + 32 + 1
	ld b, 5 ; number of entries
	ld de, 32
titleScreen.eraseCursorLoop:
	xor a
	ld [hl], a
	add hl, de
	dec b
	jr nz, titleScreen.eraseCursorLoop

	ld a, [cursorOffset]
	add a, a	; x2
	add a, a	; x4
	ld h, 0
	ld l, a
	
	add hl, hl	; x8
	add hl, hl	; x16
	add hl, hl	; x32

	ld de, WINDOW_LOCATION + 32 + 1
	add hl, de

	ld [hl], $2B
	ret
.skip:
	; finally draw the cursor
	ld [hl], $2B
	pop hl
	ret



; ==============================================
;	Only called in CGB mode. draws the text allowing for light/dark theme
;	- Destroys: `AF`, `DE`, `HL`
; ==============================================
titleScreen.drawTheme:
	ld a, [currentTheme]
	or a
	jr nz, .darkTheme
	stringATWindow TXT_LIGHT, 2, 5
	ret
.darkTheme:
	stringATWindow TXT_DARK, 2, 5
	ret


; ==============================================
;	A help menu. Shows up on the right side of the title screen
;	- Destroys: `ALL`
; ==============================================
helpMenu:
	ld a, 7
	ld [rWX], a

	call wait
	; draw window borders
	MCOPY .topRow, WINDOW_LOCATION + 9 + 32, .topRowEnd - .topRow
	MCOPY .bottomRow, WINDOW_LOCATION + 9 + 5 * 32, .bottomRowEnd - .bottomRow

	stringATWindow TXT_HELP_TITLE, 11, 0
	stringATWindow TXT_HELP_MENU1, 9, 2
	stringATWindow TXT_HELP_MENU2, 9, 3
	stringATWindow TXT_HELP_MENU3, 9, 4

	ld b, 8 * 7
	call scrollWindowUp

helpMenu.loop:
	halt

	call scanJoypad
	bit KEY_B, a
	jr z, helpMenu.loop

	ld b, 8 * 7
	call scrollWindowDown

	jp titleScreen

; these are 11 tiles long
.topRow:
	db $57, $58, $58, $58, $58, $58, $58, $58, $58, $58, $59
.topRowEnd:
.bottomRow:
	db $5A, $5B, $5B, $5B, $5B, $5B, $5B, $5B, $5B, $5B, $5C
.bottomRowEnd:

; ==============================================
;	A menu that with prompt the user with an option to delete highscores
;	- Destroys: `ALL`
; ==============================================
deleteSaveMenu:
	
	; set window position
	ld a, 7
	ld [rWX], a
	
	stringATWindow TXT_ERASE_SAVE, 9, 0
	stringATWindow TXT_YES, 10, 2
	stringATWindow TXT_TEST, 10, 3
	stringATWindow TXT_NO, 10, 4

	call waitVBlank
	MCOPY topRow, WINDOW_LOCATION + 10 + 32 * 1, topRowEnd - topRow
	MCOPY bottomRow, WINDOW_LOCATION + 10 + 32 * 5, bottomRowEnd - bottomRow

	ld b, 8 * 7
	call scrollWindowUp

deleteSaveMenu.loop:
	call scanJoypad

	bit KEY_B, a
	jr nz, deleteSaveMenu.skipDelete

	bit KEY_A, a
	jr z, deleteSaveMenu.loop

	call enableRAM
	call clearHighscores
	call disableRAM

	call waitKey
deleteSaveMenu.skipDelete:

	ld b, 8 * 7
	call scrollWindowDown

	jp titleScreen


; this is legit only used once. uses memSet. quite dumb of a routine
clearHighscores:
	ld hl, C_RAM_BASE
	ld bc, C_RAM_SIZEOF
	xor a
	jp memSet


; ==============================================
;	Runs the highscore screen this will need reform
;	- Destroys: `ALL`
; ==============================================
highscoreScreen::
	ld b, 8
	call drawWindowBorder
	
	call enableRAM

	; check for valid check sum
	; if it is invalid, zero everything
	ld hl, C_RAM_BASE
	ld bc, C_RAM_SIZEOF
	call createCheckSum
	ld a, [C_RAM_CHECKSUM]
	cp d
	call nz, clearHighscores

	ld hl, C_RAM_HIGHSCORE ;scoreEntry
	ld de, WINDOW_LOCATION + 32 + 1 ; (1, 1)
	ld b, MAX_HIGHSCORES
highscoreScreen.drawLoop:

	; if string is blank, stop drawing
	ld a, [hl]
	or a
	jr z, highscoreScreen.finished

	call waitVBlank
	push de
	push hl
	call drawString
	pop hl
	ld de, 4
	add hl, de ; increase HL by 4 to point to the BCD score
	
	pop de
	push hl

	ld hl, 33
	add hl, de
	LOAD_DE_HL ; increase window X and Y position by 1

	pop hl

	push de
	push hl
	push bc
	call drawBCDNumberLEFT
	pop bc
	pop hl
	
	; increase HL by six to point to the next entry
	ld de, 6
	add hl, de
	pop de


	; increase DE by 31
	push hl
	ld hl, 30
	add hl, de
	LOAD_DE_HL
	inc de
	pop hl

	dec b
	jr nz, highscoreScreen.drawLoop

highscoreScreen.finished:
	; gotta be a good boy
	call disableRAM

	ld b, 8*10
	call scrollWindowUp
	call waitKey

highscoreScreen.loop:
	call scanJoypad

	halt

	bit KEY_B, a
	jr z, highscoreScreen.loop

	playSoundEffect 10, SOUND_MENU_OPEN

	ld b, 8*10
	call scrollWindowDown

	jp titleScreen


; ==============================================
;	Checks for an open highscore slot. Needs modification to move lower elements downward
;	- uses memory location `score` for the data
;	- Outputs: `A` = index of highscore in order of magnitude. returns a higher number than `MAX_HIGHSCORES` if no room.
;	`B` = number of scores below the one being added
;	- Destroys: `ALL`
; ==============================================
addHighScore:
	ld de, C_RAM_HIGHSCORE + 4
	ld b, MAX_HIGHSCORES
addHighScore.loop:
	ld hl, score
	push de
	push bc
	call cpBCDNumber
	pop bc

	jr nc, addHighScore.keep
addHighScore.continue:
	pop de

	; add 10 to DE to look at next score
	ld hl, 10
	add hl, de
	LOAD_DE_HL

	dec b
	jr nz, addHighScore.loop
	; just return some number that will get flagged as invalid
	ld a, MAX_HIGHSCORES+1
	ld b, 0
	ret

addHighScore.keep:
	pop hl
	ld a, MAX_HIGHSCORES
	sub b
	ret

menuEnd:

SECTION "GAME", ROM0

; probably destroys all.
; it moves the player right
moveRight:
	ld hl, DMA_ADDRESS+3

	; set player direction
	res OAMB_XFLIP, [hl]
	dec hl

	call animatePlayer
	
	; increase player X pos
	ld a, [hl]
	cp 160
	ret nc
	inc [hl]
	ret
	
; switches between the two character sprites
; HL = pointer to character tile
; Destroys: `AF`, HL=HL-1
animatePlayer:
	ld a, [hl]
	sra a
	inc a
	and 1
	sla a
	inc a
	ld [hl-], a
	ret


; probably destroys all.
; it moves the player right
moveLeft:
	ld hl, DMA_ADDRESS+3

	; set player direction
	set OAMB_XFLIP, [hl]
	dec hl
	
	call animatePlayer

	ld a, [hl]
	cp 8
	ret c
	dec [hl]
	ret 

SECTION "graphics", ROM0

; draws the score to the window.
; probs destroys everything
drawScore::
	stringATWindow TXT_SCORE, 0, 0
	ld hl, score + 5
	ld de, $9C00 + 5 + 6
	jr drawBCDNumber


; ==============================================
; zeros out the window
;	- Inputs: `NONE`
;	- Destroys: `AF`, `B`, `HL`, `DE`, A = B = 0
; ==============================================
clearWindow::
	ld hl, WINDOW_LOCATION
	ld b, 0 ; run loop 256 times
clearWindow.loop:
	call waitVRAMReadable
	xor a
	ld [hl+], a

	dec b
	jr nz, clearWindow.loop
	ret

; ==============================================
; zeros out the DMA data. initates a DMA transfer
;	- Inputs: `NONE`
;	- Destroys: `AF`, `BC`, `HL`, `DE`
; ==============================================
clearDMA:
	call waitVRAMReadable
	MSET 0, DMA_ADDRESS, 160
	jp DMATransfer



; ==============================================
; Moves the window towards the TOP of the screen
;	- Inputs: `B` = amount to scroll
;	- Destroys: `AF`, `HL`, `DE`, `B` = 0
; ==============================================
scrollWindowUp:
	ld hl, rWY
	ld de, rTIMA
	; reset timer
	xor a
	ld [de], a

.loopScrollUp:
	ld a, [de]
	cp SCROLL_SPEED
	jr c, .loopScrollUp
	
	; reset timer
	xor a
	ld [de], a

	dec [hl]
	dec b
	jr nz, .loopScrollUp
	ret


; ==============================================
; Moves the window towards the BOTTOM of the screen
;	- Inputs: `B` = amount to scroll
;	- Destroys: `AF`, `HL` = rWY, `B` = 0
; ==============================================
scrollWindowDown:
	ld hl, rWY
	ld de, rTIMA
	xor a
	ld [de], a
.loopScrollDown:
	ld a, [de]
	cp SCROLL_SPEED
	jr c, .loopScrollDown

	; reset timer
	xor a
	ld [de], a
	
	inc [hl]
	dec b
	jr nz, .loopScrollDown
	ret

; ==============================================
; waits until the scanline is 144 (beginning of vblank)
;	- Inputs: `NONE`
;	- Destroys: `AF`
; ==============================================
wait:
	ld a, [rLY]
	cp 144
	ret z
	jr wait

; ==============================================
; draws a 6 digit BCD-encoded number. Waits for a valid time to write
;	- Inputs: `HL` = pointer to END number, `DE` = pointer to area to draw;
;		it is right-aligned
;	- Destroys: `AF`, `B`, `HL`, `DE`
; ==============================================
drawBCDNumber:
	ld b, 6
drawBCDNumber.loop:
	call waitVRAMReadable
	ld a, [hl-]

	add a, NUMBER_BASE
	ld [de], a
	dec de
	dec b
	jr nz, drawBCDNumber.loop
	ret

; ==============================================
; draws a 6 digit BCD-encoded number. Waits for a valid time to write
;	- `THIS SHOULD BE THE ONLY ROUTINE USED BECAUSE IT DRAWS LEFT TO RIGHT LIKE A NORMAL DRAWING ROUTINE`
;	- Inputs: `HL` = pointer to START number, `DE` = pointer to area to draw;
;		it is left-aligned
;	- Destroys: `AF`, `B`, `HL`, `DE`
; ==============================================
drawBCDNumberLEFT:
	ld b, 6
.loop:
	call waitVRAMReadable
	ld a, [hl+]

	add a, NUMBER_BASE
	ld [de], a
	inc de
	dec b
	jr nz, .loop
	ret

; ==============================================
; increments a 6 digit BCD-encoded number using recursion
; does not account for overflow on 6th digit
;	- Inputs: `HL` = pointer to number
;	- Destroys: `AF`, `HL`
; ==============================================
incBCDNumber:
	ld a, [hl]
	inc a
	cp 10
	jr c, incBCDNumber.fine

	; if we overflow

	push hl
	; increment the next digit
	dec hl
	call incBCDNumber

	pop hl

	; reset current digit
	xor a
incBCDNumber.fine:
	ld [hl], a
	ret

; ==============================================
; compares a 6 digit BCD-encoded number using recursion
;	- Inputs: `HL` = pointer to BEGINNING of 1st number,
;	`DE` = pointer to BEGINNING of 2nd number
;	- Outputs:
;		 `NZ` if number 1 is greater than number 2,
;		 `C`  if number 1 is less than number 2,
;		 `Z`  if number 1 equals number 2
;	- Destroys: `A`, `BC`, `DE`, `HL`
; ==============================================
cpBCDNumber:
	ld b, 6
cpBCDNumber.loop:
	ld a, [de] ; second
	ld c, a
	ld a, [hl+] ; first
	inc de
	dec b
	ret z

	cp c
	ret c
	ret nz
	jr cpBCDNumber.loop


waitOAMReadable:
	ld hl, rSTAT
.loop1:
	bit 1, [hl]       ; Wait until Mode is -NOT- 0 or 1
	jr z, .loop1
.loop2:
 	bit 1, [hl]      ; Wait until Mode 0 or 1 -BEGINS-
	jr nz, .loop2 
	ret


; ==============================================
; sets (x, y) position of a DMA sprite.
; enables interrupts
;	- Inputs: `A` - index,
;		`B` = x, `C` = y
;	- Destroys: `AF`, `HL`, `DE`
; ==============================================
setSpritePos::
	di
	GET_DMA_ADDRESS
	ld [hl], c
	inc hl
	ld [hl], b
	reti

; ==============================================
; sets sprite tile of a DMA sprite.
; enables interrupts
;	- Inputs: `A` - index,
;		`B` = tile
;	- Destroys: `AF`, `HL`, `DE`
; ==============================================
setSpriteTile::
	di
	GET_DMA_ADDRESS
	inc hl
	inc hl
	ld [hl], b
	reti

; ==============================================
; sets sprite flags of a DMA sprite.
; enables interrupts
;	- Inputs: `A` = index,
;		`B` = flags
;	- Destroys: `AF`, `HL`, `DE`
; ==============================================
setSpriteFlag::
	di
	GET_DMA_ADDRESS
	inc hl
	inc hl
	inc hl
	ld [hl], b
	reti


; ==============================================
; dramatic fade-in animation.
;	- enables interrupts
;	- Destroys: `AF`, `BC`, `D`
; ==============================================
fadeIn:
	di
	xor a
	ld [rBGP], a
	ld [rOBP0], a
	ld b, 4
	ld c, PALETTE
fadeIn.loop
	sra c
	rr a
	sra c
	rr a
	ld [rBGP], a
	ld [rOBP0], a
	ld [rOBP1], a
	ld d, 100
fadeIn.wait:
	call wait
	dec d
	jr nz, fadeIn.wait
	dec b
	jr nz, fadeIn.loop
	reti

SECTION "UTILITY", ROM0

; ==============================================
;	creates a checksum using addition
;	- Inputs: `BC` = size of memory, `HL` = pointer to memory
;	- Outputs: `A` = `D` = checksum value
;	- Destroys: `F`, `BC`, `HL`
; ==============================================
createCheckSum:
	ld d, 0
createCheckSum.loop:
	ld a, [hl+]
	add a, d
	ld d, a

	dec bc
	ld a, b
	or c
	jr nz, createCheckSum.loop
	ld a, d
	ret


; ==============================================
;	enables cart RAM at $A000-$A7FF for reading/writing
;	- Destroys: `AF`
; ==============================================
enableRAM:
	ld a, $0A
	ld [0000], a
	ret

; ==============================================
;	disables cart RAM
;	- Destroys: `F`, `A` = 0
; ==============================================
disableRAM:
	xor a
	ld [0000], a
	ret



; ==============================================
;	Returns a psuedorandom number into `HL`, `A` = `L`
;	- Destroys: `AF`
; ==============================================
xrnd::
	ld a, [randSeed]     ; seed must not be 0
	ld h, a
	ld a, [randSeed + 1]
	ld l, a

	ld a,h
	rra
	ld a,l
	rra
	xor h
	ld h,a
	ld a,l
	rra
	ld a,h
	rra
	xor l
	ld l,a
	xor h
	ld h,a

	; re-randomize seed
	ld [randSeed], a
	ld a, l
	ld [randSeed + 1], a
	ret

; ==============================================
; sets up the game
;	- Destroys: `ALL`
; ==============================================
initGame::

	; reset variables
	xor a
	ld [fruitSpawnTimer], a
	ld [fruitNumber], a
	ld [birdNumber], a
	ld [DMAIndex], a

	
	; load in-game palettes
	call loadFruitPalettes

	; randomize the first byte of seed
	; but makes sure that the seed is never 0
	ld a, [rTIMA]
	or a
	jr nz, @+3
	inc a
	ld [randSeed], a
	
	; clear score
	MSET 0, score, 6
	
	; set up window
	ld a, 7
	ld [rWX], a
	ld a, 144  ; this is off screen but will get scrolled onto
	ld [rWY], a

	call clearWindow

	; clear DMA
	call waitVBlank
	MSET 0, DMA_ADDRESS + 4, 160

	; set up the character
	xor a
	ld b, 160 / 2
	ld c, CHAR_Y
	call setSpritePos

	xor a
	ld b, %00000001
	call setSpriteFlag

	
	xor a
	ld b, SPRITE_CHAR
	call setSpriteTile
	
	call DMATransfer

	ld a, IEF_VBLANK; enable V-Blank interrupt
	ldh [rIE], a

	di
	ld b, 8
	call scrollWindowUp

	
	reti

; ==============================================
; loads a map to the SCX, SCY viewpoint. 20x16 array
;	- Inputs: `DE` = pointer to map
;	- Destroys: `ALL`
; ==============================================
loadMap::
	ld hl, $98E6
	ld c, 16
.loadMapY:
	ld b, 20
.loadMapX:
	ld a, [de]
	dec a
	ld [hl+], a
	inc de
	dec b
	jr nz, .loadMapX
	ld a, c
	ld bc, 12
	add hl, bc
	ld c, a
	dec c
	jr nz, .loadMapY
	ret 


; ==============================================
; draws a string onto the bg at (0, 0)
;	- does not check for v-blank
;	- Inputs: `HL` = string, `DE` = pointer to draw location
;	- Destroys: `AF`, `DE`, `HL`
; ==============================================
drawString::
	call waitVRAMReadable
	ld a, [hl+]
	or a
	ret z
	ld [de], a
	inc de
	jr drawString

; ==============================================
; fetches D-PAD data into upper word of `A`
; and BTNs into lower word
;	- Destroys: `AF`, `C`
; ==============================================
scanJoypad:
	ld a, P1F_GET_DPAD
	ldh [rP1], a
	ldh a, [rP1]
	ldh a, [rP1]
	cpl
	and $0F
	swap a
	ld c, a
	ld a, P1F_GET_BTN
	ldh [rP1], a
	ldh a, [rP1]
	ldh a, [rP1]
	cpl
	and $0F	
	or c
	ret

; ==============================================
; does a '16-bit' subtraction of `HL` and `DE`
;	- Ouputs: `HL` = HL-DE
;	- Destroys: `AF`
; ==============================================
sub_HL_DE:
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a
	ret


; ==============================================
; copies data from `HL` to `DE` with a size of `BC`. essentially a LDDR
;	- Destroys: `AF`, `BC`, `DE`, `HL`
; ==============================================
memCpyDecrement:
	ld a, [hl-]
	ld [de], a
	dec de
	dec bc
	ld a, b
	or a, c
	jr nz, memCpyDecrement
	ret

; ==============================================
; copies data from `HL` to `DE` with a size of `BC`
;	- Destroys: `AF`, `BC`, `DE`, `HL`
; ==============================================
memCpy:
	ld a, [hl+]
	ld [de], a
	inc de
	dec bc
	ld a, b
	or a, c
	jr nz, memCpy
	ret

; ==============================================
; clears data from `HL` with a size of `BC` using `A`
;	- Destroys: `AF`, `BC`, `HL`, `D`
; ==============================================
memSet:
	ld d, a
.loop:
	ld [hl], d
	inc hl
	dec bc
	ld a, b
	or a, c
	jr nz, .loop
	ret

; ==============================================
; waits until VBlank starts
;	- Destroys: `AF`
; ==============================================
waitVBlank:
	ldh a,[rLY]
	cp a, 144
	jr c, waitVBlank
	ret


; ==============================================
; waits until VRAM is accessible, aka vblank.
; why does this routine work but not the other.
; the other should be used instead of this
;	- Destroys: `AF`
; ==============================================
waitVRAMReadable:
	ldh a,[rSTAT]
	and 3
	or a
	ret z
	cp %01
	jr nz, waitVRAMReadable
	ret

SECTION "VARIABLES", WRAM0[$C000]

; used for the beginning to load special palettes
; - 8-bit
isCGB:
	ds 1

; used as the max number of items in the title screen
; - 8-bit
maxMenu:
	ds 1

; only used in CGB mode
; - NZ is dark ($FF)
; - Z is light (0)
currentTheme:
	ds 1

; timer incremented every v-blank.
; Used to time the creation of a new fruit
; - 8-bit
fruitSpawnTimer:
	ds 1

; timer incremented every v-blank.
; Used to time the creation of a new bird
; - 8-bit
birdSpawnTimer:
	ds 1

; index to the free DMA entry for all objects: bullets, birds, & fruits
; - 8-bit
DMAIndex:
	ds 1

; used to scroll the bottom of the screen
; - union with `fruitNumber`
; - 8-bit
titleScreenScroll:
; number of fruits that are spawned and active
; - 8-bit
fruitNumber:
	ds 1


; used to scroll the bottom of the screen
; - 8-bit
rSCXBackup:
	ds 1
; number of birds that are spawned and active
; - 8-bit
birdNumber:
	ds 1

; holds a frame when a bullet was last shot.
; used to prevent bullets from being shot too close to each
; - 8-bit
lastBullet:
	ds 1

; seed for RNG
; - 16-bit
randSeed:
	ds 2

currentName:
	ds 4
score:
	ds 6


; holds position in a menu.
; used in the title screen menu and `stringMenu`
; - 8-bit
cursorOffset:
	ds 1

; used to control the flashing of 'game over' text in `stringMenu`
; - 8-bit
gameoverFlashTimer:
; used for bouncing the title screen. specifically in `animateTitleScreen`
; - 8-bit
titleScreenTimer:
	ds 1

; stores the highscores, needs to be fetched from cart RAM
highscoreTable:
	ds MAX_HIGHSCORES * (4 + 2)

; temporary string buffer used for save data
stringBuffer:
	ds 4

SECTION "DMA", WRAM0[DMA_ADDRESS]
	ds 40 * 4 * 2

SECTION "DATA", ROM0

dataStart:

; ==============================================
; the part that is put in HRAM and stuff
; - Destroys: `AF`
; ==============================================
dma_routine:
	ld a,DMA_ADDRESS / 256
	ldh [rDMA], a
	; initiate a wait
	ld a, $28
.wait:
	dec a
	jr nz, .wait
	ret
dma_routine_end:


; 20x16 array
mapData:
	db 1,1,1,1,27,28,28,28,28,29,23,24,24,24,25,27,28,28,29,1, 28,28,29,1,22,24,1,1,1,26,32,30,31,1,27,1,24,1,1,29, 1,1,26,27,1,1,1,1,1,1,29,21,27,28,1,1,1,1,1,26, 28,1,26,22,1,1,1,1,24,1,1,29,22,24,1,1,1,1,1,26, 1,1,26,23,1,27,29,24,24,24,24,25,22,1,1,1,1,24,1,25, 1,24,26,1,23,22,32,30,31,1,1,21,23,24,24,24,24,24,25,1, 24,24,1,29,1,1,1,21,1,1,1,21,1,1,32,30,31,1,1,1, 32,30,22,26,1,1,1,21,1,81,82,83,1,1,1,21,1,1,1,1, 29,21,23,25,1,27,29,21,1,1,1,21,1,1,1,21,1,1,1,1, 25,84,31,1,1,23,25,21,1,1,1,84,85,86,1,21,1,1,1,1, 32,83,1,1,1,1,32,83,1,1,1,21,1,1,1,21,1,1,1,1, 1,21,1,1,1,1,1,21,1,1,1,21,1,1,1,21,1,1,1,1, 1,21,1,1,1,1,1,21,1,1,1,21,1,1,1,84,85,86,1,1, 1,21,1,1,1,1,1,21,1,1,1,21,1,1,1,21,1,1,1,1, 1,21,1,1,1,1,1,21,1,1,1,20,1,1,1,21,1,1,1,1, 17,18,19,1,1,1,17,18,19,1,17,18,19,1,17,18,19,1,1,1
mapDataEnd:


; this is the derivative of 10sin(x/1.6pi)
sinLUT:
	db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0
	db -0, -0, -0, -0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 0
sinLUTEnd:

; this is the derivative of sin(x/1.6/pi)
sinLUTBig:
	 db 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1
sinLUTBigEnd:

; used for displacement of the 'shootyfruity' tile
; this is the derivative of 128x^2/625 from [0, 30]
; this LUT can change size uneffected
titleLUT:
	db 0, 0, 0, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4, 5, 5, 6, 6, 6, 7, 7, 8, 8, 9, 9, 9, 10, 10, 11, 11, 11, 12
titleLUTEND:


; really small curve used for shaking the screen
smallCurveLUT:
REPT 2
	db 1, 2, 1, 0, -1, -2, -1, 0
ENDR

; TEXT DATA

TXT_PLAY:
	db "PLAY", 0
TXT_SCORES:
	db "SCORES", 0
TXT_ERASE_SAVE:
	db "ERASE SAVE?", 0
TXT_SCORE:
	db "SCORE:", 0
; says "PAUSED"
TXT_PAUSED:
	db "PAUSED", 0
TXT_HIGHSCORE:
	db "HIGHSCORE", 0
TXT_ERASE:
	db "ERASE", 0
TXT_YES:
	db $56, "aYES   ", $56, 0
TXT_NO:
	db $56, "bNO    ", $56, 0
TXT_TEST:
	db $56, "       ", $56, 0
TXT_GAME_OVER:
	db "GAME OVER", 0
TXT_HELP:
	db "HELP", 0
TXT_HELP_TITLE:
	db "BUTTONS", 0
TXT_HELP_MENU1:
	db $56, "aSHOOT   ",$56, 0
TXT_HELP_MENU2:
	db $56, "bBACK    ", $56, 0
TXT_HELP_MENU3:
	db $56, "strPAUSE ", $56, 0
TXT_START_CONFIRM:
	db "strCONFIRM", 0

;CGB
TXT_LIGHT:
	db "lLIGHT", 0
TXT_DARK:
	db "dDARK", 0


; SOUND EFFECTS

SOUND_BULLET:		; NR 10-14. 'Sound mode 1'
	db $16, $86, $73, $78, $86
SOUND_MENU_OPEN:	; NR 10-14. 'Sound mode 1'
	db $30, $91, $43, $06, $87
SOUND_BIRD_HIT:		; NR 41-44. 'Sound mode 4'
	db $3A, $F1, $70, $C0


tileData:
	INCBIN "tiles.2bpp"
tileDataEnd:
dataEnd:

DATA_SIZE	EQU dataEnd - dataStart
MAIN_SIZE	EQU mainEnd - mainStart
OBJECT_SIZE	EQU objectEnd - objectStart
MENU_SIZE	EQU menuEnd - menuStart

PRINTT "DATA Size:"
PRINTI DATA_SIZE
PRINTT " bytes\n"

PRINTT "MAIN Size:"
PRINTI MAIN_SIZE
PRINTT " bytes\n"

PRINTT "OBJECT Size:"
PRINTI OBJECT_SIZE
PRINTT " bytes\n"

PRINTT "MENU Size:"
PRINTI MENU_SIZE
PRINTT " bytes\n\n"

PRINTT "TOTAL SIZE:"
PRINTI DATA_SIZE + MAIN_SIZE + OBJECT_SIZE + MENU_SIZE
PRINTT " bytes"