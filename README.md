# CoCoSID

Reverse engineering of **CoCoSID**, a software emulation of the Commodore SID
sound chip for the TRS-80 Color Computer. The program plays three voices of
wavetable sound through the CoCo's 6-bit DAC.

## History

CoCoSID was written by **Rémi Veilleux** in 2010. "Remi Veilleux, 2010" heads
the original source, and the Color Computer Archive files it under his
handle, **Remz**. He published it on his site, "Rem's CoCo 3", alongside
other CoCo 3 demos (SCALE, SPRITE, WOLF). All of them were written for a
stock 128K CoCo 3, and the demo disk was posted in February 2010.

His site describes three versions:

- **COCOSID** plays Rob Hubbard's music for the Commodore 64 game
  *Commando*, converted by hand: "I have to hand-convert every notes of
  this song, which uses 3 tracks simultaneously." The CoCo 3 version shows
  a background picture by Louis-Philippe Guilbert.
- **COCOSID2** has its music "mostly automatically converted by taking the
  .SID and running it through some tool and script". That let it imitate
  more SID features: vibrato, portamento, attack, sustain, decay and
  release.
- **COCOSID3** is COCOSID2 with minor tweaks, playing part of *R-Type*. He
  released it as a source package with the conversion toolchain. SIDDUMP
  (by Covert Bitops) dumps the C64 player's SID register writes to text, a
  Perl script turns the dump into CoCoSID pattern data, and his page walks
  through the steps.

COCOSID3, the latest, is rebuilt here from his source in `cocosid3/` (see
[COCOSID3](#cocosid3) below).

### Where this disk fits

- `COCOSID2.DSK` is byte-identical to `cocosid.dsk` in the Color Computer
  Archive's "CocoSiD (Remz) (Coco 2)" package. Despite the disk's name, its
  program is the first version, the hand-converted *Commando*, built for the
  CoCo 2.
- That package also holds the original source (`cocosid.s`) and an assembler
  listing, dated 13 February 2010. Its `cocosid.bin` is identical to
  `files/COCOSID.BIN`.
- The CoCo 2 source keeps the CoCo 3 code commented out: GIME setup,
  title picture and VU meter. It also scales its pitch bends by a
  `cycle_ratio` of 76/92.
- The header still claims "19 KHz realtime mixing". On the CoCo 2 the mixing
  loop takes 77 cycles at 0.895 MHz, about 11.6 kHz, so that figure
  presumably describes the CoCo 3 build.
- The disk was made from a copy of the author's CoCo 3 demo disk. Its six
  deleted files are byte-identical to the six files on the archive's
  "CocoSiD (Remz) (Coco 3)" disk, in the same granules (see below).
- The original source confirms details reconstructed here independently:
  - the song is 123 patterns of 96 C64 frames ("Total Commando song:
    3:56.12")
  - it plays at 125 BPM, which is 16.7 notes per second
  - the routine at `$4A81` is `rect_modulator`, the pulse-width modulation
  - see "Cross-check with the original source" below for the full comparison

The author's site carries "Copyright (c) 2010 Remi Veilleux", and the source
has no license statement. His original files are kept unmodified in
`third-party/` with their provenance: this program's source and listing,
the CoCo 3 source and demo disk, the COCOSID3 source and conversion
script, and his 2012 texture-mapping demo disk.

Sources:

- Color Computer Archive, [Disks/Demos](https://colorcomputerarchive.com/repo/Disks/Demos/):
  "CocoSiD (Remz) (Coco 2).zip" and "CocoSiD (Remz) (Coco 3).zip"
- Rémi Veilleux, "Rem's CoCo 3" (archived):
  [home page](https://web.archive.org/web/20120204000700/http://sites.google.com/site/rveilleux/coco3home),
  [demo files and descriptions](https://web.archive.org/web/20160823232904/https://sites.google.com/site/rveilleux/coco3home/rems-coco-3-files),
  [CoCoSID3 source and conversion guide](https://web.archive.org/web/20140814204357/https://sites.google.com/site/rveilleux/coco3home/rems-cocosid3)
- CoCo Central, [CoCoSID CoCo 3 playing Commando](https://cococentral.com/cocosid-coco-3-playing-commando/)

## Contents

| Path | What it is |
|---|---|
| `COCOSID2.DSK` | Original disk image: 35 tracks, single sided, Disk BASIC (RS-DOS) |
| `files/COCOSID.BIN` | The only live file on the disk: a LOADM binary, exec `$4800` |
| `files/deleted/` | Six files recovered from deleted space: the author's CoCo 3 demos |
| `cocosid.asm` | Commented disassembly of `COCOSID.BIN`, in lwasm syntax (generated) |
| `cocosid.ann` | Labels, symbols and comments merged into `cocosid.asm` |
| `song/song.asm` | The tune: song lists and patterns as readable lwasm source (generated) |
| `song/README.md` | Song data format and a description of this tune |
| `tools/decb_extract.py` | Extracts the live files from a Disk BASIC `.DSK` image |
| `tools/dis6809.py` | Code-tracing 6809 disassembler for LOADM binaries |
| `tools/songdump.py` | Decodes the song data into `song/song.asm` |
| `files/cocosid3/COCOSID3.BIN` | COCOSID3 (*R-Type*, CoCo 3), extracted from the author's 2012 texture demo disk |
| `cocosid3/` | COCOSID3 rebuilt from the author's source, with its song recovered from the binary; see its README |
| `tools/cid3dump.py` | Recovers COCOSID3's song files from the binary |
| `tools/cocosid3_lwasm.py` | Makes the author's COCOSID3 source build with lwasm |
| `tools/decb_cmp.py` | Compares what two LOADM binaries load into memory |
| `docs/sid-format.md` | The C64 `.sid` (PSID/RSID) format and how the author converted `.sid` tunes for CoCoSID |
| `third-party/` | The author's original files (sources, disks), unmodified; see its README |
| `LICENSE` | MIT, for this project's own work only (see License below) |
| `issues.jsonl` | Issue tracker, one JSON object per line |
| `issues.html` | Browsable view of the tracker (generated by `tools/issues_html.py`) |

After editing `issues.jsonl`, rebuild the view:

```sh
python3 tools/issues_html.py render issues.jsonl issues.html --title="CoCoSID issues"
```

## Running it

In [XRoar](https://www.6809.org.uk/xroar/), as a US CoCo 2 with Disk BASIC:

```sh
xroar -machine coco2bus -rompath ~/.xroar/roms -cart rsdos -run files/COCOSID.BIN
```

Point `-rompath` at the directory holding your CoCo ROMs (`bas13.rom`,
`extbas11.rom`, `disk11.rom`). If XRoar can't find them, the log shows
`Slot 0: (unpopulated)`, the screen fills with garbage and there is no
sound. When it works the text screen freezes and the tune plays,
looping after about four minutes. The keyboard is ignored; close the
window or reset to stop it.

## Recovered deleted files

Disk BASIC deletes a file by zeroing the first byte of its name and freeing
its granules, so the data survives until something overwrites it. These six
were recovered by hand, reading contiguous granules from each start point,
not by `decb_extract.py`. They fill granules 35 to 62 with no gaps or
overlaps.

Each one is byte-identical to a file on the author's CoCo 3 disk (Color
Computer Archive, "CocoSiD (Remz) (Coco 3)"), which settles their names. The
descriptions are the author's, from his site.

| File | Bytes | Exec | Name on the CoCo 3 disk | What it is |
|---|---|---|---|---|
| `COCOSID-COCO3.BIN` | 22,833 | `$4800` | `COCOSID.BIN` | CoCoSID for the CoCo 3, with the background picture |
| `COCOSID2.BIN` | 3,668 | `$1000` | `COCOSID2.BIN` | The file the author's disk calls COCOSID2 |
| `SPRITE.BIN` | 15,501 | `$4000` | `SPRITE.BIN` | Scrolling and sprites demo in the style of *Super Mario World* |
| `WOLF.BIN` | 4,999 | `$4000` | `WOLF.BIN` | Real-time 3D maze in the style of *Wolfenstein* |
| `JOYTEST2.BIN` | 431 | `$4000` | `JOYTEST2.BIN` | Not described on the site |
| `SCALE.BIN` | 9,322 | `$5000` | `SCALE.BIN` | Full-screen real-time sprite scaling, joystick controlled |

`SCALE.BIN` had no directory entry left: the live `COCOSID.BIN` reused its
slot.

## Disassembly

`cocosid.asm` reassembles byte for byte to the original:

```sh
lwasm --format=decb -o COCOSID.BIN cocosid.asm
cmp COCOSID.BIN files/COCOSID.BIN
```

The labels, symbols and comments live in `cocosid.ann`, not in the listing,
so edit that file and regenerate:

```sh
python3 tools/songdump.py files/COCOSID.BIN > song/song.asm
python3 tools/dis6809.py -a cocosid.ann files/COCOSID.BIN > cocosid.asm
```

`cocosid.asm` INCLUDEs `song/song.asm`, so assemble from the repository root.

The directive format is documented in the `Annotations` class in
`tools/dis6809.py`. Besides labels and comments, the file carries options
the trace needs:

- `dp 48`: the program sets DP to `$48` at startup, so direct-page
  operands refer to its variables at `$48xx`.
- `dp-at 494C-4983 49`: the sample loop switches DP to `$49` so it can
  patch its own instructions cheaply.
- `entry 49F7 ... 4A07`: entries of the sequencer's command jump table,
  which is reached through an indirect `JMP [$4806]`.

### Cross-check with the original source

The disassembly was made from the binary alone, then checked against the
author's listing (`third-party/cocosid-coco2/cocosid.lis`):

- **Bytes:** all 7,775 bytes in the listing match `files/COCOSID.BIN`.
- **Code and data:** the listing's instruction boundaries match the trace
  exactly. The one difference was three unreachable `RTS` bytes at
  `$484C-$484E`, now disassembled as code to match.
- **Labels:** every routine label here sits on one of his. `cocosid.ann`
  keeps our names and notes his beside them: "Author's name: synth_mixer"
  in routine headers, and his names in square brackets on variables and
  voice-record fields.
- **Behaviour:** his comments agree with our reading of the mixer (77
  cycles per sample by his counts), the envelope and release logic, the
  commands, the PWM sweep and the wave tables.
- **One correction:** the pattern table starts at `$553D` with pattern 1,
  and the code indexes it from `PATTERNS-2`. We had put the table two bytes
  earlier and described `SONG3` as running into it. In fact `SONG3` ends
  with its own `$00`.

Some of his comments are stale and disagree with his own code. For
example, "loop for 205 iteration" sits above a count of 227, and "16
entries" sits above a loop of 15 frames. Where they disagree, this
project follows the code.

### Memory map

| Address | Contents |
|---|---|
| `$4800-$4814` | `JMP` to start, then variables (direct page `$48`) |
| `$4815-$484A` | Three 18-byte voice records (not loaded; RAM) |
| `$484B-$4BAC` | All of the code |
| `$4BAD-$532C` | Not loaded; RAM |
| `$532D` | Frequency table, indexed by note |
| `$542D-$6394` | Song data (`song/song.asm`): song lists at `$542D`, `$5478`, `$54C1`; pattern table at `$553D`; 50 patterns |
| `$6395-$6B94` | Eight noise wave tables |
| `$6C95-$6E94` | Waveform source data |
| `$6395-$7B95` | Waveform tables built in RAM at startup |

### How it works

- **Startup (`$484F`)**: sets DP to `$48`, masks interrupts, puts the stack
  at `$8000`, turns off the disk drive, builds the waveform tables
  (`$4ABC`), and sets up the sound output (`$4879`).
- **Main loop (`$48D7`)**: runs the sequencer once, then the mixer three
  times.
- **Sequencer (`$49B3`)**: steps through each voice's command stream.
  Commands 0 to 8 dispatch through a table of `BRA` instructions at `$49F7`.
- **Mixer (`$48EA`)**: loads each voice's frequency and wave table, then runs
  227 iterations of the sample loop at `$4954`.
- **Sample loop (`$4954`)**: self-modifying. Each voice is an
  `LDD #phase / ADDD #freq / STD` sequence whose `#phase` operand is
  rewritten every pass. Each voice's sample is written into the operand of a
  later `ADDB #`, and the sum goes straight to the DAC at `$FF20`. The
  patched operand bytes are labelled with `EQU`s (`V1_PHASE`, `V1_SAMPLE`, ...).

## COCOSID3

COCOSID3 (2012) is the author's last CoCoSID. It plays *R-Type* on a
CoCo 3 and was converted automatically from a `.sid` dump. Its binary is
on his 2012 texture demo disk and his source is in `third-party/cocosid3/`,
but the package lacks the three song files the source includes.

`cocosid3/` recovers those from the binary. With them, his source (with six
small edits for lwasm) assembles to exactly the bytes `COCOSID3.BIN`
loads, so it is not disassembled separately. Its README has the build,
the memory map and what changed since the 2010 player. In short, the
2010 player is a sequencer with notes and instruments. COCOSID3 plays a
compressed frame-by-frame dump of the SID registers, at twice the sample
rate and one song step per 50 Hz frame.

## Requirements

- Python 3 (no third-party packages)
- [lwtools](http://www.lwtools.ca/) for `lwasm`
- [XRoar](https://www.6809.org.uk/xroar/) and CoCo ROM images to run it

## License

This project's own work is under the MIT license (see `LICENSE`): the
tools, `cocosid.ann`, the documentation and the issue tracker files.

The license does not cover the CoCoSID program or anything derived from it.
That means `COCOSID2.DSK`, everything in `files/`, the generated listings
`cocosid.asm` and `song/song.asm`, the generated `cocosid3/cocosid3.asm` and
`cocosid3/song/`, and `third-party/`. These remain the copyright of Rémi
Veilleux. The music is Rob Hubbard's *Commando* and, in COCOSID3, Chris
Hülsbeck and Ramiro Vaca's *R-Type*. They
are included for study and preservation. `LICENSE` lists the exact scope.
