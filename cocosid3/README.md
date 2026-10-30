# COCOSID3

COCOSID3 is the author's last CoCoSID, from 2012. It plays the C64 *R-Type*
music (Chris Hülsbeck and Ramiro Vaca, 1988), converted automatically from a
`.sid` file with SIDDUMP and his Perl script. It needs a CoCo 3.

Rather than disassembling it, this folder rebuilds it from the author's own
source. The source is in `third-party/cocosid3/cocosid3.asm`, but his package
left out the three song files it includes. Those were recovered from the
binary, and with them his source assembles to exactly the bytes in
`COCOSID3.BIN`.

| File | What it is |
|---|---|
| `../files/cocosid3/COCOSID3.BIN` | The program, 10,336 bytes, extracted from `third-party/rem-texture-demo/REM_TEXTURE_DEMO.dsk` |
| `cocosid3.asm` | The author's source, made lwasm-compatible (generated) |
| `song/crazycomets_t1.cid` ... `t3.cid` | The song for voices 1 to 3, recovered from the binary (generated) |

The song files keep the author's names. His source still calls the song
"CRAZY COMETS" because he first tried that tune and kept the file names when
he switched to *R-Type* (see his archived CoCoSID3 page, linked in
`third-party/README.md`).

## Building and checking

```sh
python3 tools/cid3dump.py files/cocosid3/COCOSID3.BIN cocosid3/song
python3 tools/cocosid3_lwasm.py third-party/cocosid3/cocosid3.asm > cocosid3/cocosid3.asm
lwasm --format=decb -I cocosid3/song -o OUT.BIN cocosid3/cocosid3.asm
python3 tools/decb_cmp.py OUT.BIN files/cocosid3/COCOSID3.BIN
```

`decb_cmp.py` compares what the two files load into memory. All 10,311
loaded bytes and the exec address are identical. `cmp` alone reports a
difference because the files are blocked differently: his assembler wrote
`$1000-$1011` as a block of its own, and lwasm merges it with the
following block.

`cocosid3_lwasm.py` makes six small edits, each listed in the script:

- **Two stores written with `#`:** `stb #$FF20` and `sta #BORDERCOLOR`.
  His assembler took them as extended addressing.
- **Two size guards removed:** their bodies are deliberate syntax errors,
  and lwasm can't evaluate one of the tests on its first pass.
- **`pragma noindex0tonone`:** his assembler encodes `std ssynth.freq,u`,
  whose offset is 0, as `0,u` (`ED 40`). lwasm would shorten it to `,u`
  (`ED C4`).
- **Voice records emitted:** his assembler wrote the three voice records
  out as 804 zero bytes at `$481A-$4B3D`, so lwasm is told to do the same.

`cid3dump.py` checks as it decodes: every pattern must be exactly 96 frames,
every compressed byte must refer to a batch its pattern defines, and every
pattern must be played by the song list that follows it.

## Running it

```sh
xroar -machine coco3 -rompath ~/.xroar/roms -cart rsdos -run files/cocosid3/COCOSID3.BIN
```

It starts by itself after `LOADM` as well: the last block writes
`JMP $1000` three times over BASIC's RAM hooks at `$0164-$016C`.

## Memory map

| Address | Contents |
|---|---|
| `$1000-$1376` | Player: variables, mixer, song processing, PWM, start-up, wave generation, `waveform_lookup` |
| `$1377-$1C9C` | Voice 1 patterns (23) |
| `$1C9D-$1D5A` | `song_voice1`: 93 pattern pointers, `$FFFF`, `0000` |
| `$1D5B-$286E` | Voice 2 patterns (22) |
| `$286F-$292C` | `song_voice2` |
| `$292D-$345B` | Voice 3 patterns (25) |
| `$345C-$3519` | `song_voice3` |
| `$351A-$4519` | `noise2048`, built at start-up (4,096 bytes reserved, 2,048 used) |
| `$451A-$4819` | Saw, triangle and sine tables, built at start-up |
| `$481A-$4B3D` | Voice records `synth1` to `synth3`, 268 bytes each |
| `$4B3E-$583D` | Silence and the other 12 wave tables, built at start-up |

DP is `$10`. The mixer's self-modifying operands must stay in
`$1000-$10FF` so they can be written with direct-page stores, and the first
size guard checked that.

## What changed since the 2010 player

The CoCo 2 build in this repository (`cocosid.asm`, source dated
2010-02-13) and COCOSID3 share the wave tables and the mixer design. How
the music is described changed completely.

### The music is a register dump, not a score

The 2010 player is a small sequencer. Patterns hold notes with durations,
and 15-frame instruments supply the attack, sustain and release, the
arpeggios and the noise clicks. Pitch bend works on voice 1 only.

COCOSID3 has no notes, instruments or commands at all. Each voice gets one
16-bit word per frame:

| Bits | Meaning |
|---|---|
| 15-11 | wave, 0-23 (the same numbering as the 2010 player) |
| 10-0 | frequency, stored divided by 4 |

The Perl script works all of this out from SIDDUMP's frame-by-frame dump
of the C64 SID registers. Envelopes become switches between the full,
half and quarter volume wave copies, and slides and vibrato become
per-frame frequencies. That is why any voice can now glide, and why the
player has no note table.

### Compression

A pattern is 96 frames. Stored raw, that is 192 bytes per voice, about
53 KB for the whole song, which is too much. The converter shrinks it in
two ways:

- **Repeated patterns are stored once.** The song list repeats the pointer.
  There are 70 unique patterns for the 279 played.
- **Repeated runs within a pattern become one byte.** Each pattern starts
  with a header of *batches*, runs of 1 to 8 frames that recur in it. In
  the data stream, a byte whose top five bits are 24-31 stands for "play
  batch *n* of length *L*" instead of a frame word. When a pattern starts,
  the player builds a 256-byte lookup table of batch addresses in the
  voice record (`batch_lookup`). It then expands the references frame by
  frame as it plays.

The 70 patterns take 8,041 bytes instead of 13,440. With the song lists,
the music is 8,611 bytes.

### Song lists

There is a list of 16-bit pattern addresses per voice, instead of 8-bit
pattern numbers looked up in a table. `$FFFF` restarts the song and `0000`
stops the voice, as before.

### Timing: one C64 frame per pass

| | 2010 CoCo 2 build | COCOSID3 |
|---|---|---|
| CPU | 0.895 MHz | 1.79 MHz (`sta $FFD9`) |
| Sample loop | 77 cycles, about 11.6 kHz | 76 cycles, about 23.6 kHz (author's figure 23,552 Hz) |
| Mixer pass | 227 samples | 463 samples (471 less 8) |
| Song step | a tick: 3 mixer passes, about 60 ms | one frame per mixer pass, aiming at the C64's 50 Hz |

The song advances once per mixer pass, matching the C64 player's one call
per PAL frame. The song processing takes about 8 samples' worth of time,
so the mixer runs 463 samples instead of 471. Before each pass it advances
each voice's phase by 8 × its frequency (`lsl` three times), so the
waveforms stay in step across the gap.

The main loop no longer calls anything: song processing falls into the
PWM update, which falls into the mixer, which jumps back. The stack pointer
is used as the third voice's wave pointer during the mix, so the loop never
touches the stack. The 2010 player also borrows S in the mixer, but saves
and restores it.

### Waves

- **Same 24 entries:** silence; sine, saw, triangle and pulse at three
  volumes; the PWM rectangle at three volumes; and 8 noise tables.
- **Sine is a copy of the triangle** "to save some memory". The
  commented-out sine data is still in the source.
- **Noise is generated at start-up** by a 31-bit LFSR, then the last 510
  bytes are faded towards the centre. The 2010 build stores its noise
  table in the program.
- **PWM sweep:** `rect_modulator` is the same idea as before. It sweeps
  4 bytes of the 100% rectangle per frame, and the half and quarter copies
  don't sweep.

### What this song uses

Counting every frame word in the three `.cid` files, batches included,
the full-volume PWM rectangle (wave 13) dominates with 1,323. Next come
the pulse (464), the half-volume rectangle (378), wave 1 (the
triangle-shaped "sine", 327) and the first noise table (306). The saw and
triangle tables (waves 2, 3, 6, 7, 10 and 11) never appear.

The song is 93 patterns of 96 frames, 8,928 frames. At 50 Hz that is
2:58.6, which fits the author's 180-second SIDDUMP run trimmed to whole
patterns. Nobody has timed it in an emulator or on hardware yet.

### Display

The start-up code sets the GIME to a 256 × 200, 16-colour graphics mode
and a white border. The calls that would set the palette, clear the screen
and copy a title picture are commented out, so the screen shows whatever
is in that video memory. In XRoar that is a screen of random patterns
while the music plays.
