# The CoCo 3 build and the CoCo 2 port

The first CoCoSID (*Commando*, by hand) exists in two builds, and the
author's source survives for both:

| | CoCo 3 | CoCo 2 (this repository) |
|---|---|---|
| Source | `third-party/cocosid-coco3/cocosid.asm`, dated 2010-02-09 | `third-party/cocosid-coco2/cocosid.s` and `.lis`, dated 2010-02-13 |
| Binary | `COCOSID.BIN` on `third-party/cocosid-coco3/cocosid.dsk`, 22,833 bytes | `files/COCOSID.BIN`, 7,800 bytes |
| Matches its source? | Almost: see below | Exactly (see the main README's cross-check) |

This page records what the port to the CoCo 2 changed, and how the CoCo 3
binary differs from its own source.

## The CoCo 3 binary is a slightly later build than its source

The CoCo 3 source assembles with lwasm after two fixes: `sta #BORDERCOLOR`
and `stb #$FF20` need the `#` removed, as in COCOSID3. The result lines up
with the binary on the disk as follows.

- **Background picture:** all 14,072 bytes at `$1000` are identical.
- **Song, noise and wave tables:** identical. The only exception is the
  pattern table, whose 50 pointers all differ by the same `$170` because
  the code before it is longer in the binary.
- **Traced code:** the same, instruction for instruction (410 against
  411), apart from one extra `STB` in `init_sound`. It saves the DAC's
  previous value before the player takes it over.
- **Extra variables:** two more bytes before the voice records and 10
  more after them. The 10 are used by `init_sound`'s extra `STB` and by
  the input code below.
- **A 31-byte stub after the mixer, at `$4AA9`:** it calls a keyboard
  routine, then tests four bits of the result with branches that lead
  nowhere. Nothing calls the stub.
- **About 370 bytes of input code, at `$4CB2-$4E24`:**
  - a keyboard scan that strobes six columns through `$FF02` and packs the
    keys it finds into a bit mask
  - a routine that saves the PIA state, reads both axes of the right
    joystick by successive approximation through the DAC and comparator,
    and restores the PIA state
  - a small table

  Only the dead stub refers to any of it.

So the binary is the 2010-02-09 source plus the start of keyboard and
joystick control that was never wired up. The same disk has a 431-byte
program called `JOYTEST2.BIN`, which fits the author experimenting with
joystick input at the time. None of this made it into the CoCo 2 port.

## What the port to the CoCo 2 changed

The sequencer (`process_song`, the commands, instruments, envelopes and
pitch bend) is the same code in both. The song is the same apart from the
pitch-glide values. The changes are in the mixer, the display and the
start-up.

### The mixer

| | CoCo 3 | CoCo 2 |
|---|---|---|
| CPU | 1.79 MHz (`sta $FFD9`) | 0.895 MHz (the poke is commented out) |
| Sample loop | 92 cycles, 19,456 Hz (the "19 KHz" in both headers) | 77 cycles at half the clock, about 11.6 kHz |
| Samples per pass | 381: an outer count of 2 and an inner count of 133 - 8 | 227: a single count of 235 - 8 |
| Phase accumulators | `synth_freq` in each voice record | the operands of self-modified `LDD #` instructions |
| Each voice's sample | `synth_out` in the voice record | the operand of a self-modified `ADDB #` |
| Mixing | the sum indexes `mixtable` ("Volume * 0.25 + hard clip ramp"), then goes to `$FF20` | the sum goes straight to the DAC through `STB ,X` with X = `$FF20` |
| DP during the mix | `$48` | the mixer's own page, so the self-modifying stores are direct |

Both passes last about 20 ms, so a tick (one sequencer step and three
passes) and the tempo are unchanged.

Several changes follow from dropping `mixtable`. The wave tables are
stored signed, centred on 0, in both builds. The CoCo 3 relies on
`mixtable` to turn the signed sum into a DAC value. The CoCo 2 adds 42 to
every byte from `waveforms_start` to `waveforms_end` at start-up, so the
plain sum of three voices is already in DAC range.

Moving the phase and the sample into the code is what removes the voice
record's `synth_freq` (2 bytes) and `synth_out` (1 byte). The record
shrinks from 21 bytes to 18.

### Pitch

- **Note table:** recomputed. Every entry is 0.82 to 0.83 times its CoCo 3
  value, the same 76/92 as the glides below (note 69 is 1,224 against
  1,482). The CoCo 3 comment says its table is based on 76 Hz; the CoCo 2
  one says 80.36 Hz. The CoCo 2 mixer then doubles each frequency (`LSLB`, `ROLA`)
  before patching it in, which makes up for sampling at roughly half the
  rate.
- **Pitch bend:** the song's 15 `fdb $0800,...` glide rates are written
  as `cycle_ratio * n / frames` in the CoCo 2 source, with `cycle_ratio
  equ 76 / 92`. That scales them by about 0.83, so they come out
  smaller in the binary (-22 becomes -18, 13 becomes 11, and so on).
  All 15 differ, and apart from the relocated pattern table they are the
  only song bytes that do.
  The author's listing prints `cycle_ratio` as `0000`, yet the values are
  scaled correctly. So his assembler evaluates expressions in floating
  point and truncates only the final result. lwasm uses integers and would
  make every one of these glides 0.

### Display and machine set-up

The CoCo 2 source keeps all of the following, commented out:

- the GIME set-up: `INIT0`, video mode and resolution, border colour, and
  MMU paging of the screen at `$8000`
- the palette, the screen clear and `copy_title`, which unpacks the
  background picture loaded at `$1000`
- `reset_vu`, `vu_display` and `song_display`: the VU meters and the song
  progress bar drawn on that screen

The CoCo 2 binary therefore doesn't load the 14,072-byte picture, which is
most of the difference in size.

Other start-up differences:

| | CoCo 3 | CoCo 2 |
|---|---|---|
| Stack | `$FF00` | `$8000` |
| GIME interrupt registers | cleared | not touched |
| Auto-start | `ORG 356` writes `JMP start` over BASIC's RAM hooks at `$0164`, so it runs straight after `LOADM` | none; it needs `EXEC` |

### Syntax

The CoCo 2 source is also written for a different assembler, or at least
in a different style:

- **Voice record:** the `ssynth struct` becomes `ssynth_*` offsets with
  `equ`, and `synth1.freq` becomes `synth1+ssynth_freq`.
- **Local labels:** `!` and `<` become `1` and `1b`/`1f`.
- **Other changes:** `fzb` becomes `fdb 0`, `*` comments become `;`, and
  the text is in lower case.

The cross-check of the CoCo 2 listing found no effect of this on the
code.

## How this was checked

None of these steps needed new tools:

1. Extract `COCOSID.BIN` from `third-party/cocosid-coco3/cocosid.dsk` with
   `tools/decb_extract.py`.
2. Assemble the CoCo 3 source with lwasm after the two `#` fixes.
3. Trace both binaries with `tools/dis6809.py --dp 48`, and align the
   instruction sequences with their operands masked out.
4. Compare the picture, song and table bytes directly, allowing for the
   pattern table's relocation.

The source-to-source comparison is a diff of the two original files.
