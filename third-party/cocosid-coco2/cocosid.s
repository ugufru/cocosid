; Remi Veilleux, 2010
; This music synthesizer program mimics the sound of a Commodore 64 SID chip
; The music "COMMANDO.SID", by Rob Hubbard, has been hand converted to my CoCo synth-player music format
; Features:
; - 3 independant channels
; - Square, Sin, Sawtooth, Triangle, and White Noise waveforms
; - Supports Attack, Sustain, Release
; - 3 volume level
; - Glide and pitch bend
; - C64-style Arpeggio
; - 19 KHz realtime mixing quality sound output

; Note: With MESS, use -wavwrite output.wav to output a wave for analysis


;FIRQADDR	equ	$fef4	; where FIRQ jumps
;INIT0		equ	$ff90	; GIME Initialization register 0
;IRQENR		equ	$ff92	; IRQ interrupt source
;FIRQENR		equ	$ff93	; FIRQ interrupt source
;VMODE		equ	$ff98	; Video mode - sets lines per row, text/graphics
;VRES		equ	$ff99	; Video resolution - sets size
;BORDERCOLOR	equ	$ff9a	; screen border color
;V_OFFSETMSB	equ	$ff9d	; video memory start register msb
;V_OFFSETLSB	equ	$ff9e	; video memory start register lsb
;H_OFFSET	equ	$ff9f	; horizontal offset + virtual screen
;MMUPAGE		equ	$ffa4	; MMU page register
DISKCONTROLLER	equ	$ff40	; disk controller register
BYTES_PER_ROW	equ	128	; set horizontal resolution in byte per row (at 4 bit per pixel)

NOISE_FREQ_DOWN equ	40	; value that lowers NOISE waveform down to mimic C64

cycle_ratio	equ	76 / 92

	; Memory mapping:
	; $0000..$0FFF	; free
	; $1000..$47FF	; source image for background screen
	; $4800..$7FFF	; code, waveform, music, etc.
	; $8000..$FCFF	; 320x200 16 color graphic page mapped

;		org $1000
;		includebin cocosid_title_test2.bin

			org	0
ssynth_freq		rmb	1 	; current note, doubled, used as 16-bit index into note array (69*2) should give 'A 440 Hz'
;ssynth_synth_freq	rmb	2	; current frequency used in mixer
;ssynth_synth_out	rmb	1	; 8-bit output result used in mixer
ssynth_wavetable	rmb	2	; currently active wavetable for synth
ssynth_note_wave	rmb	2	; selected note wavetable for synth
ssynth_wave_frag	rmb	1	; wavetable fragment index synth
ssynth_voice_ptr	rmb	2	; pointer into current playing pattern for synth
ssynth_song_ptr		rmb	2	; pointer into song (i.e.: to find the current pattern)
ssynth_note_duration	rmb	1	; current note duration for synth
ssynth_pause_duration	rmb	1	; current note pause duration for synth
ssynth_slur_note	rmb	1	; same inital value as pause_duration: used to check if next note will be 'slurred'
ssynth_pitch_alteration rmb	2	; pitch alteration: added to each note being played
ssynth_pitch_glide	rmb	2	; pitch glide speed: added to pitch alteration every frame
ssynth_last_vu		rmb	1	; 'vu' meter position: used to clear last frame value
sizeof_ssynth		equ	*

		org	$4800

; jump to 'real startup' to allow definining procs before using them
start		jmp	start2

; variables...
tmp1		fcb	0
tmp2		fcb	0
tmp3		fcb	0
dtmp1		fdb	0
dtmp2		fdb	0
dtmp3		fdb	0
loop1		fcb	0
loop2		fcb	0
;loop_hi		fcb	0
loop_lo		fcb	0

modulate_dir	fcb	-1
modulate_index	fcb	255
frame_counter	fcb	0
backup_s	fdb	0
pattern_counter	fcb	0

synth1		rmb	sizeof_ssynth
synth2		rmb	sizeof_ssynth
synth3		rmb	sizeof_ssynth

disable_interrupt
;	clr	FIRQENR		; disable the interrupt register
;	clr	IRQENR		; disable these to be safe
	rts

;MyPalette
;	;fcb	14,00,49,07,53,05,56,33,03,62,60,35,63,29,57,59
;	fcb	32,34,35,36,54,6,4,7,0,56,52,16,38,63,63,63

; 3. Set 16 palette colors
;setpalette
;	ldx	#$ffb0		; set palette entries
;	leay	MyPalette,pcr
;	ldb	#8		; 8x2 entries
;	stb	tmp1
;1	ldd	,y++
;	std	,x++
;	dec	tmp1
;	bne	1B
	rts

;***********************************************
; Set graphics memory - sets 32K in 0x8000-0xFFFF
; from MMU pages 0x60000 on up
; interrupts should be disabled to use this
; REGA - first page to load (nice start pages are $30 and $34)
;***********************************************
;SetGraphicsMem
;	ldx	#MMUPAGE	; mapped to $8000-$9FFF, then more
;	ldb	#4		; 4 pages to load
;1	sta	,x+
;	inca			; next page
;	decb
;	bne	1B
	rts

;clearscreen
;	ldx	#$8000
;	ldd	#$ffff
;1	std	,x++
;	cmpx	#$fd00
;	bne	1B
	rts

;*******************
; Quick'n Dirty RLE uncompressor
; Very poor compression ratio.
; Format is: ($pack_lastcolor<<4) + ($pack_count)
; Each 'batch' of color means a color must be repeated 'pack_count+1' times
; Note: Completely linear: wraps at screen edge to next line.
;copy_title
;
;copy_title_uncompressed
;	; source image dimension: width=320 h=200
;	ldx	#$8000
;	ldy	#$1000
;
;	clr	tmp1	; indicates if we are output a 'odd' or 'even' pixel
;uncompressed_next_batch
;	ldb	,y
;	andb	#$f	; 'b' = get 'loop count'
;	incb		; increment by 1 to get real loop count
;uncompressed_next_pixel
;	lda	tmp1
;	beq	uncompressed_odd

;uncompressed_even
;	; uncompressed an 'even' pixel: odd pixel is already in place in video memory
;	lda	,y
;	lsra
;	lsra
;	lsra
;	lsra		; 'a' = get 4-bit color
;	ora	,x	; or with existing pixel
;	sta	,x+	; and output result, advance x to next pixel
;	clr	tmp1	; set tmp1 back to '0'
;	bra	uncompressed_pixel_done

;uncompressed_odd
;	; uncompressed an 'odd' pixel:
;	lda	,y
;	anda	#$f0	; mask-out loop count
;	sta	,x	; output odd and clear even pixel
;	inc	tmp1	; set tmp1 to '1'

;uncompressed_pixel_done
;	decb
;	bne	uncompressed_next_pixel
;	leay	1,y	; advance to next compressed data
;	cmpx	#$8000+320*200/2
;	blo 	uncompressed_next_batch
;	rts

;***********************
; reset vu meter display and variable data
;reset_vu
;	clr	frame_counter
;	clr	pattern_counter
;
;	; clear song progress indicator
;	; position on screen: 48,161
;	ldx	#$8000+160*160+48/2
;	ldy	#$8000+161*160+48/2
;	ldu	#$8000+162*160+48/2
;	lda	#123
;	ldb	#$BB	; clear color
;1	stb	,x+
;	stb	,y+
;	stb	,u+
;	deca
;	bne	1B
;	rts

;	; simple beat/pattern counter
;vu_display
;	; position on screen: 52,141
;	ldy	#$8000+141*160+52/2
;
;	ldb	frame_counter
;	andb	#%111000	; pattern counter
;	leay	b,y
;
;	lda	frame_counter
;	anda	#%100	; beat counter
;	bne	beat_hide
;	; show beat flash
;	ldd	#$ffff	; indicator color
;	std	,y
;	bra	beat_done
;beat_hide
;	ldd	#$BBBB	; clear color
;	std	,y
;beat_done
;	rts

;song_display
;	; song progress indicator
;	; total song length is 123 patterns
;	; position on screen: 48,161
;	ldx	#$8000+160*160+48/2
;	ldb	frame_counter
;	andb	#%11111		; 32 notes pattern counter
;	bne	progress_done
;	; advance to next pattern
;	ldb	pattern_counter
;	abx
;	lda	#$ff	; indicator color
;	sta	,x	; put a pixel
;	leax	160,x
;	sta	,x	; put a pixel
;	leax	160,x
;	sta	,x	; put a pixel
;	inc	pattern_counter
;progress_done
;	rts

;***********************
; Main program start
start2
	lda	#$48
	tfr	a,dp
	setdp	$48		; set dp into 'variable storage' at org $4800

	; initalize:
	orcc	#$50		; disable interrupts
;	sta	$ffd9		; high speed poke (1.79 MHz)

	lds	#$8000		; set stack starting at $8000

	; Disable PIA HSYNC and VSYNC irq
	lda	$ff01
	anda	#%11111110
	sta	$ff01

	lda	$ff03
	anda	#%11111110
	sta	$ff03

	clr	DISKCONTROLLER	; turn off all drive motors immediately

	jsr	disable_interrupt

;	lda 	#%01111100 	; Coco3, MMU on, DRAM constant, IRQ on, FIRQ on, Vector RAM at FEXX on, standard SCS, 16K internal 16K external ROM
;	sta 	INIT0

	; init graphic mode
;	lda	#%10000000
;	sta	VMODE 		; graphics mode, 60 Hz, normal burst, 1 line per row
;	lda	#%00111110 	; Line Per Field 200 lines, Horizontal 128 bytes per row, 16 Colors (4bpp) 256 * 200
;	sta	VRES
; A graphic page requires: 160 * 200 = 32000 bytes ($7D00)

;	ldd	#$C000		; first block of graphics screen at $60000 / 8
;	std	V_OFFSETMSB	; vidstart offset

	;lda	#57		; Mimic C64 border color 57 = 170 170 255
;	lda	#63		; white
;	sta	#BORDERCOLOR

;	lda	#$30 ; set the memory page at $8000..$FD00
;	jsr	SetGraphicsMem

;	jsr	setpalette
;	jsr	clearscreen
;	jsr	copy_title

	jsr	generate_waveform

	; entry point for reset/restart song completely
reset_restart
	lds	#$8000		; reset stack starting at $8000
;	jsr	reset_vu
	jsr	init_sound
	bra	loop_sound

init_sound
	lda	$ff23		; SOUND CONTROL: turn on sound
	ora	#8
	sta	$ff23

	lda	$ff21
	anda	#~4		; SET FOR DATA DIRECTION
	sta	$ff21

	ldb	$ff20		; GET CURRENT DIRECTIONS
	ldb	#%11111100	; DAC-OUT, TAPE&RS-232:IN
	stb	$ff20

	ora	#4		; RESET TO NORMAL

	sta	$ff21

	; initialize song
	; Initialize start values for all synth
	ldd	#song_voice1
	std	synth1+ssynth_song_ptr
	ldd	#song_voice2
	std	synth2+ssynth_song_ptr
	ldd	#song_voice3
	std	synth3+ssynth_song_ptr
	clra
	clrb
	sta	synth1+ssynth_note_duration
	sta	synth1+ssynth_pause_duration
	std	synth1+ssynth_voice_ptr
	std	synth1+ssynth_pitch_alteration
	std	synth1+ssynth_pitch_glide

	sta	synth2+ssynth_note_duration
	sta	synth2+ssynth_pause_duration
	std	synth2+ssynth_voice_ptr
	std	synth2+ssynth_pitch_alteration
	std	synth2+ssynth_pitch_glide

	sta	synth3+ssynth_note_duration
	sta	synth3+ssynth_pause_duration
	std	synth3+ssynth_voice_ptr
	std	synth3+ssynth_pitch_alteration
	std	synth3+ssynth_pitch_glide

	lda	#1	; set 'no slur'
	sta	synth1+ssynth_slur_note
	sta	synth2+ssynth_slur_note
	sta	synth3+ssynth_slur_note

	ldd	#wavetable	; set all voice initially to 'mute' (wavetable entry 0)
	std	synth1+ssynth_wavetable
	std	synth2+ssynth_wavetable
	std	synth3+ssynth_wavetable
	rts

loop_sound
	jsr	process_song

	jsr	sin_wave2
	jsr	rect_modulator
;	jsr	vu_display

	jsr	sin_wave2
	jsr	rect_modulator
;	jsr	song_display
	inc	frame_counter	; increment general frame counter

	jsr	sin_wave2

	bra	loop_sound


sin_wave2
	sts	backup_s

	; setup 3 synths frequency and waveform

	; Synth 1: final wave pointer in Y
	ldx	synth1+ssynth_wavetable
	lda	synth1+ssynth_wave_frag
	leax	a,x
	ldy	,x++	; read 16-bit wave pointer into y
	ldb	,x	; read pitch alteration into b
	adda	#4	; 4 bytes per entry, we have 16 entries
	sta	synth1+ssynth_wave_frag
	; setup final frequency
	ldx	#note_table
	addb	synth1+ssynth_freq	; 'b' contain pitch alteration: add base freq
	abx
	ldd	,x
	addd	synth1+ssynth_pitch_alteration	; add current pitch alteration
;	ldx	#selfmod_addd_freq1+1
	lslb
	rola
;	std	,x	; store into self modifying code the final frequency
	std	selfmod_addd_freq1+1
	ldd	synth1+ssynth_pitch_alteration	; process pitch alteration glide
	addd	synth1+ssynth_pitch_glide
	std	synth1+ssynth_pitch_alteration

	; Synth 2: final wave pointer in U
	ldx	synth2+ssynth_wavetable
	lda	synth2+ssynth_wave_frag
	leax	a,x
	ldu	,x++	; read 16-bit wave pointer into u
	ldb	,x	; read pitch alteration into b
	adda	#4	; 4 bytes per entry, we have 16 entries
	sta	synth2+ssynth_wave_frag
	; setup final frequency
	ldx	#note_table
	addb	synth2+ssynth_freq	; 'b' contain pitch alteration: add base freq
	abx
	ldd	,x
;	ldx	#selfmod_addd_freq2+1
	lslb
	rola
;	std	,x	; store into self modifying code the final frequency
	std	selfmod_addd_freq2+1

	; Synth 3: final wave pointer in S
	ldx	synth3+ssynth_wavetable
	lda	synth3+ssynth_wave_frag
	leax	a,x
	lds	,x++	; read 16-bit wave pointer into s
	ldb	,x	; read pitch alteration into b
	adda	#4	; 4 bytes per entry, we have 16 entries
	sta	synth3+ssynth_wave_frag
	; setup final frequency
	ldx	#note_table
	addb	synth3+ssynth_freq	; 'b' contain pitch alteration: add base freq
	abx
	ldd	,x
;	ldx	#selfmod_addd_freq3+1
	lslb
	rola
;	std	,x	; store into self modifying code the final frequency
	std	selfmod_addd_freq3+1

synthdp	equ	first_selfmod / 256
	lda	#synthdp
	tfr	a,dp
	setdp	synthdp

;	ldx	#mixtable+128 ; 3
	ldx	#$ff20

	; loop for 205 iteration (to output 50Hz)
	; 205 -> 0 + 205
;	lda	#1	; should be #0 but set to #1 to account for first inner loop
;	sta	loop_hi
	lda	#235-8	; subtract #8 to speed up a bit since song processing slows down slightly
	sta	loop_lo
synth_mixer
	; First synth:
first_selfmod
selfmod_ldd_freq1
	ldd	#$0000			; 3
selfmod_addd_freq1
	addd	#$0000			; 4
	std	selfmod_ldd_freq1+1	; 6 (5 if direct)
	ldb	a,y			; 5
	stb	selfmod_addb_sample1+1	; 5 (4 if direct)
	; Total for synth 1: 23 clocks

	; Second synth:
selfmod_ldd_freq2
	ldd	#$0000			; 3
selfmod_addd_freq2
	addd	#$0000			; 4
	std	selfmod_ldd_freq2+1	; 6 (5 if direct)
	ldb	a,u			; 5
	stb	selfmod_addb_sample2+1	; 5 (4 if direct)
	; Total for synth 2: 23 clocks

	; Third synth:
selfmod_ldd_freq3
	ldd	#$0000			; 3
selfmod_addd_freq3
	addd	#$0000			; 4
	std	selfmod_ldd_freq3+1	; 6 (5 if direct)
	ldb	a,s			; 5
	; Total for synth 3: 18 clocks

selfmod_addb_sample1
	addb	#$00			; 2
selfmod_addb_sample2
	addb	#$00			; 2
	;stb	$ff20			; 5
	stb	,x			; 4
	; Total for mixing + inner loop: 18

	dec	loop_lo			; 6
	bne 	synth_mixer		; 3
;	dec	loop_hi			; 6
;	bne 	synth_mixer		; 3


	; Total for 1 sample loop iteration for 3 channel: (we are not accounting for outer loop, insignificant)
	; 82 clocks (77 clocks)  now 76!  need to recalc all this:
	; Effective sample rate:
	; 1789772 / 82 = 21826 Hz (slow: 10913 Hz) (direct: 23243.8/11621.9)
	; To have a C64 Pal frequency of 50Hz, we need to play:
	; 21826 / 50 Hz = 436 iteration (which is 256 + 180 loop)
	; slow: 10913 / 50 Hz = 218 iterations
	; direct: 465/232
	; For a waveform of 256 sample played at 'freq 1.0' (i.e.: freq=256), we have:
	; 21826 / 256 = 85.26 Hz
	; direct: 23243.8 / 256 = 90.796 Hz

	; Speed:
	; We play 361 samples x 4 batch = 1444 samples
	; 18080 / 1444 = 12.5 note per second
	; 12.5 * 60 = 750 note per minute
	; 750 / 8 = 93.75 bpm, using 1/8th note duration

	; C64 Commando plays at 125 BPM
	; So: 125 * 8 = 1000 / 60 = 16.7 note per second
	; 19456 / 16.7 = 1165 samples / 389 = exactly 3 batchs

	lda	#$48
	tfr	a,dp
	setdp	$48

	lds	backup_s
	rts



;*******************
note_continue
	; while a note is playing, this channel does nothing else
	ldb	ssynth_wave_frag,u
	deca
	sta	ssynth_note_duration,u
	; when we reach note duration 0, it's time to play 'release' part of wave_frag
	beq	note_continue_release
	; wave_frag needs to wrap around from 12 to 48 while the note plays
	lda	#48
	cmpa	ssynth_wave_frag,u
	bne	note_continue_sustain_done
	lda	#12
	sta	ssynth_wave_frag,u
note_continue_sustain_done
	rts
note_continue_release
	; 'release' starts at fragment offset 48
	; slur check if 'slur_note' is zero for this note, we DON'T play the 'release' part
	; in order to 'slur' note
	lda	ssynth_slur_note,u
	bne	note_continue_release_accept
	lda	#12	; set fragment to offset start of 'sustain' part: this means we are not doing the release
	bra	note_continue_release_cont
note_continue_release_accept
	lda	#48	; ok, jump to 'release' portion
note_continue_release_cont
	sta	ssynth_wave_frag,u
	rts

pause_continue
	; while a note is pausing, this channel does nothing else
	deca
	sta	ssynth_pause_duration,u
	ldd	#wavetable
	std	ssynth_wavetable,u	; set silence wavetable #00 as active
	clr	ssynth_wave_frag,u	; leave 'wave_frag' stuck at fragment 0
	rts

;*********************
; process_song
process_song
	; process each voice
	ldu	#synth1
	jsr	process_voice

	ldu	#synth2
	jsr	process_voice

	ldu	#synth3
	; optimisation: don't need to 'jsr / rts', process_voice will 'rts' itself

process_voice
	; First, check if we need to fetch a new pattern: (i.e.: when our voice_ptr is 0000)
	ldd	ssynth_voice_ptr,u
	bne 	process_voice_cont
	; Fetch a pattern from song ptr and move song_ptr to next
new_pattern_request
	ldx	ssynth_song_ptr,u
	ldb	,x+
	; if pattern is 00, we have reached end of pattern data for this track
	beq	new_pattern_end
	; if pattern is 255 (-1), special case: instant jump to complete reset/restart
	cmpb	#255
	bne	new_pattern_ok
	jmp	reset_restart
new_pattern_end
	clr	ssynth_wave_frag,u	; leave 'wave_frag' stuck at fragment 0 forever
	rts
new_pattern_ok
	; update song ptr
	stx	ssynth_song_ptr,u
	; now compute pattern pointer location
	ldx	#pattern_ptr-2
	lslb	; each pattern ptr is 16-bit so multiply by 2 to get 16-bit offset
	abx
	ldx	,x
	stx	ssynth_voice_ptr,u

process_voice_cont
	; Now check is a note is currently in progress (if note_duration is not 0)
	lda	ssynth_note_duration,u
	bne	note_continue
	; ..and check is a silence/pause is in progress (if pause_duration is not 0)
	lda	ssynth_pause_duration,u
	bne	pause_continue

	; Process commands from song voice data:
	ldx	ssynth_voice_ptr,u
	ldb	,x+	; fetch command number
	lslb
	clra
	addd	#cmd_jumptable
	std	dtmp1

	jmp	[dtmp1]
cmd_jumptable
	bra	command_00
	bra	command_01
	bra	command_02
	bra	command_03
	bra	command_04
	bra	command_05
	bra	command_06
	bra	command_07
	bra	command_08

command_done
	stx	ssynth_voice_ptr,u	; update voice pointer
	bra	process_voice	; reloop: until we hit a play note command

command_00
	; End of pattern: go to new pattern request
	bra	new_pattern_request
command_01
	lda	#1
	bra	command_done
command_02
	pshs	u	; WARNING: 'u' synth pointer is not used and invalided in this command
	; Wavetable define:
	lda	#60	; 60 bytes per entry
	ldb	,x+	; fetch wavetable index
	mul
	addd	#wavetable	; set destination
	tfr	d,y
	lda	#15	; copy 15 pointers
	sta	tmp1
wavecpy	ldd	,x++	; read 'a=wave index', 'b=pitch alteration'
	cmpa	#16	; Special case: check if this is a 'noise' waveform (i.e.: if wave >= 16)
	blt	1F
	; for noise waveform, we lower the pitch to mimic the C64 low-frequency white noise generator
	subb	#NOISE_FREQ_DOWN	; lower pitch several note down
1	lsla
	ldu	#waveform_lookup
	ldu	a,u
	stu	,y++
	aslb	; pre-multiply by 2 for adequate note shift (signed 8-bit)
	stb	,y++	; (note: 1 byte is wasted here for 32-bit alignment purpose)
	dec	tmp1
	bne	wavecpy
	puls	u

	bra	command_done
command_03
	; play note
	ldd	,x++	; a=note, b=length
	lsla
	sta	ssynth_freq,u
	decb		; pre-decrement duration by 1 since this loop will play '1' duration
	stb	ssynth_note_duration,u

	lda	ssynth_slur_note,u	; check if previous note as a 'slur_note' indication
	beq	play_note_slurred	; yes: slur!
	clra				; no: regular play: start fragment at 0
	sta	ssynth_wave_frag,u	; set fragment when starting a new note
	bra	play_note_cont
play_note_slurred
	; Unneeded: just keep fragment where it was: it will continue and wrap around as normal
	;lda	#12			; set starting frag to skip 'attack' since we are slurring
play_note_cont

	lda	,x+	; a=pause duration
	sta	ssynth_pause_duration,u
	sta	ssynth_slur_note,u	; set both pause and slur as the same initial value
	stx	ssynth_voice_ptr,u
	ldd	ssynth_note_wave,u
	std	ssynth_wavetable,u	; set note wavetable as active

	; release mod:
	; if pause duration is not 0, then increase note length by 1 and decrease pause length by 1
	; so the 'release' part will play in the first time of 'pause'
	; this should make note longer and feel more 'attached' than the harsh mute pause
	lda	ssynth_pause_duration,u
	beq	play_note_release_mod_skip
	deca
	sta	ssynth_pause_duration,u
	inc	ssynth_note_duration,u
play_note_release_mod_skip
	rts
command_04
	; unused
command_05
	; unused
command_06
	; Set note wavetable (which will be used for future playing notes)
	lda	#60	; 60 bytes per entry
	ldb	,x+	; fetch wavetable index
	mul
	addd	#wavetable
	std	ssynth_note_wave,u
	bra	command_done
command_07
	; Set pitch alteration
	leax	1,x	; skip empty byte since command is fdb 16-bit
	ldd	,x++
	std	ssynth_pitch_alteration,u
	bra	command_done
command_08
	; Set Set pitch-glide speed
	leax	1,x	; skip empty byte since command is fdb 16-bit
	ldd	,x++
	std	ssynth_pitch_glide,u
	bra	command_done

;***************
; modulate the rect waveform over time: simulate a 'LFO' modulation
; Note: only 'rect256' 100% volume is modulated
; not 50% and 25% volume
rect_modulator
	ldx	#rect256
	ldb	modulate_index
	abx
	lda	modulate_dir
	beq	rect_mod_dir_0
rect_mod_dir_1
	lda	#-36+42
	sta	,x		; modulate two byte per 'frame'
	sta	,-x
	sta	,-x
	sta	,-x
	subb	#4
	stb	modulate_index
	cmpb	#127
	bne	rect_done	; once we reach '128', toggle value
	lda	#0
	ldb	#128		; modulate samples 128 to 255
	bra	rect_toggle
rect_mod_dir_0
	lda	#36+42
	sta	,x+		; modulate two byte per 'frame'
	sta	,x+		;
	sta	,x+		;
	sta	,x
	addb	#4
	stb	modulate_index
	bne	rect_done	; once we reach '0', toggle value
	lda	#-1
	ldb	#255		; modulate samples 128 to 255
rect_toggle
	stb	modulate_index
	sta	modulate_dir
rect_done
	rts

;******************* generate waveforms:
generate_waveform

	; generate square:
	ldx	#square256
	lda	#224	; 224 / 32 is a pulse wave, 128 / 128 would be a perfect square wave
	ldb	#36	; note: using values values maximum range -42..42
1	stb	,x+
	deca
	bne	1B
	lda	#32
	ldb	#-36
1	stb	,x+
	deca
	bne	1B

	; generate rect:
	ldx	#rect256
	lda	#88	; 224 / 32 is a pulse wave, 128 / 128 would be a perfect square wave
	ldb	#-36	; inverted of square for better mixing
1	stb	,x+
	deca
	bne	1B
	lda	#(256-88)
	ldb	#36
1	stb	,x+
	deca
	bne	1B

	;generate mute:
	ldx	#mute256
	lda	#0	; loop 256 times,
	ldb	#0	; fill with '0'
1	stb	,x+
	deca
	bne	1B

	; generate sin
	ldx	#sin256
	lda	#128	; loop 128 times (we only 'mirror' half the sin)
1	ldb	,x+
	negb
	stb	127,x
	deca
	bne	1B

	; generate 50% volume and 25% volume
	ldx	#square256
	ldy	#square256_s1
	jsr	waveform_volume_half
	ldx	#square256_s1
	ldy	#square256_s2
	jsr	waveform_volume_half

	ldx	#saw256
	ldy	#saw256_s1
	jsr	waveform_volume_half
	ldx	#saw256_s1
	ldy	#saw256_s2
	jsr	waveform_volume_half

	ldx	#triangle256
	ldy	#triangle256_s1
	jsr	waveform_volume_half
	ldx	#triangle256_s1
	ldy	#triangle256_s2
	jsr	waveform_volume_half

	ldx	#sin256
	ldy	#sin256_s1
	jsr	waveform_volume_half
	ldx	#sin256_s1
	ldy	#sin256_s2
	jsr	waveform_volume_half

	ldx	#rect256
	ldy	#rect256_s1
	jsr	waveform_volume_half
	ldx	#rect256_s1
	ldy	#rect256_s2
	jsr	waveform_volume_half

	ldx	#waveforms_start
1	lda	,x
	adda	#42
	sta	,x+
	cmpx	#waveforms_end
	blo	1B

	rts

;********************* waveform_volume_half
; Half the volume of a 256 sample fragment into a destination area
; input:
; 'x': points to source sample buffer
; 'y': points to destination sample buffer
waveform_volume_half
	clra
1	ldb	,x+
	asrb		; divide waveform by 2
	stb	,y+
	deca
	bne	1B
	rts

waveform_lookup
	fdb	mute256+128		; 0  Silence
	fdb	sin256+128		; 1  Sin volume 100%
	fdb	saw256+128		; 2  Saw volume 100%
	fdb	triangle256+128		; 3  Tri volume 100%
	fdb	square256+128		; 4  Sqr volume 100%
	fdb	sin256_s1+128		; 5  Sin volume 50%
	fdb	saw256_s1+128		; 6  Saw volume 50%
	fdb	triangle256_s1+128	; 7  Tri volume 50%
	fdb	square256_s1+128	; 8  Sqr volume 50%
	fdb	sin256_s2+128		; 9  Sin volume 25%
	fdb	saw256_s2+128		; 10 Saw volume 25%
	fdb	triangle256_s2+128	; 11 Tri volume 25%
	fdb	square256_s2+128	; 12 Sqr volume 25%
	fdb	rect256+128		; 13 Rect inverted modulated pulse
	fdb	rect256_s1+128		; 14 Rect 50% inverted modulated pulse
	fdb	rect256_s2+128		; 15 Rect 25% inverted modulated pulse

	fdb	noise4096+128		; 16 Noise: waveform 13..20 will have their frequency lowered to 'match'
	fdb	noise4096+256+128	; 17        the C64 white noise which seems to play a lot lower (by NOISE_FREQ_DOWN)
	fdb	noise4096+512+128	; 18
	fdb	noise4096+768+128	; 19
	fdb	noise4096+1024+128	; 20
	fdb	noise4096+1280+128	; 21
	fdb	noise4096+1536+128	; 22
	fdb	noise4096+1792+128	; 23

;reserve room for 32 wavetable contains 15 waveform 16-bit pointers from waveform_lookup + pitch alteration, (60 bytes each)
wavetable	rmb	1920

; Note table based on frequency of 80.36 Hz
; Note number corresponds to midi notes: http://www.phys.unsw.edu.au/jw/notes.html
; 0..127 notes. 'A 440 Hz' is note 69
; Special case: note 0 is 00 freq = silence
; about note 39 or 40 is 1:1 play ratio (freq=256)
note_table
	fdb 23, 24, 26, 27, 29, 30, 32, 34, 36
	fdb 38, 41, 43, 46, 48, 51, 54, 57, 61, 64, 68, 72
	fdb 77, 81, 86, 91, 96, 102, 108, 115, 121, 129, 136, 144
	fdb 153, 162, 172, 182, 193, 204, 216, 229, 243, 257, 273, 289
	fdb 306, 324, 344, 364, 386, 409, 433, 459, 486, 515, 545, 578
	fdb 612, 649, 687, 728, 771, 817, 866, 917, 972, 1030, 1091, 1156
	fdb 1224, 1297, 1374, 1456, 1543, 1634, 1732, 1835, 1944, 2059, 2182, 2312
	fdb 2449, 2595, 2749, 2912, 3086, 3269, 3463, 3669, 3888, 4119, 4364, 4623
	fdb 4898, 5189, 5498, 5825, 6171, 6538, 6927, 7339, 7775, 8237, 8727, 9246
	fdb 9796, 10378, 10995, 11649, 12342, 13076, 13853, 14677, 15550, 16475, 17454, 18492
	fdb 19592, 20757, 21991, 23299, 24684, 26152, 27707, 29355, 31100, 32949, 34908

; mixing table:
; this is a 256 entries table for logarithmic sound output:
; input: a 8-bit signed value (-128..+127)
; output: clamp 6-bit DAC adjusted value (0..63)<<2 (0..252)
;mixtable
;	; Volume * 0.25 + hard clip ramp
;	fcb 0,0,0,0,0,0,4,4,4,4,8,8,8,8,12,12,12,12,16,16,16,16,20,20,20,20,24,24,24,24,28,28
;	fcb 28,28,32,32,32,32,36,36,36,36,40,40,40,40,44,44,44,44,48,48,48,48,52,52,52,52,56,56,56,56,60,60
;	fcb 60,60,64,64,64,64,68,68,68,68,72,72,72,72,76,76,76,76,80,80,80,80,84,84,84,84,88,88,88,88,92,92
;	fcb 92,92,96,96,96,96,100,100,100,100,104,104,104,104,108,108,108,108,112,112,112,112,116,116,116,116,120,120,120,120,124,124
;	fcb 124,124,128,128,128,128,132,132,132,132,136,136,136,136,140,140,140,140,144,144,144,144,148,148,148,148,152,152,152,152,156,156
;	fcb 156,156,160,160,160,160,164,164,164,164,168,168,168,168,172,172,172,172,176,176,176,176,180,180,180,180,184,184,184,184,188,188
;	fcb 188,188,192,192,192,192,196,196,196,196,200,200,200,200,204,204,204,204,208,208,208,208,212,212,212,212,216,216,216,216,220,220
;	fcb 220,220,224,224,224,224,228,228,228,228,232,232,232,232,236,236,236,236,240,240,240,240,244,244,244,244,248,248,248,248,252,252

	; '1' = 3 frame, a pattern is 32 notes * 3 = 96 frames per pattern
	; (double pattern are 192 frames long)
	; Total Commando song: 3:56.12 (i.e.: 11806 frames / 96 = 123 patterns)

song_voice1
	; pattern list for this track:
	fcb	01	; init instrument: don't SKIP THIS PATTERN!

	fcb	05,05	; frame 1,193
	fcb	05,05	; frame 385,577
	fcb	08,09	; frame 769,961
	fcb	10,11	; frame 1153,1345
	fcb	08,09	; frame 1537,1729 (repeat)
	fcb	10,11	; frame 1921,2113
	fcb	17,18	; frame 2305,2497
	fcb	19,20	; frame 2689,2881
	fcb	19,20	; frame 3073,3265 (repeat)
	fcb	21,21	; frame 3457,3649
	fcb	22,23	; frame 3841,4033
	fcb	22,23	; frame 4225,4417 (repeat)
	fcb	24,24	; frame 4609,4801
	fcb	25,26	; frame 4993,5185
	fcb	27,27,27,27	; frame 5377,5569
	fcb	27,27,27,27	; frame 5761,5953
	fcb	21,21	; frame 6145,6337
	fcb	27,27,27,27	; frame 6529,6721
	fcb	21,27,27	; frame 6913,7105
	fcb	28,29	; frame 7297,7489
	fcb	30,31	; frame 7681,7873
	fcb	32,33	; frame 8065,8257
	fcb	34,35	; frame 8449,8641
	fcb	36,36	; frame 8833,9025
	fcb	37,37	; frame 9217,9409
	fcb	38,38	; frame 9601,9793
	fcb	22,23	; frame 9985,10177
	fcb	27,27,39	; frame 10369,10561
	fcb	21,27	; frame 10657,10849
	fcb	24,27	; frame 10945,11137
	fcb	25,26	; frame 11233,11425
	fcb	27,39	; frame 11617,11713

	fcb	255	; reset/restart song indefinitely
	fcb	00

song_voice2
	; pattern list for this track:
	fcb	06,07	; frame 1,193
	fcb	06,07	; frame 385,577
	fcb	06,07	; frame 769,961
	fcb	15,16	; frame 1153,1345
	fcb	06,07	; frame 1537,1729 (repeat)
	fcb	15,16	; frame 1921,2113
	fcb	06,07	; frame 2305,2497
	fcb	06,07	; frame 2689,2881
	fcb	06,07	; frame 3073,3265
	fcb	45,45	; frame 3457,3649
	fcb	46,46	; frame 3841,4033
	fcb	46,46	; frame 4225,4417
	fcb	47,47	; frame 4609,4801
	fcb	48,48	; frame 4993,5185
	fcb	49,49,49,49	; frame 5377,5569
	fcb	49,49,49,49	; frame 5761,5953
	fcb	45,45	; frame 6145,6337
	fcb	49,49,49,49	; frame 6529,6721
	fcb	45,49,49	; frame 6913,7105
	fcb	45,45	; frame 7297,7489
	fcb	45,45	; frame 7681,7873
	fcb	45,45	; frame 8065,8257
	fcb	45,45	; frame 8449,8641
	fcb	45,45	; frame 8833,9025
	fcb	46,46	; frame 9217,9409
	fcb	46,46	; frame 9601,9793
	fcb	46,46	; frame 9985,10177
	fcb	49,49,50	; frame 10369,10561
	fcb	45,49	; frame 10657,10849
	fcb	47,49	; frame 10945,11137
	fcb	48,48	; frame 11233,11425
	fcb	49,50	; frame 11617,11713

	fcb	00


song_voice3
	; pattern list for this track:
	fcb	02,02,03,04	; frame 1,97,193,289
	fcb	02,02,03,04	; frame 385,481,577,673
	fcb	02,02,03,04	; frame 769,865,961,1057
	fcb	12,12,13,14	; frame 1153,1249,1345,1441
	fcb	02,02,03,04	; frame 1537,1729 (repeat)
	fcb	12,12,13,14	; frame 1921,2113
	fcb	02,40,41,02	; frame 2305,2401,2497,2593
	fcb	02,02,03,04	; frame 2689,2881
	fcb	02,02,03,04	; frame 3073,3265
	fcb	02,02,40,40	; frame 3457,3649
	fcb	42,42,13,13	; frame 3841,4033
	fcb	42,42,13,13	; frame 4225,4417
	fcb	40,40,40,40	; frame 4609,4801
	fcb	41,41,41,41	; frame 4993,5185
	fcb	43,43,43,43	; frame 5377,5569
	fcb	43,43,43,43	; frame 5761,5953
	fcb	02,02,40,40	; frame 6145,6337
	fcb	43,43,43,43	; frame 6529,6721
	fcb	02,40,43,43	; frame 6913,7105
	fcb	02,02,40,40	; frame 7297,7489
	fcb	02,02,40,40	; frame 7681,7873
	fcb	02,02,40,40	; frame 8065,8257
	fcb	02,02,40,40	; frame 8449,8641
	fcb	02,02,40,40	; frame 8833,9025
	fcb	42,42,13,13	; frame 9217,9409
	fcb	42,42,13,13	; frame 9601,9793
	fcb	42,42,13,13	; frame 9985,10177
	fcb	43,43,44	; frame 10369,10561
	fcb	02,40,43	; frame 10657,10849
	fcb	40,40,43	; frame 10945,11137
	fcb	41,41,41,41	; frame 11233,11425
	fcb	43,44		; frame 11617,11713
	fcb	00

pattern_ptr
	fdb	pattern_01
	fdb	pattern_02
	fdb	pattern_03
	fdb	pattern_04
	fdb	pattern_05
	fdb	pattern_06
	fdb	pattern_07
	fdb	pattern_08
	fdb	pattern_09
	fdb	pattern_10
	fdb	pattern_11
	fdb	pattern_12
	fdb	pattern_13
	fdb	pattern_14
	fdb	pattern_15
	fdb	pattern_16
	fdb	pattern_17
	fdb	pattern_18
	fdb	pattern_19
	fdb	pattern_20
	fdb	pattern_21
	fdb	pattern_22
	fdb	pattern_23
	fdb	pattern_24
	fdb	pattern_25
	fdb	pattern_26
	fdb	pattern_27
	fdb	pattern_28
	fdb	pattern_29
	fdb	pattern_30
	fdb	pattern_31
	fdb	pattern_32
	fdb	pattern_33
	fdb	pattern_34
	fdb	pattern_35
	fdb	pattern_36
	fdb	pattern_37
	fdb	pattern_38
	fdb	pattern_39
	fdb	pattern_40
	fdb	pattern_41
	fdb	pattern_42
	fdb	pattern_43
	fdb	pattern_44
	fdb	pattern_45
	fdb	pattern_46
	fdb	pattern_47
	fdb	pattern_48
	fdb	pattern_49
	fdb	pattern_50

; this is our special init instrument pattern: no note played, total duration: 0
pattern_01
	; a wavetable is defined using 5 group of 3 'wave / pitch alteration'
	; first group (0..2): attack portion
	; second group (3..11): sustain portion (loops around if sound is long)
	; third group (12..14): release portion, always played at the end
	;   (unless the sound duration is 1: in this case only the 'attack' portion plays)

	fcb	02,00,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; define wavetable 00 : complete silence
	fcb	02,01,4,0,4,0,4,0,4,0,4,0,4,0,4,0,4,0,4,0,4,0,4,0,4,0,4,0,8,0,12,0 ; define wavetable 01 : voice 3 bass square
	fcb	02,02,16,0,17,0,18,12,10,0,20,12,21,0,10,0,20,12,21,0,0,0,0,0,0,0,21,0,22,0,23,0 ; define wavetable 02 : snare drum
	fcb	02,03,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0 ; define wave 3: plain sin (unused)
	fcb	02,04,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0,2,0 ; define wave 4: plain sawtooth (unused)
	fcb	02,05,3,0,3,0,3,0,3,0,3,0,3,0,3,0,3,0,3,0,3,0,3,0,3,0,3,0,3,0,3,0 ; define wave 5: plain triangle (unused)

	fcb	02,06,3,0,16,0,17,-55,3,0,3,-70,3,0,3,-70,3,0,3,-70,0,0,0,0,0,0,7,0,11,-70,0,0 ; define wave 6: voice 1 first commando note
	fcb	02,07,3,0,16,0,17,12,3,0,3,12,3,0,3,12,3,0,3,12,0,0,0,0,0,0,7,0,11,12,0,0 ; define wave 7: voice 1 second sound
	fcb	02,08,4,0,16,0,17,12,4,0,4,12,4,0,4,12,4,0,4,12,4,0,4,12,4,0,4,12,8,0,12,12 ; define wave 8: voice 2 main instrument
	fcb	02,09,3,0,16,0,17,-41,3,0,3,-41,3,0,3,-41,3,0,3,-41,0,0,0,0,0,0,7,0,11,-41,0,0 ; define wave 9:

	fcb	02,10,4,0,19,0,21,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; voice 2 'little tic tic tic'

	fcb	02,11,15,0,14,0,13,0,13,0,13,0,13,0,13,0,13,0,13,0,13,0,13,0,13,0,13,0,14,0,15,0 ; voice 1 'song main instrument'

	fcb	02,12,4,0,16,0,17,0,4,-1,4,-3,4,-4,4,-6,4,-8,4,-10,4,-12,4,-15,4,-18,4,-22,4,-28,4,-35 ; voice 1 'tom drum'
	fcb	02,13,4,0,16,0,17,0,4,0,4,-1,4,-2,0,0,0,0,0,0,0,0,0,0,0,0,4,-3,4,-5,4,-6 ; voice 1 'mini tom drum'
	fcb	02,14,4,0,16,0,17,-20,4,0,4,-51,4,0,4,-51,4,0,4,-51,4,0,4,-51,4,0,4,-51,4,0,4,-51 ; voice 1 'end song tom drum'

	fcb	02,15,3,0,16,0,17,-20,3,0,4,-51,3,0,4,-51,3,0,4,-51,3,0,4,-51,3,0,4,-51,3,0,4,-51 ; voice 2 special drum 1
	fcb	02,16,3,0,16,0,17,0,3,0,3,12,3,0,3,12,3,0,3,12,3,0,3,12,3,0,3,12,3,0,3,12 ; voice 2 special drum 2

	; test stuff
	;fcb	06,11
	;fcb	03,60,255,1

	fcb	00	; End of pattern

pattern_02
	; Voice 3: 'A-1' measure
	fcb	06,01	; activate wavetable
	fcb	03,33,5,1 ; play notes..
	fcb	03,45,1,1

	fcb	06,02	; activate wavetable
	fcb	03,58,3,1

	fcb	06,01	; activate wavetable
	fcb	03,33,3,1 ; 4 -> 3 + 1 pause
	fcb	03,33,7,1

	fcb	06,02	; activate wavetable
	fcb	03,58,3,1

	fcb	06,01	; activate wavetable
	fcb	03,43,1,1
	fcb	03,45,1,1
	fcb	00	; End of pattern

pattern_03
	; Voice 3: 'A#1' measure
	fcb	06,01	; activate wavetable
	fcb	03,34,5,1 ; play notes..
	fcb	03,46,1,1

	fcb	06,02	; activate wavetable
	fcb	03,58,3,1

	fcb	06,01	; activate wavetable
	fcb	03,34,3,1
	fcb	03,34,7,1

	fcb	06,02	; activate wavetable
	fcb	03,58,3,1

	fcb	06,01	; activate wavetable
	fcb	03,45,1,1
	fcb	03,46,1,1
	fcb	00	; End of pattern

pattern_04
	; Voice 3: 'E-1' measure
	fcb	06,01	; activate wavetable
	fcb	03,28,5,1 ; play notes..
	fcb	03,40,1,1

	fcb	06,02	; activate wavetable
	fcb	03,58,3,1

	fcb	06,01	; activate wavetable
	fcb	03,28,3,1
	fcb	03,28,7,1

	fcb	06,02	; activate wavetable
	fcb	03,58,3,1

	fcb	06,01	; activate wavetable
	fcb	03,38,1,1
	fcb	03,40,1,1
	fcb	00	; End of pattern

pattern_05
	; Voice 1: first pattern (double)
	fcb	06,06
	fcb	03,100,3,1
	fcb	06,07
	fcb	03,93,3,1

	fcb	06,08
	fcb	03,69,3,1
	fcb	03,69,3,1
	fcb	03,69,5,1
	fcb	03,69,5,1
	fcb	03,67,5,1
	fcb	03,69,1,1
	fcb	03,69,3,1
	fcb	03,69,3,1
	fcb	03,67,3,1
	fcb	03,69,1,1
	fcb	03,67,1,1
	fcb	03,69,3,1

	fcb	06,09
	fcb	03,100,3,1

	fcb	06,07
	fcb	03,93,3,1
	fcb	00	; End of pattern

pattern_06
	; Voice 2: first pattern (double)
	fcb	06,10
	fcb	03,71,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1

	fcb	06,08
	fcb	03,64,3,1
	fcb	03,64,3,1
	fcb	03,65,5,1
	fcb	03,64,5,1
	fcb	03,62,3,1

	fcb	06,10
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1

	fcb	06,08
	fcb	03,64,3,1
	fcb	03,64,3,1
	fcb	03,64,7,9
	fcb	00	; End of pattern

pattern_07
	; Voice 2: second pattern (double)
	fcb	06,10
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1

	fcb	06,08
	fcb	03,64,3,1
	fcb	03,64,3,1
	fcb	03,65,5,1
	fcb	03,64,5,1
	fcb	03,62,3,3

	fcb	03,64,1,1
	fcb	03,64,3,1
	fcb	03,64,3,1
	fcb	03,64,3,1
	fcb	03,64,7,9
	fcb	00	; End of pattern

pattern_08
	; Voice 1: refrain music first pattern normal in A-4 (69) (double)
	fcb	06,02
	fcb	03,62,1,1

	fcb	06,11
	fcb	03,69,1,1
	fcb	03,69,3,1
	fcb	03,69,3,1
	fcb	03,69,3,1
	fcb	03,69,7,1
	fcb	03,69,5,1
	fcb	03,69,3,1
	fcb	03,76,1,1
	fcb	03,76,3,1
	fcb	03,76,3,1
	fcb	03,76,3,1
	fcb	03,76,7,1
	fcb	06,12
	fcb	03,56,4,4
	fcb	00	; End of pattern

pattern_09
	; Voice 1: refrain music second pattern normal (double)
	fcb	06,11
	fcb	03,77,7,1
	fcb	03,76,7,1
	fcb	03,77,7,1
	fcb	03,76,7,3

	fcb	03,71,1,1
	fcb	03,71,3,1
	fcb	03,71,3,1
	fcb	03,71,3,1
	fcb	03,71,7,1

	fcb	06,12
	fcb	03,56,4,4
	fcb	00	; End of pattern

pattern_10
	; Voice 1: refrain music first pattern raised to C-5 (72) (double)
	fcb	06,02
	fcb	03,62,1,1

	fcb	06,11
	fcb	03,72,1,1
	fcb	03,72,3,1
	fcb	03,72,3,1
	fcb	03,72,3,1
	fcb	03,72,7,1
	fcb	03,72,5,1
	fcb	03,72,3,1
	fcb	03,79,1,1
	fcb	03,79,3,1
	fcb	03,79,3,1
	fcb	03,79,3,1
	fcb	03,79,7,1
	fcb	06,12
	fcb	03,56,4,4
	fcb	00	; End of pattern

pattern_11
	; Voice 1: refrain music second pattern raised (double)
	fcb	06,11
	fcb	03,80,7,1
	fcb	03,79,7,1
	fcb	03,80,7,1
	fcb	03,79,7,3

	fcb	03,74,1,1
	fcb	03,74,3,1
	fcb	03,74,3,1
	fcb	03,74,3,1
	fcb	03,74,7,1

	fcb	06,13
	fcb	03,59,3,1
	fcb	03,56,1,1
	fcb	03,56,1,1
	fcb	00	; End of pattern

pattern_12
	; Voice 3: raised C-2 to measure
	fcb	06,01
	fcb	03,36,5,1
	fcb	03,48,1,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,36,3,1
	fcb	03,36,7,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,46,1,1
	fcb	03,48,1,1
	fcb	00	; End of pattern

pattern_13
	; Voice 3: raised 'C#2' measure
	fcb	06,01
	fcb	03,37,5,1
	fcb	03,49,1,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,37,3,1
	fcb	03,37,7,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,48,1,1
	fcb	03,49,1,1
	fcb	00	; End of pattern

pattern_14
	; Voice 3: 'G-1' measure
	fcb	06,01
	fcb	03,31,5,1
	fcb	03,43,1,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,31,3,1
	fcb	03,31,7,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,40,1,1
	fcb	03,40,1,1
	fcb	00	; End of pattern

pattern_15
	; Voice 2: first pattern raised +3 (double)
	fcb	06,10
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1

	fcb	06,08
	fcb	03,67,3,1
	fcb	03,67,3,1
	fcb	03,68,5,1
	fcb	03,67,5,1
	fcb	03,65,3,1

	fcb	06,10
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1

	fcb	06,08
	fcb	03,67,3,1
	fcb	03,67,3,1
	fcb	03,67,7,9
	fcb	00	; End of pattern

pattern_16
	; Voice 2: second pattern raised +3 (double)
	fcb	06,10
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1
	fcb	03,83,1,1

	fcb	06,08
	fcb	03,67,3,1
	fcb	03,67,3,1
	fcb	03,68,5,1
	fcb	03,67,5,1
	fcb	03,65,3,3

	fcb	03,67,1,1
	fcb	03,67,3,1
	fcb	03,67,3,1
	fcb	03,67,3,1
	fcb	03,67,7,9
	fcb	00	; End of pattern

pattern_17
	; Voice 1: frame 2305
	fcb	06,02	; snare drum
	fcb	03,62,3,1
	fcb	03,62,3,1

	fcb	06,11	; main instr.
	fcb	03,69,3,1
	fcb	03,69,3,1
	fcb	03,69,1,1
	fcb	03,69,1,1
	fcb	03,69,3,1
	fcb	03,71,3,1
	fcb	03,72,3,1
	fcb	03,74,1,1
	fcb	03,74,1,1
	fcb	03,74,3,1
	fcb	03,74,3,1
	fcb	03,74,3,1
	fcb	03,74,7,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1

	fcb	06,11	; main instr.
	fcb	03,74,1,1
	fcb	03,76,1,1

	fcb	00	; End of pattern

pattern_18
	; Voice 1: frame 2497
	fcb	06,11	; main instr.
	fcb	03,77,1,1
	fcb	03,77,1,1
	fcb	03,76,3,1
	fcb	03,74,3,1
	fcb	03,72,3,1
	fcb	03,71,3,1
	fcb	03,69,3,1
	fcb	03,68,7,1

	fcb	06,02	; snare drum
	fcb	03,62,1,1

	fcb	06,11	; main instr.
	fcb	03,69,1,1
	fcb	03,69,3,1
	fcb	03,69,3,1
	fcb	03,71,3,1
	fcb	03,69,7,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,4,4

	fcb	00	; End of pattern

pattern_19
	; Voice 1: frame 2689
	fcb	06,08	; 'voice 2' snare-instrument
	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,70,1,1
	fcb	03,69,3,1

	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,70,1,1
	fcb	03,69,3,1

	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,70,1,1
	fcb	03,69,3,1

	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,70,1,1
	fcb	03,69,3,1

	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,69,1,1
	fcb	03,77,3,1
	fcb	03,76,3,1

	fcb	00	; End of pattern

pattern_20
	; Voice 1: frame 2881
	fcb	06,08	; 'voice 2' snare-instrument
	fcb	03,77,1,1
	fcb	03,76,3,1
	fcb	03,75,1,1
	fcb	03,74,3,1

	fcb	03,77,1,1
	fcb	03,76,3,1
	fcb	03,75,1,1
	fcb	03,74,3,1

	fcb	03,77,3,1
	fcb	03,76,3,1
	fcb	03,71,1,1
	fcb	03,70,3,1
	fcb	03,69,1,1
	fcb	03,68,3,1
	fcb	03,71,1,1
	fcb	03,70,3,1
	fcb	03,69,1,1
	fcb	03,68,3,1
	fcb	03,72,3,1
	fcb	03,71,3,1

	fcb	00	; End of pattern

pattern_21
	; Voice 1: frame 3457
	fcb	06,11	; main instr
	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,70,1,1
	fcb	03,69,3,1
	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,70,1,1
	fcb	03,69,3,1
	fcb	03,72,3,1
	fcb	03,74,3,1
	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,70,1,1
	fcb	03,69,3,1
	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,70,1,1
	fcb	03,69,3,1
	fcb	03,72,3,1
	fcb	03,74,3,1

	fcb	00	; End of pattern

pattern_22
	; Voice 1: frame 3841
	fcb	06,11	; main instr
	fcb	03,78,11,1

	; test pitch alteration
	;fcb	03,78,11,1	; this note is slurred down
	fdb	$0800,-(cycle_ratio*272/12)	; -272 total pitch bend during 12 frames
	fcb	03,78,4,0
	fdb	$0800,0		; stop pitch bend
	fcb	03,78,7,1
	fdb	$0707,0		; reset pitch alteration

	fcb	03,73,3,1
	fcb	03,71,3,1

	;fcb	03,71,7,1	; slurred
	fdb	$0800,-(cycle_ratio*134/12)	; -134 total pitch bend during 12 frames
	fcb	03,71,4,0
	fdb	$0800,0		; stop pitch bend
	fdb	$0707,0		; reset pitch alteration
	fcb	03,70,3,1

	fcb	03,70,3,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1
	fcb	03,56,3,1

	fcb	06,11	; main instr
	fcb	03,70,1,1
	fcb	03,70,1,1
	fcb	03,71,3,1
	fcb	03,73,3,1

	fcb	00	; End of pattern

pattern_23
	; Voice 1: frame 4033
	fcb	06,11	; main instr
	fcb	03,73,11,1
	fcb	03,73,3,1
	fcb	03,76,5,1
	fcb	03,73,5,1

	;fcb	03,71,11,1	; slurred
	fdb	$0800,(cycle_ratio*202/15)	; 202 total pitch bend during 15 frames
	fcb	03,71,5,0
	fdb	$0800,0		; stop pitch bend
	fcb	03,71,6,1
	fdb	$0707,0		; reset pitch alteration

	;fcb	03,73,15,1	; slurred
	fdb	$0800,-(cycle_ratio*696/45)	; 696 total pitch bend during 45 frames
	fcb	03,73,15,1
	fdb	$0800,0		; stop pitch bend
	fdb	$0707,0		; reset pitch alteration

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1
	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1

	fcb	00	; End of pattern

pattern_24
	; Voice 1: frame 4609
	fcb	06,11	; main instr
	fcb	03,74,7,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1

	fcb	06,11	; main instr
	fcb	03,74,1,1
	fcb	03,74,1,1
	fcb	03,76,5,1
	fcb	03,74,5,1

	;fcb	03,72,11,1 ; slurred
	fdb	$0800,(cycle_ratio*87/12)	; 87 total pitch bend during 12 frames
	fcb	03,72,4,0
	fdb	$0800,0		; stop pitch bend
	fdb	$0707,0		; reset pitch alteration
	fcb	03,74,7,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,59,3,1
	;fcb	02,12,4,0,16,0,17,0,4,-1,4,-3,4,-4,4,-6,4,-8,4,-10,4,-12,4,-15,4,-18,4,-22,4,-28,4,-35 ; voice 1 'tom drum'
	fcb	03,56,5,7 ; big tom: slurred
	;fcb	03,56,4,0 ; removed: this doesn't sound good
	;fcb	03,38,4,4

	fcb	03,59,3,1
	fcb	03,56,3,1

	fcb	00	; End of pattern

pattern_25
	; Voice 1: frame 4993
	fcb	06,11	; main instr
	fcb	03,76,7,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1

	fcb	06,11	; main instr
	fcb	03,76,1,1
	fcb	03,76,1,1
	fcb	03,78,5,1
	fcb	03,76,5,1

	;fcb	03,74,11,1 ; slurred
	fdb	$0800,(cycle_ratio*87/12)	; 87 total pitch bend during 12 frames
	fcb	03,74,4,0
	fdb	$0800,0		; stop pitch bend
	fdb	$0707,0		; reset pitch alteration
	fcb	03,76,7,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,59,3,1
	fcb	03,56,5,7 ; slurred
	;fcb	03,56,4,0 ; removed: this doesn't sound good
	;fcb	03,38,4,4

	fcb	03,59,3,1
	fcb	03,56,3,1

	fcb	00	; End of pattern

pattern_26
	; Voice 1: frame 5185
	fcb	06,11	; main instr
	fcb	03,76,7,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1

	fcb	06,11	; main instr
	fcb	03,76,1,1
	fcb	03,76,1,1
	fcb	03,78,5,1
	fcb	03,76,5,1

	;fcb	03,74,9,1 ; slurred
	fdb	$0800,(cycle_ratio*87/12)	; 87 total pitch bend during 12 frames
	fcb	03,74,4,0
	fdb	$0800,0		; stop pitch bend
	fdb	$0707,0		; reset pitch alteration
	fcb	03,76,5,1

	fcb	03,78,5,1
	fcb	03,80,3,1
	fcb	03,78,5,1
	fcb	03,80,5,1
	fcb	03,81,3,1

	fcb	00	; End of pattern

pattern_27
	; Voice 1: frame 5377
	; NOTE: THIS IS A HALF-PATTERN (96 frames)
	fcb	06,08	; 'voice 2' snare-instrument
	fcb	03,82,1,1
	fcb	03,82,1,1
	fcb	03,82,1,1
	fcb	03,82,1,1
	fcb	03,82,1,1
	fcb	03,82,1,1
	fcb	03,80,1,1
	fcb	03,82,1,1
	fcb	03,82,1,1
	fcb	03,80,1,1
	fcb	03,82,3,1
	fcb	03,82,1,1
	fcb	03,82,1,1
	fcb	03,80,1,1
	fcb	03,80,1,1

	fcb	00	; End of pattern

pattern_28
	; Voice 1: frame 7297
	fcb	06,11	; main instr

	;fcb	03,67,39,1 ; slurred
	fcb	03,67,8,0
	fdb	$0800,(cycle_ratio*162/24)	; 162 total pitch bend during 24 frames
	fcb	03,67,8,0
	fdb	$0800,0		; stop pitch bend
	fcb	03,67,23,1
	fdb	$0707,0		; reset pitch alteration

	fcb	03,67,3,1
	fcb	03,69,3,1
	fcb	03,74,3,1
	fcb	03,72,3,1
	fcb	03,69,7,1

	fcb	00	; End of pattern

pattern_29
	; Voice 1: frame 7489
	fcb	06,11	; main instr
	;fcb	03,72,39,1 ; slurred
	fcb	03,72,8,0
	fdb	$0800,(cycle_ratio*215/24)	; 162 total pitch bend during 24 frames
	fcb	03,72,8,0
	fdb	$0800,0		; stop pitch bend
	fcb	03,72,23,1
	fdb	$0707,0		; reset pitch alteration

	fcb	03,74,3,1
	fcb	03,79,3,1
	fcb	03,78,3,1
	fcb	03,74,3,1
	fcb	03,69,7,1

	fcb	00	; End of pattern

pattern_30
	; Voice 1: frame 7681
	fcb	06,11	; main instr
	;fcb	03,67,39,1 ; slurred
	fcb	03,67,8,0
	fdb	$0800,(cycle_ratio*162/24)	; 162 total pitch bend during 24 frames
	fcb	03,67,8,0
	fdb	$0800,0		; stop pitch bend
	fcb	03,67,23,1
	fdb	$0707,0		; reset pitch alteration

	;fcb	03,75,11,1 ; slurred
	fdb	$0800,-(cycle_ratio*182/24)	; 162 total pitch bend during 24 frames
	fcb	03,75,8,0
	fdb	$0800,0		; stop pitch bend
	fdb	$0707,0		; reset pitch alteration
	fcb	03,74,3,1

	fcb	03,72,3,1
	fcb	03,69,7,1

	fcb	00	; End of pattern

pattern_31
	; Voice 1: frame 7873
	fcb	06,11	; main instr
	;fcb	03,74,39,1 ;slurred
	fcb	03,74,8,0
	fdb	$0800,-(cycle_ratio*176/24)	; total pitch bend during 24 frames
	fcb	03,74,8,0
	fdb	$0800,0		; stop pitch bend
	fcb	03,74,23,1
	fdb	$0707,0		; reset pitch alteration

	fcb	03,74,3,1
	fcb	03,76,3,1
	fcb	03,79,3,1
	fcb	03,78,3,1
	fcb	03,79,3,1
	fcb	03,81,3,1

	fcb	00	; End of pattern

pattern_32
	; Voice 1: frame 8065
	fcb	06,11	; main instr
	;fcb	03,79,23,1	; slurred
	fcb	03,79,8,0
	fdb	$0800,(cycle_ratio*324/24)	; total pitch bend during 24 frames
	fcb	03,79,8,0
	fdb	$0800,0		; stop pitch bend
	fcb	03,79,7,1
	fdb	$0707,0		; reset pitch alteration

	fcb	03,81,1,1
	fcb	03,81,3,1
	fcb	03,81,1,1
	fcb	03,81,1,1
	fcb	03,81,3,1
	fcb	03,79,1,1
	fcb	03,81,3,1
	fcb	03,79,1,1
	fcb	03,78,3,1
	fcb	03,79,1,1
	fcb	03,78,3,1
	fcb	03,76,3,1
	fcb	03,74,3,1

	fcb	00	; End of pattern

pattern_33
	; Voice 1: frame 8257
	fcb	06,11	; main instr
	fcb	03,74,1,1
	fcb	03,74,3,1
	fcb	03,72,1,1
	fcb	03,74,3,1
	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,72,1,1
	fcb	03,71,3,1
	fcb	03,69,3,1
	fcb	03,67,3,1
	fcb	03,69,1,1
	fcb	03,69,3,1
	fcb	03,67,1,1
	fcb	03,69,3,1
	fcb	03,71,1,1
	fcb	03,72,3,1
	fcb	03,74,1,1
	fcb	03,76,3,1
	fcb	03,78,3,1
	fcb	03,79,3,1

	fcb	00	; End of pattern

pattern_34
	; Voice 1: frame 8449
	fcb	06,11	; main instr
	;fcb	03,83,39,1 ; slurred
	fcb	03,83,8,0
	fdb	$0800,-(cycle_ratio*218/24)	; total pitch bend during 24 frames
	fcb	03,83,8,0
	fdb	$0800,0		; stop pitch bend
	fdb	$0707,0		; reset pitch alteration
	fcb	03,81,23,1

	fcb	03,79,3,1
	fcb	03,81,3,1
	fcb	03,84,1,1
	fcb	03,84,1,1
	fcb	03,81,3,1
	fcb	03,86,1,1
	fcb	03,86,1,1
	fcb	03,84,3,1

	fcb	00	; End of pattern

pattern_35
	; Voice 1: frame 8641
	fcb	06,11	; main instr
	;fcb	03,88,47,3 ; slurred
	fcb	03,88,8,0
	fdb	$0800,-(cycle_ratio*483/24)	; total pitch bend during 24 frames
	fcb	03,88,8,0
	fdb	$0800,0		; stop pitch bend
	fcb	03,88,31,3
	fdb	$0707,0		; reset pitch alteration

	fcb	03,88,1,1
	fcb	03,88,1,1
	fcb	03,76,1,1
	fcb	03,89,1,1
	fcb	03,76,1,1
	fcb	03,84,1,1
	fcb	03,86,1,1

	fcb	00	; End of pattern

pattern_36
	; Voice 1: frame 8833,9025
	fcb	06,11	; main instr
	fcb	03,88,1,1
	fcb	03,88,1,1
	fcb	03,76,3,1
	fcb	03,86,3,1
	fcb	03,76,1,1
	fcb	03,84,3,1
	fcb	03,76,1,1
	fcb	03,83,3,1
	fcb	03,84,1,1
	fcb	03,76,1,1
	fcb	03,84,1,1
	fcb	03,86,1,1
	fcb	03,88,1,1
	fcb	03,88,1,1
	fcb	03,76,3,1
	fcb	03,86,3,1
	fcb	03,76,1,1
	fcb	03,84,3,1
	fcb	03,76,1,1
	fcb	03,83,3,1
	fcb	03,84,1,1
	fcb	03,76,1,1
	fcb	03,84,1,1
	fcb	03,86,1,1

	fcb	00	; End of pattern

pattern_37
	; Voice 1: frame 9217,9409
	fcb	06,11	; main instr
	fcb	03,88,1,1
	fcb	03,88,1,1
	fcb	03,76,3,1
	fcb	03,87,3,1
	fcb	03,76,1,1
	fcb	03,85,3,1
	fcb	03,76,1,1
	fcb	03,83,3,1
	fcb	03,85,1,1
	fcb	03,76,1,1
	fcb	03,85,1,1
	fcb	03,87,1,1
	fcb	03,88,1,1
	fcb	03,88,1,1
	fcb	03,76,3,1
	fcb	03,87,3,1
	fcb	03,76,1,1
	fcb	03,85,3,1
	fcb	03,76,1,1
	fcb	03,83,3,1
	fcb	03,85,1,1
	fcb	03,76,1,1
	fcb	03,85,1,1
	fcb	03,87,1,1

	fcb	00	; End of pattern

pattern_38
	; Voice 1: frame 9601,9793
	fcb	06,11	; main instr
	fcb	03,85,1,1
	fcb	03,85,1,1
	fcb	03,73,3,1
	fcb	03,83,3,1
	fcb	03,73,1,1
	fcb	03,82,3,1
	fcb	03,73,1,1
	fcb	03,80,3,1
	fcb	03,78,1,1
	fcb	03,73,1,1
	fcb	03,83,1,1
	fcb	03,85,1,1
	fcb	03,85,1,1
	fcb	03,85,1,1
	fcb	03,73,3,1
	fcb	03,83,3,1
	fcb	03,73,1,1
	fcb	03,82,3,1
	fcb	03,73,1,1
	fcb	03,80,3,1
	fcb	03,78,1,1
	fcb	03,73,1,1
	fcb	03,83,1,1
	fcb	03,85,1,1

	fcb	00	; End of pattern

pattern_39
	; voice 1 frame 10561
	fcb	06,14	; voice 1 song end drum
	fcb	03,63,7,17

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1
	fcb	03,56,3,1
	fcb	00	; End of pattern

pattern_40
	; Voice 3: 'D-2' measure
	fcb	06,01
	fcb	03,38,5,1
	fcb	03,50,1,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,38,3,1
	fcb	03,38,7,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,48,1,1
	fcb	03,48,1,1
	fcb	00	; End of pattern

pattern_41
	; Voice 3: 'G-1' measure
	fcb	06,01
	fcb	03,28,5,1
	fcb	03,40,1,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,28,3,1
	fcb	03,28,7,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,38,1,1
	fcb	03,40,1,1
	fcb	00	; End of pattern

pattern_42
	; Voice 3: 'F#-1' measure
	fcb	06,01
	fcb	03,30,5,1
	fcb	03,42,1,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,30,3,1
	fcb	03,30,7,1

	fcb	06,02
	fcb	03,58,3,1

	fcb	06,01
	fcb	03,40,1,1
	fcb	03,42,1,1
	fcb	00	; End of pattern

pattern_43
	; Voice 3: frame 5377
	; taratatata
	fcb	06,08	; 'voice 2' snare-instrument
	fcb	03,51,1,1
	fcb	03,51,1,1
	fcb	03,51,1,1
	fcb	03,51,1,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1

	fcb	06,08	; 'voice 2' snare-instrument
	fcb	03,49,1,1
	fcb	03,51,3,1
	fcb	03,49,1,1
	fcb	03,51,1,1
	fcb	03,51,1,1

	fcb	06,12	; voice 1 end tom drum
	fcb	03,59,3,1
	fcb	03,56,3,1
	fcb	00	; End of pattern

pattern_44
	; voice 3 frame 10561
	fcb	06,14	; voice 1 song end drum
	fcb	03,83,7,17

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1
	fcb	03,56,3,1
	fcb	00	; End of pattern

pattern_45
	; Voice 2: frame 3457
	fcb	06,15
	fcb	03,100,3,1
	fcb	06,16
	fcb	03,93,3,1

	fcb	06,08
	fcb	03,69,3,1
	fcb	03,69,3,1
	fcb	03,69,5,1
	fcb	03,69,5,1
	fcb	03,67,5,1
	fcb	03,69,1,1
	fcb	03,69,3,1
	fcb	03,69,3,1
	fcb	03,67,3,1
	fcb	03,69,1,1
	fcb	03,67,1,1
	fcb	03,69,3,1

	fcb	06,15
	fcb	03,100,3,1
	fcb	06,16
	fcb	03,93,3,1
	fcb	00	; End of pattern

pattern_46
	; Voice 2: frame 3841
	fcb	06,15
	fcb	03,97,3,1
	fcb	06,16
	fcb	03,90,3,1

	fcb	06,08
	fcb	03,61,3,1
	fcb	03,61,3,1
	fcb	03,61,5,1
	fcb	03,61,5,1
	fcb	03,59,5,1
	fcb	03,61,1,1
	fcb	03,61,3,1
	fcb	03,61,3,1
	fcb	03,59,3,1
	fcb	03,61,1,1
	fcb	03,59,1,1
	fcb	03,61,3,1

	fcb	06,15
	fcb	03,97,3,1
	fcb	06,16
	fcb	03,90,3,1
	fcb	00	; End of pattern

pattern_47
	; Voice 2: frame 4609
	fcb	06,15
	fcb	03,105,3,1
	fcb	06,16
	fcb	03,98,3,1

	fcb	06,08
	fcb	03,62,3,1
	fcb	03,62,3,1
	fcb	03,62,5,1
	fcb	03,62,5,1
	fcb	03,60,5,1
	fcb	03,62,1,1
	fcb	03,62,3,1
	fcb	03,62,3,1
	fcb	03,60,3,1
	fcb	03,62,1,1
	fcb	03,60,1,1
	fcb	03,62,3,1

	fcb	06,15
	fcb	03,105,3,1
	fcb	06,16
	fcb	03,98,3,1
	fcb	00	; End of pattern

pattern_48
	; Voice 2: frame 4993
	fcb	06,15
	fcb	03,107,3,1
	fcb	06,16
	fcb	03,100,3,1

	fcb	06,08
	fcb	03,64,3,1
	fcb	03,64,3,1
	fcb	03,64,5,1
	fcb	03,64,5,1
	fcb	03,62,5,1
	fcb	03,64,1,1
	fcb	03,64,3,1
	fcb	03,64,3,1
	fcb	03,62,3,1
	fcb	03,64,1,1
	fcb	03,62,1,1
	fcb	03,64,3,1

	fcb	06,15
	fcb	03,107,3,1
	fcb	06,16
	fcb	03,100,3,1
	fcb	00	; End of pattern

pattern_49
	; Voice 2: frame 5377
	; NOTE: THIS IS A HALF-PATTERN (96 frames)
	fcb	06,08	; 'voice 2' snare-instrument
	fcb	03,79,1,1
	fcb	03,79,1,1
	fcb	03,79,1,1
	fcb	03,79,1,1
	fcb	03,79,1,1
	fcb	03,79,1,1
	fcb	03,77,1,1
	fcb	03,79,1,1
	fcb	03,79,1,1
	fcb	03,77,1,1
	fcb	03,79,3,1
	fcb	03,79,1,1
	fcb	03,79,1,1
	fcb	03,77,1,1
	fcb	03,77,1,1

	fcb	00	; End of pattern

pattern_50
	; voice 2 frame 10561
	fcb	06,14	; voice 1 song end drum
	fcb	03,83,7,17

	fcb	06,12	; voice 1 end tom drum
	fcb	03,56,3,1
	fcb	03,56,3,1
	fcb	00	; End of pattern

waveforms_start

; Noisetable: trimmed down to 2048 elements
noise4096
	fcb 34,-13,4,-17,13,-16,-37,12,30,-7,-1,-1,-40,18,-1,33,-18,-9,-25,30,35,-3,25,25,-6,-14,-8,25,13,-34,26,18
	fcb 25,-37,8,34,-36,-18,-41,12,41,16,-5,37,9,-2,14,27,-29,-9,20,35,-35,12,15,-17,-36,-35,40,-14,-36,-31,35,20
	fcb 24,-6,12,-7,31,10,-16,-17,40,33,38,17,-25,-18,-1,14,33,30,-4,3,-8,-40,-37,-23,31,41,39,23,-13,24,1,-21
	fcb 8,10,1,14,31,-32,25,-13,29,-17,-4,25,-37,16,-2,-40,-37,0,8,-29,23,-28,-6,-23,-27,-8,20,-18,-18,33,-13,-25
	fcb 6,25,35,21,-36,-33,19,-14,-20,-23,-20,1,2,24,10,-24,23,38,-11,-2,-21,-28,20,17,33,8,5,-18,29,27,6,-13
	fcb 18,-25,1,-37,4,-4,19,5,-4,38,6,-7,-27,-23,-17,-11,37,-39,26,5,-39,12,-9,31,20,36,9,-3,-25,-2,23,-25
	fcb 18,-39,22,-25,10,6,30,-29,-5,37,4,-13,14,-30,-20,-5,-34,-10,36,14,-5,25,-34,21,37,29,37,27,3,-20,38,-33
	fcb 32,4,-24,-30,17,-9,7,34,25,6,-21,-6,33,-24,15,-32,-19,27,13,-6,-35,-13,37,-32,1,18,11,15,-11,-30,1,-33
	fcb -19,-31,-33,-34,-4,-11,20,9,28,-19,4,-31,30,11,-23,25,-12,-20,18,11,1,-4,12,-5,37,-37,1,4,-22,3,-23,-34
	fcb -8,37,15,2,3,-1,11,10,-1,-3,-10,-35,20,-19,22,31,23,-7,29,-2,12,31,-30,-30,9,-22,-8,-18,28,5,-21,13
	fcb 10,7,-23,-17,32,-16,32,-24,-15,15,-4,-20,27,-18,25,-11,19,-20,15,-12,-2,38,13,-21,-11,23,-37,33,-22,17,-23,-11
	fcb 31,-15,11,-9,11,24,13,-16,2,-1,-5,32,11,2,-25,-36,34,10,15,33,-29,5,-24,14,18,-10,34,36,-15,-30,-28,-13
	fcb 26,4,-36,-24,33,13,-7,16,-31,-8,30,13,21,-10,36,-1,27,2,-12,-16,25,32,20,-24,-36,-4,20,-31,-11,-14,-5,5
	fcb 15,21,-24,-15,-23,34,35,-33,-1,36,-11,-15,-33,11,32,-26,6,30,29,8,-25,36,-29,-26,-33,12,27,-24,17,-2,32,27
	fcb -7,0,29,10,29,-10,16,9,34,30,-26,26,-9,22,-34,-24,24,20,11,-3,11,-23,-27,22,-8,11,8,1,34,-15,28,20
	fcb 0,-19,28,-7,21,36,-12,6,-7,24,4,21,27,19,13,-1,-32,-23,16,13,-29,-6,-16,-21,-19,-28,-20,8,18,32,30,10
	fcb -17,0,17,-32,14,9,30,23,-14,-6,23,16,23,35,18,25,-17,-23,-23,-9,-7,-22,-9,-25,-7,13,24,-14,29,-21,-30,6
	fcb 3,28,31,-13,9,-1,-33,-32,23,-9,-33,8,9,1,0,19,-21,24,29,29,11,0,9,-21,-4,-24,3,10,-4,-14,18,0
	fcb 28,-29,28,-17,15,-11,2,13,23,-2,-23,13,24,22,4,3,-18,-11,25,34,-26,27,12,14,-1,-17,-15,34,0,-31,26,-29
	fcb 4,9,31,-23,-13,0,21,-30,21,-3,-23,-4,-17,-32,33,-19,-7,22,17,4,-24,-2,4,23,-9,19,28,-30,-8,17,12,17
	fcb -9,-15,-14,8,24,20,6,-23,27,-21,21,12,11,11,-15,11,-8,-1,-16,23,-13,19,14,2,3,5,-17,12,3,-13,22,20
	fcb 20,12,-29,2,33,7,-32,19,27,-3,26,-2,-21,27,-16,1,1,2,30,-9,-13,32,31,-2,-21,-1,27,-24,8,-27,-6,-16
	fcb -28,8,-16,-30,1,21,8,5,-13,-22,-31,-23,30,-6,-17,-19,20,-17,-10,26,32,17,8,-23,-30,-7,3,25,-6,-30,25,26
	fcb 31,23,22,5,-11,25,-7,25,-21,-19,13,-10,-7,-11,24,25,26,24,18,3,-6,-13,-13,20,3,-17,7,13,18,4,-21,-10
	fcb -29,-19,11,23,4,16,11,24,-13,0,-5,31,28,-5,-13,7,-23,18,7,10,12,-12,-27,4,21,27,0,11,24,12,2,27
	fcb -8,-3,-1,25,-3,25,-16,0,-23,-28,0,-13,-10,25,28,-26,-3,-12,-30,24,-17,-27,-6,-19,10,0,2,-25,26,27,10,21
	fcb 16,0,26,28,-6,-6,-14,-2,13,19,-16,11,-10,6,18,21,-2,18,-25,-22,-3,-9,-18,-12,-5,26,25,6,-10,-10,12,30
	fcb 10,-15,5,8,29,15,-10,-12,20,21,15,27,27,18,-24,-15,-1,12,22,6,-29,-1,13,-10,-19,-13,16,-24,8,-2,-21,-23
	fcb -18,6,24,13,25,-25,-4,-15,21,-17,-22,-21,-11,-9,5,-7,-5,-3,-14,17,14,-10,11,-5,10,7,-22,13,4,-3,23,11
	fcb -22,1,-13,-7,-23,28,27,-6,20,28,-8,2,12,6,-7,-21,21,0,-23,-3,3,-13,-19,2,-13,-26,22,28,28,24,-11,27
	fcb 21,-28,26,28,3,6,12,5,1,-12,-11,16,6,1,-28,-18,-23,-7,-21,8,5,-16,10,-5,-27,11,23,6,24,-25,-24,-24
	fcb -1,-23,-18,-13,-4,9,23,-2,-16,-12,16,12,4,-1,-5,25,27,5,27,9,-21,6,-20,4,7,14,24,6,3,3,-7,15
	fcb 13,17,27,-19,-20,-9,-19,-4,27,-19,-2,2,-6,0,23,11,-21,14,-16,-18,2,-3,19,-11,-5,-4,6,-11,-14,9,12,13
	fcb 26,-14,-5,22,-20,-6,-3,8,0,-21,25,10,26,-23,-12,-5,10,-4,-13,27,-2,-16,2,11,-5,22,0,-13,-3,-20,-23,-8
	fcb -12,0,-7,-23,-22,-23,-13,-19,-23,-6,15,19,-5,-15,8,21,4,-13,-1,-7,5,24,-8,7,-13,0,-24,-8,17,-12,15,15
	fcb -8,13,7,-3,16,-15,-7,6,11,-11,-8,-21,21,-1,4,12,-9,20,-17,11,18,-13,15,12,-11,-1,7,12,-15,21,6,-24
	fcb 1,-18,23,-20,-11,-19,-22,7,-22,-19,23,9,17,26,-23,-13,-19,-23,-1,12,-12,-15,16,-3,-1,-16,1,17,2,-6,13,16
	fcb 16,21,22,-2,7,10,23,0,-3,-14,17,-17,14,-6,-4,5,14,-4,-1,0,-22,-3,14,22,-2,23,19,-7,21,6,12,8
	fcb 20,-11,-17,-18,-18,-8,-19,-9,14,22,-17,-5,-5,13,-1,11,16,14,-16,-11,4,-18,-3,-14,0,-15,16,-10,9,-23,4,19
	fcb -18,1,24,-19,-12,22,24,21,10,11,20,2,3,18,-5,-11,-5,21,-3,7,-7,23,21,-21,3,-9,-7,20,-14,3,8,4
	fcb -3,21,15,2,2,-23,-2,-21,0,22,-19,23,-10,19,12,12,-8,7,-20,-1,-21,-14,17,24,-12,11,-8,13,-19,10,12,5
	fcb 1,18,17,22,13,1,12,-18,-20,-15,1,-3,10,5,4,-3,-21,15,13,18,0,3,-15,-5,14,23,3,11,-18,0,-19,5
	fcb 5,9,-8,-15,17,23,5,-9,-22,14,20,16,-13,-10,-11,-8,9,-9,-14,-8,9,-7,-12,-7,-16,3,13,17,-17,-2,-11,-20
	fcb 10,12,-11,-13,18,0,-20,7,4,-4,-20,0,-13,10,4,-9,-18,-21,13,-1,12,-5,16,10,15,-21,5,5,-13,7,-11,-16
	fcb -4,2,4,-4,-20,4,4,19,7,1,-4,18,-6,-10,13,17,5,18,-21,-7,-20,-21,-11,-12,-17,18,3,5,3,10,1,14
	fcb 20,-1,-12,-4,9,-3,-16,9,12,12,0,19,-1,14,1,3,-5,19,-13,-15,18,-15,19,-8,15,15,-19,15,4,13,16,18
	fcb -8,-19,18,-17,-3,5,19,-6,-13,11,7,6,-1,12,11,-2,-16,-15,2,-1,-18,-14,-20,-12,3,0,-3,2,12,3,2,20
	fcb -20,12,-3,8,16,-4,12,18,10,-14,-10,-3,-1,-16,18,-1,-9,0,-10,-15,-11,-19,13,17,0,0,18,-9,14,-11,-13,-5
	fcb -7,-10,-9,6,17,-3,9,-2,17,4,-3,18,9,-11,18,-4,15,-14,-7,-10,-6,-11,-11,-8,-1,2,9,11,4,0,11,-13
	fcb -16,-19,19,8,2,18,-7,0,19,14,-8,-14,6,-14,19,9,6,-14,8,-12,-1,10,-4,14,18,-4,14,-13,-18,6,14,-8
	fcb 15,8,18,15,16,12,-2,4,7,7,13,-9,13,-3,9,10,17,4,-7,6,14,-13,-18,-18,-11,10,-8,11,-6,0,-10,-3
	fcb 16,16,1,2,-5,-10,-1,-17,2,11,-18,10,18,-14,-10,2,13,8,13,2,15,0,-15,14,16,1,13,-6,10,-5,-12,-17
	fcb -17,-3,15,-10,-6,-15,-13,10,9,-16,5,0,-17,11,17,16,18,6,18,-12,-13,-3,-15,-3,7,-2,-4,7,11,-14,-6,-6
	fcb 9,12,-11,12,-1,9,3,6,-16,-8,-3,0,15,4,10,5,9,7,-4,17,-7,17,10,-8,3,-4,0,-13,-14,-14,11,-3
	fcb -9,16,-2,0,1,-13,-5,-6,13,-5,16,-13,16,-9,16,16,-13,-16,-2,11,-10,14,1,17,-4,-8,11,-15,-4,-7,-14,-16
	fcb -6,1,3,6,-1,3,-3,-13,-2,-11,13,17,-2,10,-9,-10,8,15,3,8,13,-4,14,10,2,15,12,-7,3,-12,17,9
	fcb -1,-5,0,-13,-3,-10,-13,-11,-2,6,2,-15,12,-13,4,-7,13,11,-13,-13,2,-12,-14,9,-10,-2,16,12,11,3,13,-14
	fcb 11,-7,12,7,2,-5,-9,-2,-5,11,-3,-1,14,-6,5,14,3,14,-10,0,0,-3,-3,8,-14,6,0,-10,-4,-8,0,15
	fcb -8,-10,-3,11,-4,-12,13,6,-9,4,3,6,-1,-7,-8,9,-1,8,14,13,-8,15,9,-5,1,7,4,8,2,-14,10,0
	fcb -13,12,4,-12,-4,-13,9,-4,8,-11,-4,2,-3,-6,5,-11,8,3,-1,2,-4,-7,3,11,7,3,0,2,15,4,-1,-4
	fcb 0,-3,-13,-8,-6,-7,10,8,-1,-5,7,-13,12,-9,4,-13,-1,13,3,11,6,14,-2,3,-4,-4,-11,7,-3,-11,-5,14
	fcb -7,4,-13,-4,14,-5,-1,14,-6,-4,7,-1,-5,-4,-4,-2,-11,-6,-9,5,-6,3,-2,-1,7,-10,-3,7,2,-10,5,6
	fcb 7,3,9,12,2,-3,-2,10,13,-4,-7,-1,13,5,-6,12,11,-11,11,12,-11,-13,-10,-8,-12,-11,-8,-3,2,8,-5,2
	fcb -10,-4,4,5,-9,-8,12,-12,12,-2,12,10,2,3,-5,-11,10,11,1,-11,-1,4,-4,-5,9,-5,-7,3,3,11,-5,-2

; Sintable: 256 elements
sin256
	fcb 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,22,23,24,25,26,27,27,28,29
	fcb 30,30,31,32,32,33,34,34,35,35,36,37,37,38,38,38,39,39,40,40,40,40,41,41,41,41,42,42,42,42,42,42
	fcb 42,42,42,42,42,42,42,41,41,41,41,40,40,40,40,39,39,38,38,38,37,37,36,35,35,34,34,33,32,32,31,30
	fcb 30,29,28,27,27,26,25,24,23,22,22,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1
	rmb	128
	; these remaining values are auto-computed
	;fcb 0,-1,-2,-3,-4,-5,-6,-7,-8,-9,-10,-11,-12,-13,-14,-15,-16,-17,-18,-19,-20,-21,-22,-22,-23,-24,-25,-26,-27,-27,-28,-29
	;fcb -30,-30,-31,-32,-32,-33,-34,-34,-35,-35,-36,-37,-37,-38,-38,-38,-39,-39,-40,-40,-40,-40,-41,-41,-41,-41,-42,-42,-42,-42,-42,-42
	;fcb -42,-42,-42,-42,-42,-42,-42,-41,-41,-41,-41,-40,-40,-40,-40,-39,-39,-38,-38,-38,-37,-37,-36,-35,-35,-34,-34,-33,-32,-32,-31,-30
	;fcb -30,-29,-28,-27,-27,-26,-25,-24,-23,-22,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1

; sawtooth table: 256 elements
saw256
	fcb -42,-42,-42,-42,-41,-41,-41,-40,-40,-40,-39,-39,-39,-38,-38,-38,-37,-37,-37,-36,-36,-36,-35,-35,-35,-34,-34,-34,-33,-33,-33,-32
	fcb -32,-32,-31,-31,-31,-30,-30,-30,-29,-29,-29,-28,-28,-28,-27,-27,-27,-26,-26,-26,-25,-25,-25,-24,-24,-24,-23,-23,-23,-22,-22,-22
	fcb -21,-21,-21,-20,-20,-20,-19,-19,-19,-18,-18,-18,-17,-17,-17,-16,-16,-16,-15,-15,-15,-14,-14,-14,-13,-13,-13,-12,-12,-12,-11,-11
	fcb -11,-10,-10,-10,-9,-9,-9,-8,-8,-8,-7,-7,-7,-6,-6,-6,-5,-5,-5,-4,-4,-4,-3,-3,-3,-2,-2,-2,-1,-1,-1,0
	fcb 0,0,1,1,1,2,2,2,3,3,3,4,4,4,5,5,5,6,6,6,7,7,7,8,8,8,9,9,9,10,10,10
	fcb 11,11,11,12,12,12,13,13,13,14,14,14,15,15,15,16,16,16,17,17,17,18,18,18,19,19,19,20,20,20,21,21
	fcb 21,22,22,22,23,23,23,24,24,24,25,25,25,26,26,26,27,27,27,28,28,28,29,29,29,30,30,30,31,31,31,32
	fcb 32,32,33,33,33,34,34,34,35,35,35,36,36,36,37,37,37,38,38,38,39,39,39,40,40,40,41,41,41,42,42,42

triangle256
	fcb -42,-42,-41,-41,-40,-39,-39,-38,-37,-37,-36,-35,-35,-34,-33,-33,-32,-31,-31,-30,-29,-29,-28,-27,-27,-26,-25,-25,-24,-23,-23,-22
	fcb -21,-21,-20,-19,-19,-18,-17,-17,-16,-15,-15,-14,-13,-13,-12,-11,-11,-10,-9,-9,-8,-7,-7,-6,-5,-5,-4,-3,-3,-2,-1,-1
	fcb 0,1,1,2,3,3,4,5,5,6,7,7,8,9,9,10,11,11,12,13,13,14,15,15,16,17,17,18,19,19,20,21
	fcb 21,22,23,23,24,25,25,26,27,27,28,29,29,30,31,31,32,33,33,34,35,35,36,37,37,38,39,39,40,41,41,42
	fcb 42,42,41,41,40,39,39,38,37,37,36,35,35,34,33,33,32,31,31,30,29,29,28,27,27,26,25,25,24,23,23,22
	fcb 21,21,20,19,19,18,17,17,16,15,15,14,13,13,12,11,11,10,9,9,8,7,7,6,5,5,4,3,3,2,1,1
	fcb 0,-1,-1,-2,-3,-3,-4,-5,-5,-6,-7,-7,-8,-9,-9,-10,-11,-11,-12,-13,-13,-14,-15,-15,-16,-17,-17,-18,-19,-19,-20,-21
	fcb -21,-22,-23,-23,-24,-25,-25,-26,-27,-27,-28,-29,-29,-30,-31,-31,-32,-33,-33,-34,-35,-35,-36,-37,-37,-38,-39,-39,-40,-41,-41,-42

; all values below this point are auto-generated at runtime
mute256		rmb	256

sin256_s1	rmb	256	; volume shifted by 1
sin256_s2	rmb	256	; volume shifted by 2

saw256_s1	rmb	256	; volume shifted by 1
saw256_s2	rmb	256	; volume shifted by 2

triangle256_s1	rmb	256	; volume shifted by 1
triangle256_s2	rmb	256	; volume shifted by 2

square256	rmb	256
square256_s1	rmb	256	; volume shifted by 1
square256_s2	rmb	256	; volume shifted by 2


rect256		rmb	256	; same as square but inverted to help with mixing
rect256_s1	rmb	256
rect256_s2	rmb	256

waveforms_end

;********************
; End
