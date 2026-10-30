# CoCoSID

Reverse engineering of **CoCoSID**, a software emulation of the Commodore SID
sound chip for the TRS-80 Color Computer. The program plays three voices of
wavetable sound through the CoCo's 6-bit DAC.

## Contents

| Path | What it is |
|---|---|
| `COCOSID2.DSK` | Original disk image: 35 tracks, single sided, Disk BASIC (RS-DOS) |
| `files/COCOSID.BIN` | The only live file on the disk: a LOADM binary, exec `$4800` |
| `files/deleted/` | Six files recovered from deleted directory entries and free granules |
| `cocosid.asm` | Commented disassembly of `COCOSID.BIN`, in lwasm syntax (generated) |
| `cocosid.ann` | Labels, symbols and comments merged into `cocosid.asm` |
| `tools/decb_extract.py` | Extracts the live files from a Disk BASIC `.DSK` image |
| `tools/dis6809.py` | Code-tracing 6809 disassembler for LOADM binaries |

## Recovered deleted files

Disk BASIC deletes a file by zeroing the first byte of its name and freeing
its granules, so the data survives until something overwrites it. All six of
these parse as complete LOADM files, fill granules 35 to 62 with no gaps or
overlaps, and (where a directory entry survives) match its last-sector byte
count.

| File | Bytes | Exec | Note |
|---|---|---|---|
| `COCOSID-OLD.BIN` | 22,833 | `$4800` | Earlier build of COCOSID |
| `COCOSID2.BIN` | 3,668 | `$1000` | |
| `SPRITE.BIN` | 15,501 | `$4000` | Name was `?PRITE` |
| `GOLF.BIN` | 4,999 | `$4000` | Name was `?OLF` |
| `JOYTEST2.BIN` | 431 | `$4000` | Name was `?OYTEST2` |
| `UNNAMED-G35.BIN` | 9,322 | `$5000` | No directory entry left; starts at granule 35 |

The first letters of the names are guesses. The recovery was done by hand
(reading contiguous granules from each start point), not by
`decb_extract.py`.

## Disassembly

`cocosid.asm` reassembles byte for byte to the original:

```sh
lwasm --format=decb -o COCOSID.BIN cocosid.asm
cmp COCOSID.BIN files/COCOSID.BIN
```

The labels, symbols and comments live in `cocosid.ann`, not in the listing,
so edit that file and regenerate:

```sh
python3 tools/dis6809.py -a cocosid.ann files/COCOSID.BIN > cocosid.asm
```

The directive format is documented in the `Annotations` class in
`tools/dis6809.py`. Besides labels and comments, the file carries options
the trace needs:

- `dp 48`: the program sets DP to `$48` at startup, so direct-page
  operands refer to its variables at `$48xx`.
- `dp-at 494C-4983 49`: the sample loop switches DP to `$49` so it can
  patch its own instructions cheaply.
- `entry 49F7 ... 4A07`: entries of the sequencer's command jump table,
  which is reached through an indirect `JMP [$4806]`.

### Memory map

| Address | Contents |
|---|---|
| `$4800-$4814` | `JMP` to start, then variables (direct page `$48`) |
| `$4815-$484A` | Three 18-byte voice records (not loaded; RAM) |
| `$484B-$4BAC` | All of the code |
| `$4BAD-$532C` | Not loaded; RAM |
| `$532D` | Frequency table, indexed by note |
| `$542D`, `$5478`, `$54C1` | Initial song data for voices 1 to 3 |
| `$553B` | Pattern pointer table |
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
  patched operand bytes are labelled with `EQU`s (`D4955`, `D4977`, ...).

## Requirements

- Python 3 (no third-party packages)
- [lwtools](http://www.lwtools.ca/) for `lwasm`
