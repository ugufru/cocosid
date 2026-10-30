# CoCoSID song data

`song.asm` is the tune built into `COCOSID.BIN`, separated from the player.
It covers `$542D-$6394` (3,944 bytes): three song lists, the pattern table
and 50 patterns. `cocosid.asm` pulls it in with `INCLUDE song/song.asm`,
and the whole program still reassembles byte for byte to the original.

`song.asm` is generated; don't edit it by hand unless you mean to change the
tune:

```sh
python3 tools/songdump.py files/COCOSID.BIN > song/song.asm
python3 tools/songdump.py --summary files/COCOSID.BIN   # structure overview
```

## Timing and tuning

The player runs with interrupts off, so all timing comes from cycle counts
on the 0.895 MHz CPU.

| Unit | Length | How it is made |
|---|---|---|
| sample | 77 cycles, 11.6 kHz | one pass of `SAMPLOOP` |
| frame | about 20 ms | one `MIXER` pass of 227 samples; instruments step one frame per pass |
| tick | about 60 ms (16.7 per second) | one sequencer step plus three mixer passes |

All durations in the song data are in ticks. Tick length is estimated
from cycle counts (about 53,600 cycles: 3 × 17,724 for the mixer plus a few
hundred for the sequencer and PWM). Nobody has timed it on hardware yet.

Note numbers follow MIDI numbering (60 = C4), and that is how `song.asm`
names them. Counting the time between mixer passes, the effective sample
rate is about 11.4 kHz. At that rate note 69 (A4) comes out near 425 Hz, so
the whole tune plays roughly half a semitone flat. The original source
intends note 69 to be "A 440 Hz".

## Format

### Song lists

There is one list per voice (`SONG1`, `SONG2`, `SONG3`), with one pattern
number per byte. When a pattern ends, the voice reads the next entry.

| Byte | Meaning |
|---|---|
| `$01-$FE` | play that pattern |
| `$00` | stop this voice (it holds silent) |
| `$FF` | restart the whole song (all voices) |

### Pattern table

`PATTERNS` maps a pattern number to its address, with 2 bytes per entry.
Entry 0 is never used as a pointer, because a 0 in a song list means stop.

### Patterns

A pattern is a stream of commands ending with `ENDPAT`. The macros in
`song.asm` match the player's command numbers:

| Macro | Bytes | Meaning |
|---|---|---|
| `ENDPAT` | `0` | end of pattern; the voice reads its song list |
| `NOP` | `1` | nothing (unused) |
| `DEFINS i` + 15 `FRAME w,p` | `2 i` then 15 × `w p` | define instrument `i` |
| `NOTE n,d,r` | `3 n d r` | play note `n` (see below) |
| `INSTR i` | `6 i` | use instrument `i` for the following notes; `4` and `5` do the same but are unused |
| `BEND x,v` | `7 x hh ll` | set the pitch bend to `v` (`x` is ignored) |
| `BRATE x,v` | `8 x hh ll` | set the bend rate to `v` (`x` is ignored) |

`NOTE n,d,r` takes `d + r` ticks (`d` if `r` is 0):

- **The note itself:** it sounds for `d` ticks, with its envelope looping in
  the sustain frames.
- **When it ends:** the release frames play for one tick, then the voice is
  silent for the rest of the `r` ticks.
- **Ties:** with `r` = 0 there is no release. The next note continues the
  envelope where it is instead of restarting from the attack, which is how
  slurs and slides are written.

`NOTE` is the only command that uses up time. All the others run
immediately, in the same tick as the following note.

Pitch bend (`BEND`, `BRATE`) is only applied to voice 1. The bend is added
to the note's frequency word, and `BRATE` is added to the bend after every
frame, so a non-zero rate makes a glide. Every bend in this song is in a
voice 1 pattern. The typical shape is `BRATE 0,v` before a tied note,
`BRATE 0,0` to stop the glide, and `BEND 7,0` to reset the pitch.

### Instruments

An instrument is 15 frames, one per mixer pass (about 20 ms each):

| Frames | Phase |
|---|---|
| 0-2 | attack: plays once at the start of a note |
| 3-11 | sustain: loops while the note is held |
| 12-14 | release: plays once when the note ends (only if it is followed by a rest) |

Each frame gives a wave and a pitch offset in semitones. The sounding note
is `(note + offset) mod 128`. That is why large negative offsets such as
`-70` wrap round to high notes rather than going very low. Noise waves
(16-23) are pitched another 40 semitones down. Volume envelopes are made by
switching to the half (`2`) and quarter (`4`) amplitude copies of a wave,
and vibrato-like or arpeggio effects by alternating the offset from frame to
frame.

### Waves

| Number | Name | Wave |
|---|---|---|
| 0 | `W_OFF` | silence |
| 1-4 | `W_SINE` `W_SAW` `W_TRI` `W_PULSE` | full amplitude; the pulse is 7/8 high |
| 5-8 | `W_SINE2` ... `W_PULSE2` | the same at half amplitude |
| 9-12 | `W_SINE4` ... `W_PULSE4` | quarter amplitude |
| 13 | `W_PWM` | pulse whose width the player sweeps continuously |
| 14, 15 | `W_PWM2`, `W_PWM4` | half and quarter copies, made at startup; these do not sweep |
| 16-23 | `W_NOISE0` ... `W_NOISE7` | eight different noise tables |

## This song

The tune is Rob Hubbard's music for the Commodore 64 game *Commando*,
converted note by note by hand by the author, Rémi Veilleux. See the
History section of the main README for sources. His source gives the
original's length as "3:56.12 (i.e.: 11806 frames / 96 = 123 patterns)"
and its tempo as 125 BPM.

The song is 3,936 ticks long, about 3 minutes 56 seconds, and then repeats.
Every pattern is 32 or 64 ticks, and the three voices use separate sets of
patterns:

| Voice | Role | Patterns | Instruments |
|---|---|---|---|
| 1 | lead melody | `01`, `05`, `08`-`0B`, `11`-`27` | 2, 6-9, 11-14 |
| 2 | second melody / arpeggios | `06`, `07`, `0F`, `10`, `2D`-`32` | 8, 10, 12, 14-16 |
| 3 | bass and drums | `02`-`04`, `0C`-`0E`, `28`-`2C` | 1, 2, 8, 12, 14 |

Pattern `01` is not music. Voice 1 plays it first, and it defines all 17
instruments in zero ticks.

### Instruments

| # | Frames | Character |
|---|---|---|
| 0 | all `W_OFF` | silence; the player uses it for rests |
| 1 | pulse, fading out in the release | bass |
| 2 | noise and a little quiet saw, gap in the middle | snare-type drum |
| 3, 4, 5 | plain sine, saw, triangle | defined but never used |
| 6, 7, 9 | triangle with a noise click, then alternating 0 / -70, +12, -41 | buzzy triangle leads |
| 8 | pulse with a noise click, then alternating 0 / +12, fading release | octave-arpeggio pulse |
| 10 | pulse and noise for 3 frames, then silence | short click / hi-hat |
| 11 | `W_PWM`, fading in over the attack and out over the release | soft PWM lead |
| 12 | pulse with a noise click, then pitch falling 35 semitones | tom / kick drop |
| 13 | pulse with a noise click and a slight pitch fall, short | pluck |
| 14 | pulse with a noise click, then alternating 0 / -51 | harsh two-tone pulse |
| 15 | triangle and pulse alternating, the pulse at -51 | two-tone triangle |
| 16 | triangle alternating 0 / +12 | octave-arpeggio triangle |

The descriptions come from reading the frames, not from listening.

### Quirks

- **Voice 3's ending:** `SONG3` has no end marker of its own and runs on
  into the pattern table. Its final entry is the first byte of
  `PATTERNS` (the unused entry 0, `$2C00`), so voice 3 plays pattern `$2C`
  and would then read `$00` and stop. All three voices finish on tick
  3,936, though, and voice 1's `$FF` restarts the song first. Neither
  voice 3's implied stop nor the `$00` at the end of `SONG2` is ever reached.
- **Byte after `SONG1`:** the `$00` after `SONG1`'s `$FF` is never read.
- **Unused commands:** `NOP` and instrument commands 4 and 5 never appear;
  every instrument change uses command 6.
- **Bend's ignored byte:** `BEND` always carries the ignored byte 7, and
  `BRATE` always carries 0.
