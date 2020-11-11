; turns off the VRAM bank
DISABLE_VRAM_BANK: MACRO
	xor a
	ld [rVBK], a
ENDM

; turns on the VRAM bank
ENABLE_VRAM_BANK: MACRO
	ld a, 1
	ld [rVBK], a
ENDM

; random colors
BG_COL				EQU $0000
L_GRAY_COL			EQU $6F7B
TXT_COL				EQU L_GRAY_COL ; $7D20 ; a really nice blue


; bg palettes
TREE_PALETTE_BG		EQU 1 ; BG0
GRASS_PALETTE_BG	EQU 2 ; BG1
LEAF_PALETTE_BG		EQU 3 ; BG2

BGPAL_0	EQU 0	; default
BGPAL_1	EQU 1	; tree
BGPAL_2	EQU 2	; grass
BGPAL_3	EQU 3	; leaves
BGPAL_4	EQU 4	; grayscale
BGPAL_5	EQU 5	; unused
BGPAL_6	EQU 6	; unused
BGPAL_7	EQU 7	; unused



OBJPAL_0	EQU 0	; default: red, dark red, green
OBJPAL_1	EQU 1	; character
OBJPAL_2	EQU 2	; bird (grayscale)
OBJPAL_3	EQU 3	; red title screen		; watermelon in-game
OBJPAL_4	EQU 4	; green title screen	; pineapple in-game
OBJPAL_5	EQU 5
OBJPAL_6	EQU 6
OBJPAL_7	EQU 7



; ==============================================
; loads a palette from HL to the objwct palette.
; index is where ever it was before
;	- Destroys: `AF`, `B`, `HL`
; ==============================================
loadOBPalette:
	call waitVRAMReadable
	ld a, [hl+]
	ldh [$FF6B], a
	dec b
	jr nz, loadOBPalette
	ret

; ==============================================
; loads a palette from HL to the background palette.
; index is where ever it was before
;	- Destroys: `AF`, `B`, `HL`
; ==============================================
loadBGPalette:
	call waitVRAMReadable
	ld a, [hl+]
	ldh [$FF69], a

	dec b
	jr nz, loadBGPalette
	ret

; ==============================================
; changes all leaves in the map to be green rather than have
; the palette of a tree.
; VRAM banking must be off
;	- Destroys: `ALL`
; ==============================================
changeLeafPalette:
	ld hl, $9800
	ld bc, $1F * $1F
.loop:
	ld a, [hl]
    cp $55
    jr z, .special
	cp $15
	jr c, .skip
	cp $1D
	jr nc, .skip

	ENABLE_VRAM_BANK

	ld a, LEAF_PALETTE_BG
	ld [hl], a

	DISABLE_VRAM_BANK
.skip:
	inc hl
	dec bc
    ld a, b
    or c
	jr nz, .loop
	ret
    
.special:
    ENABLE_VRAM_BANK
    
    xor a
    ld [hl], a

    DISABLE_VRAM_BANK
    jr .skip

; ==============================================
; this routine initializes stuff with a gameboy color.
; load palettes and proper tiles
;	- Destroys: `ALL`
; ==============================================
CGBMode:

	; load sprite palettes. i could just make B 24 any only run once
	ld b, 8
	ld hl, colorOBJ0Palette
	call loadOBPalette

	ld b, 8
	ld hl, colorOBJ1Palette
	call loadOBPalette

	; copies bird and title palette
	ld b, 16
	ld hl, colorGrayscale
	call loadOBPalette

	
	ld b, OBJPaletteEnd - colorOBJ4Palette
	ld hl, colorOBJ4Palette
	call loadOBPalette

	
	ld b, colorBGPaletteEnd - colorBGPalette
	ld hl, colorBGPalette
	call loadBGPalette

	; load grayscale palette to bg
	ld b, 8
	ld hl, colorInvertGrayscale
	call loadBGPalette

	; enable VRAM bank
	ld a, 1
	ld [rVBK], a

	; set tree palettes
	ld hl, $9800 + 32 * 7 + 6
	ld bc, $1F4
	call memSet

	; set ground palette
	ld a, GRASS_PALETTE_BG
	ld bc, 32
	call memSet

 	; set grayscale for the bottom row
	ld a, BGPAL_4
	ld c, 38
	call memSet

	DISABLE_VRAM_BANK

	call changeLeafPalette
	

	; re-do ground with special tiles
	MSET SPRITE_GROUND_CGB, $9AE6, 160 / 8
	
	ret

; ==============================================
; call before showing the game to load special fruit palettes
;	- Destroys: `ALL`
; ==============================================
loadTitlePalettes:
	ld a, [isCGB]
	or a
	ret z

	ld a, (OBJPAL_3 * 8) | ($80)	; first color of OBJ2 palette
	ldh [$FF6A], a
	ld hl, colorOBJ3Palette
	ld b, 16 ; load two palettes
	call loadOBPalette
	
	ret

; ==============================================
; call before running the game to load special fruit palettes
;	- Destroys: `ALL`
; ==============================================
loadFruitPalettes:
	ld a, [isCGB]
	or a
	ret z
	
	ld a, (OBJPAL_3 * 8) | ($80)	; first color of OBJ2 palette
	ldh [$FF6A], a
	ld hl, colorMelonPalette
	ld b, 16 ; load two palettes
	call loadOBPalette
	
	ret


; called from `titleScreen` to swap palettes
changeTheme:
	ld a, [currentTheme]
	cpl 
	ld [currentTheme], a
	or a
	call z, .darkTheme
	call nz, .lightTheme

	ld a, $80
	ldh [rBCPS], a

	ld b, colorBGPaletteLightEnd - colorBGPaletteLight

	call loadBGPalette

	ld a, [currentTheme]
	or a
	jr z, .darkTheme2
.lightTheme2:
	ld hl, colorGrayscale
	ld b, 8
	call loadBGPalette

	jp titleScreen

.darkTheme2:
	ld hl, colorInvertGrayscale
	ld b, 8
	call loadBGPalette
	
	jp titleScreen

.darkTheme:
	ld hl, colorBGPalette
	ret
.lightTheme:
	ld hl, colorBGPaletteLight
	ret

; a string that has all fruits and fills the entire row
TXT_FRUITS:

POOPY = 0
REPT 32
	db SPRITE_FRUIT + POOPY
POOPY = (POOPY + 1) & 7
ENDR
	db 0



;dark green:	1A45
;light green:	3761
;pink:			24F7
;dark blue:	7CE0 
; default dark mode
colorBGPalette:
; default palette (menus)
;		       green	brown	
	dw	BG_COL,	$03E2,	$1972,	TXT_COL
; tree trunk palette
;		    	gold	brown	Dred
	dw	BG_COL,	$0EDD,	$1972,	$0007
; grass palette
;		Lbrown	green	Dbrown	Dgreen
	dw	$1972,	$03E2,	$0CED,	$0540
; leaf palette
;				Dgreen	green	Dgreen
	dw	BG_COL,	$0202,	$03E2,	$0202
colorBGPaletteEnd:


; light mode
colorBGPaletteLight:
; default palette (menus)
;		       green	brown	
	dw	TXT_COL,$03E2,	$1972,	BG_COL
; tree trunk palette
;		    	gold	brown	Dred
	dw	TXT_COL,$0EDD,	$1972,	$0007
; grass palette
;		Lbrown	green	Dbrown	Dgreen
	dw	$1972,	$03E2,	$0CED,	$0540
; leaf palette
;				unused	green	unused
	dw	TXT_COL,$FFFF,	$0202,	$FFFF
colorBGPaletteLightEnd:



; creates a new sprite palette.
; And creates a label called END`palette name`
; - `Parameters:` `palette name`, `color 1`, `color 2`, `color 3`
NEW_BG_PAL: MACRO
\1:
	dw \2, \3, \4, \5
END\1:
ENDM

; creates a new sprite palette.
; And creates a label called END`palette name`
; - `Parameters:` `palette name`, `color 1`, `color 2`, `color 3`
NEW_SPR_PAL: MACRO
\1:
	dw $FFFF, \2, \3, \4
END\1:
ENDM

; inversed grayscale
	NEW_BG_PAL colorInvertGrayscale, $0000, $2108, $5AD6, $FFFF

; apple, cherry, and pineapple palette (watermelon too?)
;								 red	Dred	Dgreen
	NEW_SPR_PAL colorOBJ0Palette, $043F, $000B, $1A45


; character palette
;									blue	tan		purp eyes
	NEW_SPR_PAL colorOBJ1Palette,	$7567,	$3EBB,	$2C0B

;	bird palette					Lgray	Dgray	black
	NEW_SPR_PAL colorGrayscale,		$5AD6,	$2108,	$0000

; title palette, kinda wasteful, half unused
;									unused	Lred	red
	NEW_SPR_PAL colorOBJ3Palette,	$FFFF,	$002F,	$001F
; title pt2									Lgreen	Dgreen
	NEW_SPR_PAL colorOBJ4Palette,	$FFFF,	$0202, $03E2

;  peach							tan		pink	Dgreen
	NEW_SPR_PAL colorOBJ5Palette,	$3EBB,	$DCDB,	$1A45 

; banana, pear, and orange			yellow	Dyellow	brown
	NEW_SPR_PAL colorOBJ6Palette,	$03FF,	$0E10,	$1972 

; orange							orange	Lred	Dgreen
	NEW_SPR_PAL colorOBJ7Palette,	$01DF,	$0033,	$1A45 

OBJPaletteEnd:

; watermelon						white	red		black
	NEW_SPR_PAL	colorMelonPalette,	$FFFF,	$0C7A,	$0000
; pineapple							gold	brown	green
	NEW_SPR_PAL colorPinePalette,	$0EDD,	$1972,	$1A45