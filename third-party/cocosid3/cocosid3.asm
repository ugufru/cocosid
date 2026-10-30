; Remi Veilleux, 2010
; This music synthesizer program mimics the sound of a Commodore 64 SID chip
; The music "CRAZY COMETS.SID", by Rob Hubbard, has been converted to my CoCo synth-player music format
; Features:
; - 3 independant channels
; - Square, Sin, Sawtooth, Triangle, and White Noise waveforms
; - Supports Attack, Sustain, Release
; - 3 volume level
; - Glide and pitch bend
; - C64-style Arpeggio
; - 19 KHz realtime mixing quality sound output

; Note: With MESS, use  -wavwrite output.wav to output a wave for analysis


FIRQADDR	equ	$FEF4	* where FIRQ jumps
INIT0		equ	$FF90	* GIME Initialization register 0		
IRQENR		equ	$FF92	* IRQ interrupt source		
FIRQENR		equ	$FF93	* FIRQ interrupt source
VMODE		equ	$FF98	* Video mode - sets lines per row, text/graphics		
VRES		equ	$FF99	* Video resolution - sets size		
BORDERCOLOR	equ	$FF9A	; screen border color
V_OFFSETMSB	equ	$FF9D	* video memory start register msb
V_OFFSETLSB	equ	$FF9E	* video memory start register lsb
H_OFFSET	equ	$FF9F	; horizontal offset + virtual screen  
MMUPAGE		equ	$FFA4	; MMU page register
DISKCONTROLLER	equ	$FF40	; disk controller register
BYTES_PER_ROW	equ	128	; set horizontal resolution in byte per row (at 4 bit per pixel)
PATTERN_LEN	equ	96	; this must match the pattern length in the conversion Perl script

	; Memory mapping:
	; $0000..$0FFF	; free
	; $1000..$3FFF	; source image for splash screen
	; $4000..$7FFF	; code, waveform, music, etc.
	; $8000..$FCFF	; 320x200 16 color graphic page mapped
	
	org $1000
	
; jump to 'real startup' to allow definining procs before using them
start	
	lda	#$10
	tfr	a,dp
	setdp	$10		; DP points to org for fast variable access
	jmp start2

; variables...
modulate_dir	fcb	-1
modulate_index	fcb	255
tmp1		fcb	0
tmp2		fcb	0
tmp3		fcb	0
r4	fcb	12	; used for random generator..
r5	fcb	23
r6	fcb	34
r7	fcb 	45
test_waveform	fcb	0
test_waveform_c	fcb	0

ssynth		struct
freq		rmb	2 	; current frequency
wavetable	rmb	2	; currently active waveform for synth
pattern_counter rmb	1	; count number of notes in current playing pattern
song_ptr	rmb	2	; pointer into song (i.e.: to find the current pattern)
voice_ptr	rmb	2	; pointer into current playing pattern for synth
voice_ptr_backup rmb	2	; pointer backup while decompressing a batch
compress_count	rmb	1	; count how many data remaining to fetch from decompressed batch 
batch_lookup	rmb	256	; lookup table buffer for pattern batch decompressor (8 length * 16 batch * 2 bytes each)
		ends

**********************
; Entry point for sound mixing routine
sound_mix_routine
	; Synth 1: final wave pointer in Y
	ldy	synth1.wavetable
	ldd	synth1.freq
	std	<selfmod_addd_freq1+1	; store into self modifying code the final frequency

	; Synth 2: final wave pointer in U
	ldu	synth2.wavetable
	ldd	synth2.freq
	std	<selfmod_addd_freq2+1	; store into self modifying code the final frequency

	; Synth 3: final wave pointer in S
	lds	synth3.wavetable
	ldd	synth3.freq
	std	<selfmod_addd_freq3+1	; store into self modifying code the final frequency

	; loop for 471 iteration (to output 50Hz)
	; subtract '8' iteration because song processing cost some cycles
	; This means that all synth freq should simulate accumulation for 8 'missed' iteration
	; to compensate.
	ldd	<selfmod_addd_freq1+1	; calculate 'add_freq1 << 3'
	lslb
	rola
	lslb
	rola
	lslb
	rola
	addd	<selfmod_ldd_freq1+1
	std	<selfmod_ldd_freq1+1

	ldd	<selfmod_addd_freq2+1	; calculate 'add_freq2 << 3'
	lslb
	rola
	lslb
	rola
	lslb
	rola
	addd	<selfmod_ldd_freq2+1
	std	<selfmod_ldd_freq2+1

	ldd	<selfmod_addd_freq3+1	; calculate 'add_freq3 << 3'
	lslb
	rola
	lslb
	rola
	lslb
	rola
	addd	<selfmod_ldd_freq3+1
	std	<selfmod_ldd_freq3+1
	
	ldx	#(471-8)
synth_mixer
	; First synth:
selfmod_ldd_freq1	
	ldd	#0000		; 3 
selfmod_addd_freq1	
	addd	#0000		; 4
	std	<selfmod_ldd_freq1+1	; 5
	ldb	a,y		; 5
	stb	<selfmod_addb_synth1+1	; 4  store into self-modify 'addb'
	; Total for synth 1: 21 clocks
	
	; Second synth:	
selfmod_ldd_freq2	
	ldd	#0000		; 3 
selfmod_addd_freq2	
	addd	#0		; 4
	std	<selfmod_ldd_freq2+1	; 5
	ldb	a,u		; 5
	stb	<selfmod_addb_synth2+1	; 4 store into self-modify 'addb'
	; Total for synth 2: 21 clocks
	
	; Third synth:	
selfmod_ldd_freq3	
	ldd	#0000		; 3 
selfmod_addd_freq3	
	addd	#0		; 4
	std	<selfmod_ldd_freq3+1	; 5
	ldb	a,s		; 5
	; Total for synth 3: 17 clocks
	
selfmod_addb_synth1
	addb	#00			; 2
selfmod_addb_synth2
	addb	#00			; 2
	stb	#$FF20		; 5
	; Total for mixing + inner loop: 17
check_org_dp
	if check_org_dp>=$1100
		Problem: code+data too big to fit in same page
	endif

	leax	-1,x		; 5
	bne 	synth_mixer	; 3
	
	; Total for 1 sample loop iteration for 3 channel: (we are not accounting for outer loop, insignificant)
	; 76 clocks
	; Effective sample rate:
	; 1790000 / 76 = 23552.6 Hz
	; To have a C64 Pal frequency of 50Hz, we need to play:
	; 23552.6 / 50 Hz = 471 iteration
	; For a waveform of 256 sample played at 'freq 1.0' (i.e.: freq=256), we have:
	; 23552.6 / 256 = 92.0 Hz
	; Ratio constant to convert C64 SID frequency to CoCoSID frequency:
	; c64 note AF58 (44888) is E-7, which is 2637 Hz
	; CoCoSID is based on freq 92.0 Hz with a 256 sample long waveform
	; 2637 * 256 / 92.0 = 7337.7
	; 44888 / 7337.7 = 6.1174
	; c64 high frequency note AF58 (44888) being equivalent of note (8883) in Coco

	; 'continue' into loop_sound
	
	; waste some time here just to see how it would sound if a game code was running with music
	; Waste about 17556 clocks
	;ldx	#17556/8
!	;leax	-1,x		; 5
	;bne 	<		; 3
	
	
			
*********************************
* main music loop	
loop_sound
	; optimized: no more jsr:
	; process_song, followed by:
	; rect_modulator, followed by
	; sound_mix_routine, 
	; then jmp back to loop_sound
	; no stack usage at all
	; so stack pointer is now invalid

********************
* process_song

process_song
	; process each voice
	ldu	#synth1

process_voice
	; First, check if we need to fetch a new pattern: (i.e.: when our pattern_counter is 00)
	lda	ssynth.pattern_counter,u
	bne 	process_voice_cont
	; Fetch a pattern from song ptr and move song_ptr to next
new_pattern_request
	ldy	ssynth.song_ptr,u
	ldx	,y++
	; if pattern is 0000, we have reached end of pattern data for this track
	lbeq	process_voice_end
	; if pattern is $ffff (-1), special case: instant jump to complete reset/restart
	cmpx	#$ffff
	lbeq	reset_restart

new_pattern_ok
;!	bra	<
	; update pattern counter
	lda	#PATTERN_LEN
	sta	ssynth.pattern_counter,u
	
	; update song ptr
	sty	ssynth.song_ptr,u
	; pattern decompressor: header
	; every time a new pattern begins, we need to build lookup tables
	; for compressed batch of data audio
	ldb	,x+	; fetch 'nb of batch of batch'
	beq	process_voice_cont	; if 0, skip everything: this would need NO compression at all in this pattern
	stb	tmp1	; store for outer loop
pattern_batch_of_batch_next
	ldb	,x	; fetch
	andb	#%00000111	; extract batch_len (remember that batch is stored 'batch_len-1')
	lslb		; multiply by 2 to get 16-bit pointer
	leay	ssynth.batch_lookup,u
	leay	b,y	; prepare 'y' pointer to start offset in lookup table
			; ssynth.batch_lookup is a big 256 bytes buffer used as a 2D-lookup table
			; Indexed:  ((batch_nb<<3)+batch_len-1)<<1
	addb	#2	; adjust 'b' correctly to 'batch_len'

	lda	,x+	; fetch info: nb of batch and batch length: batch_nb always in range [1..15]
	; data is formatted like this: (batch_nb<<3)+batch_len-1
	anda	#%01111000
	sta	tmp2	; extract 'batch_nb' and store into tmp2 for inner loop
	
pattern_batch_next
	stx	,y	; store x pointer into lookup table buffer
	abx		; advance 'x' to skip actual batch data
	leay	16,y	; 8<<1: increase pointer to next entry 

	suba	#8
	bne	pattern_batch_next
	
pattern_batch_of_batch_loop
	dec	tmp1
	bne	pattern_batch_of_batch_next
	
	; save pattern start pointer location
	;stx	ssynth.voice_ptr,u 	; unneeded
	bra	process_new_data
	
	; 'continue' into process_voice_cont


process_voice_cont
	; Process commands from song voice data:
	ldx	ssynth.voice_ptr,u
	
;!	bra <
	; Pattern realtime decompressor:
	; The first byte fetch can be two different things:
	; - A normal uncompressed data: in this case, it is the MSB of a 16-bit data
	; - A compressed data byte: in this case, only one byte (8-bit)
	; To differentiate them, the 5-bit portion 'wave' is used:
	; - If between 0..23: regular uncompressed 16-data
	; - If between 24..31: this is a compressed data byte
		
	; Each uncompressed note data is 16-bit:
	; 11-bit for frequency
	; 5-bit for waveform
	; stored as: (freq>>2) + waveform<<11
	; So resulting operation is:
	; wave = ((DATA 1st byte) & %11111000) >> 3    (wave valid range is [0..23])
	; freq = ((DATA 2 bytes) & %00000111 11111111) << 2
	
	; A compressed data byte is 8-bit:
	; batch_len: 5-bit   batch_len range is [1..8]
	; batch_no: 3-bit    batch_no range is [0..7]
	; Encoded:    (batch_len-1+24)<<5 + (batch_no)

process_new_data	
;!	bra	<
	
	; Enable these lines for waveform test
	; (waveform<<1) + (freq>>1)
	; So: MSB=waveform<<3   LSB=128
	;inc test_waveform_c
	;beq	test_wave_done
	;inc	test_waveform
	;lda	test_waveform
	;anda	#%11111100	; make waveform play 4 times each
	;lsla
	;ldb	#70	; set freq to have a complete period of 471 iteration  (256/471)*256 >> 1 = 70
	;std	,x	;
test_wave_done
	
	lda	,x	; first, extract waveform (from MSB)
	anda	#%11111000 ; 5 bit
	lsra
	lsra
	;lsla		; each waveform lookup is 16-bit so keep it shifted by 1

	; check if wave is a compressed or uncompressed data
	cmpa	#46	; if [0..23]<<1, it is uncompressed
	bls	process_uncompressed
	; No, then it is a compressed byte
	; runtime decompression!
	; example: 	fcb	200		; compressed, batch_len=2, batch no=0, pos=0 batch=[22BE88FB]
	; batch_len tells on many successive frames will be handled by decompressor
	; batch_no and batch_len are used to determine which batch to address in batch_lookup table
	; Indexed:  ((batch_nb<<3)+batch_len-1)<<1
	suba	#48
	lsra	; temporarilly divide by 2..
	inca
	sta	ssynth.compress_count,u	; keep a count = length of this batch [1..8]
	deca
	lsla	; ..then bring back for lookup-table
	adda	#ssynth.batch_lookup
	leay	a,u
	lda	,x+	; fetch byte again, this time extract 'batch_no'
	anda	#%00000111
	lsla
	lsla
	lsla
	lsla	; multiply by 2: 16-bit address
	; get actual 'x' pointer into batch data
	stx	ssynth.voice_ptr_backup,u	; keep x in voice backup
	ldx	a,y	; safe since it never exceeds 127 so no signed stuff to handle
	
	lda	,x	; great, extract our byte!
	anda	#%11111000 ; 5 bit extract waveform (from MSB)
	lsra
	lsra

process_uncompressed	
	ldy	#waveform_lookup
	ldy	a,y
	sty	ssynth.wavetable,u
	std	ssynth.freq,u
	
	ldd	,x++	; now extract freq and advance to next data
;!	bra	<	
	anda	#%00000111	; mask out waveform bits
	lslb
	rola
	lslb
	rola	; shift by 2 because freq is stored >> 2
	std	ssynth.freq,u

	; we are almost done: update pointer
	lda	ssynth.compress_count,u
	beq	process_normally	; if count is 0, we are processing normal uncompressed data, keep going normally.
	deca				; else decrease batch counter
	sta	ssynth.compress_count,u
	bne	process_normally	; if count is not 0, we are still processing a compressed batch, keep going normally
					; else, the batch is finished: bring backup pointer
	ldx	ssynth.voice_ptr_backup,u
process_normally

	stx	ssynth.voice_ptr,u
	dec	ssynth.pattern_counter,u	; decrease note counter to detect end of pattern

process_voice_end
	; now process next voice
	leau	sizeof{ssynth},u
	; check if we have reached past synth3
	cmpu	#synth3+sizeof{ssynth}
	lbne	process_voice
	; when complete, 'continue' into rect_modulator

****************
* modulate the rect waveform over time: simulate a 'LFO' modulation
; Note: only 'rect256' 100% volume is modulated
; not 50% and 25% volume
rect_modulator
	ldx	#rect256
	ldb	modulate_index
	abx
	lda	modulate_dir
	beq	rect_mod_dir_0
rect_mod_dir_1	
	lda	#0
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
	lda	#84
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
	jmp	sound_mix_routine	; jump to sound mixing

************************************
* real start of program

************************************************
start2	
	; initalize:
	orcc	#$50		* disable interrupts
	sta	$FFD9		* high speed poke (1.79 Mhz)
	
	lds	#$FF00		; set stack starting at $FF00

	; Disable PIA HSYNC and VSYNC irq
	lda	$FF01
	anda	#%11111110
	sta	$FF01
	
	lda	$FF03
	anda	#%11111110
	sta	$FF03
	
	clr	DISKCONTROLLER  ; turn off all drive motors immediately
	
	clr	FIRQENR		* disable the interrupt register
	clr	IRQENR		* disable these to be safe
	
	lda 	#%01111100 	* Coco3, MMU on, DRAM constant, IRQ on, FIRQ on, Vector RAM at FEXX on, standard SCS, 16K internal 16K external ROM
	sta 	INIT0
	
	; init graphic mode
	lda	#%10000000	
	sta	VMODE 		* graphics mode, 60 hz, normal burst, 1 line per row
	lda	#%00111110 	* Line Per Field 200 lines, Horizontal 128 bytes per row, 16 Colors (4bpp) 256 * 200
	sta	VRES
; A graphic page requires: 160 * 200 = 32000 bytes ($7D00)
	
	ldd	#$C000		* first block of graphics screen at $60000 / 8
	std	V_OFFSETMSB	* vidstart offset
	
	;lda	#57		; Mimic C64 border color 57 = 170 170 255
	lda	#63		; white
	sta	#BORDERCOLOR
	
	;lda	#$30 * set the memory page at $8000..$FD00
	;jsr	SetGraphicsMem

	;jsr	setpalette
	;jsr	clearscreen
	;jsr	copy_title
	
	jsr	generate_waveform
	
	; entry point for reset/restart song completely
reset_restart
	lds	#$FF00		; set stack starting at $FF00
	;jsr	reset_vu
	jsr	init_sound
	jmp	loop_sound

*************************
* initialize sound output
init_sound
	LDA $FF23 ; SOUND CONTROL: turn on sound
	ORA #8	
	STA $FF23
	
	LDA $FF21
	ANDA #^4 SET FOR DATA DIRECTION
	STA $FF21
	
	LDB $FF20 GET CURRENT DIRECTIONS
	LDB #%11111100 DAC-OUT, TAPE&RS-232:IN
	STB $FF20
	
	ORA #4 RESET TO NORMAL

	STA $FF21
	
	; initialize song
	; Initialize start values for all synth
	ldd	#song_voice1
	std	synth1.song_ptr
	ldd	#song_voice2
	std	synth2.song_ptr
	ldd	#song_voice3
	std	synth3.song_ptr
	clra
	clrb
	sta	synth1.pattern_counter
	sta	synth2.pattern_counter
	sta	synth3.pattern_counter

	ldd	#mute256	; set all voice initially to 'mute'
	std	synth1.wavetable
	std	synth2.wavetable
	std	synth3.wavetable
	rts

******************** generate waveforms:
generate_waveform
; generate square:
	ldx	#square256
	lda	#224	; 224 / 32 is a pulse wave,   128 / 128 would be a perfect square wave
			; since only track 1 in Battle Valley uses square wave
	ldb	#85	; note: using values over maximum range 0..84
!	stb	,x+
	deca
	bne	<
	lda	#32
	ldb	#0
!	stb	,x+
	deca	
	bne	<
	
; generate rect:
	ldx	#rect256
	lda	#88	; 224 / 32 is a pulse wave,   128 / 128 would be a perfect square wave
	ldb	#0	; inverted of square for better mixing
!	stb	,x+
	deca
	bne	<
	lda	#(256-88)
	ldb	#84
!	stb	,x+
	deca	
	bne	<
	
;generate mute:
	ldx	#mute256
	lda	#0	; loop 256 times, 
	ldb	#42	; fill with '42'
!	stb	,x+
	deca
	bne	<
	
;generate sawtooth
	ldx	#saw256
	lda	#85	; loop 85 times
	ldb	#0	; start at 0
	stb	,x+
!	stb	,x+
	stb	,x+
	stb	,x+
	incb
	deca
	bne	<

;generate triangle
	ldx	#triangle256
	lda	#42	; loop 42 times
	ldb	#0	; start at 0
	stb	,x+
!	stb	,x+
	incb
	stb	,x+
	stb	,x+
	incb
	deca
	bne	<
	stb	,x
	ldx	#triangle256
	lda	#128	; loop 128 times (we only 'mirror' half the triangle)
!	ldb	#85
	subb	,x+
	stb	127,x
	deca
	bne	<
	
; generate sin
	ldx	#triangle256
	ldy	#sin256
	lda	#0	; loop 256 times: sin is a copy of triangle to save some memory
!	ldb	,x+
	stb	,y+
	deca
	bne	<
	
; generate noise	
	ldx	#noise2048
	;lda	#23
	;ldb	#97
	; super simple pseudo-random generator
noise_gen_loop
	;mul
	;addd	#5167
	;stb	tmp1
; 31-bit random number 
; primitive polynomial order 31 
; (1)0100000 10101010 10010101 10110101 (20 AA 95 B5) 
; shift before XOR

rand_31
   	lsl   r4         ; shift first 
   	rol   r5
   	rol   r6 
   	rol   r7
   	ldb	r7
   	andb	#%10000000 ; test MSB 
   	beq	rand_done            ; clear, no XOR
   	ldb	r4
   	eorb	#$B5	; first poly byte XOR it in
   	stb	r4
   	ldb	r5
   	eorb 	#$95    ; second byte of poly
   	stb	r5
   	ldb	r6
   	eorb	#$AA      ; same routine
   	stb	r6
   	ldb	r7
   	eorb	#$20
   	stb	r7 
rand_done
   	ldb	r7
   	eorb	r6
   	eorb	r5
   	eorb	r4

	lsrb	; try to keep 'b' in valid range [0..85]
	cmpb	#85
	bhi	rand_31	; recompute a new random
noise_continue
	stb	,x+
	cmpx	#noise2048+2048
	bne	noise_gen_loop
	
; fade 510 last entries in noise	
	ldx	#noise2048+2048-510
	lda	#0
	sta	tmp1	; tmp1 is recenter offset
	lda	#6
	sta	tmp2	; tmp2 is counter before moving recenter
	; each entry is reduced progressively to 0 but recentered at 42
	lda	#255
	sta	tmp3	; tmp3 is current attenuation value
noise_fade_loop
	lda	tmp3
	ldb	,x
	mul
	adda	tmp1
	sta	,x+

	lda	tmp3
	ldb	,x
	mul
	adda	tmp1
	sta	,x+
	dec	tmp2	; keep track of recentering: goes from 0 to 42, inc by 1 every 6 iteration
	bne	noise_fade_cont
	lda	#6
	sta	tmp2
	inc	tmp1
noise_fade_cont
	dec	tmp3
	bne	noise_fade_loop

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
	
	rts
	
********************** waveform_volume_half
* Half the volume of a 256 sample fragment into a destination area
* input:
* 'x': points to source sample buffer
* 'y': points to destination sample buffer
waveform_volume_half
	lda	#0
!	ldb	,x+
	asrb		; divide waveform by 2
	addb	#21	; re-center waveform (needed because waveform is unsigned centered at 42)
	stb	,y+
	deca
	bne	<
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
	
	fdb	noise2048+128		; 16 Noise: waveform 16..23 will have their frequency lowered to 'match'
	fdb	noise2048+256+128	; 17        the C64 white noise which seems to play a lot lower (by NOISE_FREQ_DOWN)
	fdb	noise2048+512+128	; 18
	fdb	noise2048+768+128	; 19
	fdb	noise2048+1024+128	; 20
	fdb	noise2048+1280+128	; 21
	fdb	noise2048+1536+128	; 22
	fdb	noise2048+1792+128	; 23
	
	include crazycomets_t1.cid
	include crazycomets_t2.cid
	include crazycomets_t3.cid

	; indicator to where the important initialized memory portion finishes
ZZZLASTSYMBOL
	if ZZZLASTSYMBOL>$7E80
		Danger: code+data exceed safe limit. Bad thing could happen because of BASIC stack overwriting.
	endif

	; complete mystery: if I put 2048 here, program crash.
	; noise is 2048 bytes long but for some LOADM / basic / stack / mysticism reason,
	; it crashes the CPU while loading the program
noise2048	rmb  4096
	;fcb 18,45,77,27,37,55,1,39,24,37,24,73,20,63,75,23,70,22,40,29,60,40,52,38,9,38,40,66,71,77,73,25
	;fcb 23,33,48,77,38,16,15,7,58,41,16,60,74,57,58,7,73,23,32,83,11,12,26,58,3,66,74,82,76,15,60,59
	;fcb 28,81,72,25,78,52,71,61,54,14,21,75,20,20,6,57,82,78,65,1,70,34,2,38,51,54,38,47,7,2,78,56
	;fcb 60,51,78,24,65,40,56,49,62,0,17,31,55,60,39,6,23,8,19,77,65,46,14,71,60,44,75,57,25,1,10,54
	;fcb 28,61,70,80,4,67,62,56,17,43,61,35,52,77,55,8,48,60,23,29,10,33,41,64,80,83,69,61,50,17,24,69
	;fcb 70,63,47,50,83,15,46,64,80,20,32,47,63,15,72,31,22,58,28,25,14,24,17,73,44,49,64,30,16,18,74,17
	;fcb 37,10,83,73,80,63,84,37,44,68,55,52,71,34,59,21,40,2,63,5,31,11,76,53,28,79,12,46,39,16,57,48
	;fcb 9,30,74,57,40,12,31,3,10,68,77,59,71,83,18,79,79,60,61,13,28,27,48,24,76,58,26,46,77,67,79,41
	;fcb 34,80,78,17,21,47,33,59,54,77,39,15,73,72,70,30,4,67,36,35,71,68,55,73,36,42,41,74,21,20,25,24
	;fcb 47,39,61,77,11,58,14,26,48,67,42,62,12,42,31,20,75,28,76,80,67,6,80,11,64,5,71,27,24,22,67,6
	;fcb 38,41,66,47,10,66,19,49,9,14,10,24,11,76,9,9,14,36,7,12,24,11,57,60,34,11,35,83,3,10,74,66
	;fcb 54,53,43,14,31,52,40,83,7,68,28,7,32,51,58,21,21,18,72,58,47,44,39,79,44,38,14,19,55,53,34,5
	;fcb 27,45,16,4,16,43,22,65,84,38,3,52,52,57,14,63,15,72,82,43,84,25,31,81,79,70,83,58,36,8,53,34
	;fcb 30,75,7,69,5,23,27,81,82,80,7,58,62,59,0,36,54,44,8,73,12,7,68,60,9,6,52,26,70,33,20,3
	;fcb 21,32,24,26,52,25,67,32,70,9,15,30,64,68,7,81,81,39,69,20,60,0,54,75,16,5,65,26,40,77,24,84
	;fcb 15,65,71,61,52,40,19,53,1,69,81,83,77,55,57,62,12,79,52,39,48,61,9,84,81,56,85,13,12,49,23,6
	;fcb 83,69,57,39,1,19,51,6,56,83,81,15,44,37,39,81,72,17,75,50,62,38,76,23,72,69,70,53,65,71,5,75
	;fcb 9,28,54,21,77,44,21,75,44,45,54,75,10,73,45,52,33,50,79,84,30,75,4,67,83,37,53,67,37,58,82,66
	;fcb 62,11,42,9,47,73,82,0,3,36,28,23,31,16,32,40,62,39,80,25,68,27,4,32,8,47,61,83,34,54,58,77
	;fcb 53,8,75,24,29,23,77,13,25,58,26,71,6,18,78,5,41,16,3,37,45,44,66,54,52,12,26,67,4,62,27,19
	;fcb 22,10,31,31,73,25,57,70,2,26,62,27,19,19,38,60,80,15,19,51,16,70,43,83,50,22,44,12,79,47,31,36
	;fcb 61,11,36,16,69,2,20,27,53,32,57,66,82,6,59,44,4,74,36,25,50,6,80,49,65,84,32,17,66,19,65,0
	;fcb 67,6,36,74,7,6,0,58,13,83,9,43,49,12,65,32,31,64,41,22,57,55,15,31,43,36,67,38,39,31,71,21
	;fcb 74,80,56,70,59,51,66,66,26,19,78,10,43,29,17,81,15,27,10,47,48,41,61,9,74,60,53,50,84,14,25,17
	;fcb 5,66,25,62,73,24,63,19,40,24,75,42,31,9,78,59,30,9,83,43,44,1,40,26,45,1,51,58,46,27,25,61
	;fcb 6,51,38,48,77,28,46,37,56,27,61,69,77,35,23,70,41,58,51,62,82,18,64,23,72,46,32,1,41,6,32,35
	;fcb 26,44,9,49,29,42,15,52,46,49,1,42,4,63,0,32,66,56,39,8,42,50,25,6,70,44,43,14,24,16,42,59
	;fcb 68,54,15,24,70,4,7,60,39,24,24,23,73,12,23,9,8,55,76,67,70,16,18,50,10,17,38,1,51,81,84,62
	;fcb 23,9,40,43,14,66,8,41,35,61,79,14,49,15,53,53,83,27,14,22,72,50,4,38,5,77,48,60,21,18,53,42
	;fcb 5,8,61,29,29,4,37,40,2,16,24,38,50,80,3,22,52,31,40,20,54,75,64,7,52,79,13,56,16,28,50,62
	;fcb 15,69,45,14,40,61,65,84,52,4,48,59,35,5,74,14,71,43,74,63,32,60,56,59,36,55,31,51,45,15,37,81
	;fcb 27,43,39,53,72,15,10,11,12,56,78,64,66,58,77,20,13,43,31,6,37,19,44,24,64,38,25,43,47,16,13,42
	;fcb 66,37,78,55,77,31,83,67,18,37,32,65,43,43,28,17,60,12,70,68,28,11,43,51,49,63,81,56,59,27,10,36
	;fcb 48,78,22,40,21,63,15,51,10,68,75,11,54,64,63,43,26,19,4,67,63,56,16,18,40,84,18,51,45,5,12,53
	;fcb 26,23,63,50,52,26,1,2,64,20,24,47,27,15,10,38,37,53,64,14,41,49,45,37,59,56,76,16,70,35,35,63
	;fcb 25,74,43,67,78,48,12,23,62,18,30,1,75,4,74,3,18,18,46,31,48,13,77,33,15,23,59,44,39,79,46,18
	;fcb 41,9,54,9,20,51,56,29,24,24,63,64,68,15,69,10,35,76,79,8,9,19,10,83,39,32,21,84,43,60,46,20
	;fcb 41,35,7,77,65,84,3,3,26,85,2,27,60,79,13,24,40,52,30,27,35,12,29,73,67,46,6,25,14,29,70,70
	;fcb 48,20,62,69,77,71,16,77,30,80,58,46,34,14,44,79,41,30,10,27,81,66,15,42,4,31,51,33,69,82,18,64
	;fcb 53,6,30,62,16,69,35,26,54,64,8,42,70,25,79,18,16,9,39,53,27,48,54,10,64,43,13,43,83,23,80,49
	;fcb 23,37,56,71,24,7,34,31,1,6,47,50,7,22,71,8,0,78,46,7,25,37,11,65,10,52,84,14,28,39,56,53
	;fcb 60,76,18,51,5,31,24,84,0,50,21,40,37,45,4,24,84,72,33,67,68,75,40,19,83,35,22,16,61,21,33,3
	;fcb 72,2,45,67,42,77,48,73,68,2,24,8,25,9,72,27,72,1,82,12,78,76,74,6,72,51,0,55,12,79,50,59
	;fcb 18,36,1,35,66,40,16,39,19,10,56,57,21,44,73,39,82,44,11,68,74,3,83,58,76,82,16,78,62,24,9,25
	;fcb 2,65,83,67,17,32,41,4,66,55,26,62,0,71,13,69,31,45,54,62,5,30,70,16,78,26,58,54,69,55,19,25
	;fcb 11,60,55,43,20,39,14,55,50,36,4,3,39,55,16,18,63,22,15,13,4,40,71,44,35,36,23,63,72,75,51,80
	;fcb 4,81,12,38,44,6,35,7,41,25,50,57,55,7,72,26,36,78,27,50,44,43,75,33,43,17,52,37,37,31,25,22
	;fcb 80,23,42,66,71,12,64,79,77,10,48,84,66,68,34,42,36,65,47,72,29,11,17,23,83,42,27,18,32,4,69,5
	;fcb 55,34,54,77,10,6,13,51,82,69,46,52,18,83,45,83,33,7,23,82,45,46,39,37,24,23,71,71,50,31,4,77
	;fcb 53,15,36,48,39,69,80,21,39,28,76,39,36,32,30,64,53,18,61,32,25,41,59,76,42,37,53,35,18,27,22,24
	;fcb 9,34,49,63,14,74,78,62,64,48,14,59,14,19,28,50,15,36,21,52,71,20,40,51,35,76,75,21,33,33,16,19
	;fcb 56,72,64,62,42,34,33,71,13,50,31,69,14,23,32,10,40,21,59,56,67,39,46,15,36,70,13,65,46,51,62,49
	;fcb 12,54,51,21,22,57,54,25,74,38,58,55,31,60,58,32,71,64,37,60,64,49,30,56,46,31,13,29,31,52,61,29
	;fcb 20,48,45,58,63,18,69,67,14,19,39,26,69,56,29,52,45,66,20,35,51,42,36,54,48,27,62,49,34,46,18,52
	;fcb 56,48,63,53,39,19,45,22,23,53,37,53,32,40,66,63,58,59,49,28,27,43,61,67,63,55,45,36,44,18,58,23
	;fcb 37,53,65,37,62,55,32,49,23,37,41,58,55,57,39,52,64,24,54,36,48,45,35,35,45,23,60,33,59,26,59,46
	;fcb 23,61,63,42,43,61,36,26,32,34,41,40,63,35,45,44,62,32,27,28,30,26,47,32,30,35,49,36,46,48,37,61
	;fcb 41,37,25,25,45,53,38,59,46,46,28,50,50,55,50,46,38,54,34,30,35,29,28,26,31,48,42,54,27,52,52,56
	;fcb 28,58,29,33,45,27,39,38,54,43,55,30,54,57,46,55,39,42,46,36,44,30,40,48,42,39,54,41,45,38,33,50
	;fcb 52,55,30,43,35,53,50,37,39,38,42,37,43,48,41,38,51,50,44,48,47,32,49,36,50,48,40,52,32,45,48,48
	;fcb 44,43,47,50,38,38,41,42,34,37,36,39,50,45,47,39,39,42,40,50,45,44,45,37,43,34,40,42,36,40,41,47
	;fcb 44,46,48,39,46,42,43,42,45,44,40,42,40,47,42,40,36,39,39,44,41,47,37,37,42,43,48,43,46,37,40,44
	;fcb 46,46,38,39,45,41,45,44,42,45,40,41,42,46,38,41,44,44,40,45,40,42,41,46,42,44,43,45,41,42,45,45
	;fcb 40,40,45,41,43,42,41,41,42,41,44,43,44,44,41,42,44,43,42,43,42,42,42,43,43,43,42,42,43,42,42,43

; sawtooth table: 256 elements
saw256	rmb	256
	;fcb 0,0,0,0,1,1,1,2,2,2,3,3,3,4,4,4,5,5,5,6,6,6,7,7,7,8,8,8,9,9,9,10
	;fcb 10,10,11,11,11,12,12,12,13,13,13,14,14,14,15,15,15,16,16,16,17,17,17,18,18,18,19,19,19,20,20,20
	;fcb 21,21,21,22,22,22,23,23,23,24,24,24,25,25,25,26,26,26,27,27,27,28,28,28,29,29,29,30,30,30,31,31
	;fcb 31,32,32,32,33,33,33,34,34,34,35,35,35,36,36,36,37,37,37,38,38,38,39,39,39,40,40,40,41,41,41,42
	;fcb 42,42,43,43,43,44,44,44,45,45,45,46,46,46,47,47,47,48,48,48,49,49,49,50,50,50,51,51,51,52,52,52
	;fcb 53,53,53,54,54,54,55,55,55,56,56,56,57,57,57,58,58,58,59,59,59,60,60,60,61,61,61,62,62,62,63,63
	;fcb 63,64,64,64,65,65,65,66,66,66,67,67,67,68,68,68,69,69,69,70,70,70,71,71,71,72,72,72,73,73,73,74
	;fcb 74,74,75,75,75,76,76,76,77,77,77,78,78,78,79,79,79,80,80,80,81,81,81,82,82,82,83,83,83,84,84,84
	
triangle256	rmb 256
	;fcb 0,0,1,1,2,3,3,4,5,5,6,7,7,8,9,9,10,11,11,12,13,13,14,15,15,16,17,17,18,19,19,20
	;fcb 21,21,22,23,23,24,25,25,26,27,27,28,29,29,30,31,31,32,33,33,34,35,35,36,37,37,38,39,39,40,41,41
	;fcb 42,43,43,44,45,45,46,47,47,48,49,49,50,51,51,52,53,53,54,55,55,56,57,57,58,59,59,60,61,61,62,63
	;fcb 63,64,65,65,66,67,67,68,69,69,70,71,71,72,73,73,74,75,75,76,77,77,78,79,79,80,81,81,82,83,83,84
	;fcb 84,84,83,83,82,81,81,80,79,79,78,77,77,76,75,75,74,73,73,72,71,71,70,69,69,68,67,67,66,65,65,64
	;fcb 63,63,62,61,61,60,59,59,58,57,57,56,55,55,54,53,53,52,51,51,50,49,49,48,47,47,46,45,45,44,43,43
	;fcb 42,41,41,40,39,39,38,37,37,36,35,35,34,33,33,32,31,31,30,29,29,28,27,27,26,25,25,24,23,23,22,21
	;fcb 21,20,19,19,18,17,17,16,15,15,14,13,13,12,11,11,10,9,9,8,7,7,6,5,5,4,3,3,2,1,1,0

; Sintable: 256 elements
sin256	rmb	128
	;fcb 42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,64,65,66,67,68,69,69,70,71
	;fcb 72,72,73,74,74,75,76,76,77,77,78,79,79,80,80,80,81,81,82,82,82,82,83,83,83,83,84,84,84,84,84,84
	;fcb 84,84,84,84,84,84,84,83,83,83,83,82,82,82,82,81,81,80,80,80,79,79,78,77,77,76,76,75,74,74,73,72
	;fcb 72,71,70,69,69,68,67,66,65,64,64,63,62,61,60,59,58,57,56,55,54,53,52,51,50,49,48,47,46,45,44,43
	rmb	128
	; these remaining values are auto-computed
	;fcb 42,41,40,39,38,37,36,35,34,33,32,31,30,29,28,27,26,25,24,23,22,21,20,20,19,18,17,16,15,15,14,13
	;fcb 12,12,11,10,10,9,8,8,7,7,6,5,5,4,4,4,3,3,2,2,2,2,1,1,1,1,0,0,0,0,0,0
	;fcb 0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,4,4,4,5,5,6,7,7,8,8,9,10,10,11,12
	;fcb 12,13,14,15,15,16,17,18,19,20,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41

synth1		ssynth
synth2		ssynth
synth3		ssynth

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

	

*********************
* End
	;setdp $00		; This must be set or else the program crashes.
	
	; This section must be placed at the end of code absolutely 
	ORG	356		; force an automatic execute after LOADM
	JMP	>start
	JMP	>start
	JMP	>start
	END start
