# The `.sid` file format

`.sid` is the standard file format for Commodore 64 music. It is maintained
alongside the [High Voltage SID Collection](https://hvsc.c64.org) (HVSC),
the main archive of C64 music. The authoritative
specification is HVSC's
[SID FILE FORMAT DESCRIPTION (V1-V5)](https://www.hvsc.c64.org/download/C64Music/DOCUMENTS/SID_file_format.txt)
(last updated 2026-10-09). Its contributors are Michael Schwendt (PSID v1 and
v2), Simon White (PSID v2NG and RSID), Dag Lem (PSID v2NG), LaLa
(documentation before v3) and Wilfred Bos (v3, v4 and v5).

This page summarises the parts that matter for CoCoSID. For anything beyond
that, follow the specification, not this page.

## What a `.sid` file is

A `.sid` file is **not a recording**. It holds the C64 machine code that
played the music in the original game, the music driver plus its data,
behind a small header. The header tells a player:

- **Where to load the code.**
- **Which routine starts a song:** the *init* routine.
- **Which routine to call every frame:** the *play* routine.

Playing a `.sid` file therefore means emulating a 6510 CPU and a SID chip:

1. **Load** the C64 data at its load address.
2. **Start a song:** put the song number minus one in the accumulator and
   call the init routine.
3. **Call the play routine** once per frame, usually 50 times a second on
   PAL. Each call updates the SID's registers: frequency, waveform,
   envelope and pulse width for each of the three voices.

A file can contain several songs. Games often packed their title music,
in-game music and sound effects into one driver.

## PSID and RSID

The first four bytes are the magic ID:

| Magic | Meaning |
|---|---|
| `PSID` | The common case. The tune can be driven from outside by calling init once and play every frame, as above. |
| `RSID` | "Real SID": the tune needs a genuine C64 environment. It installs its own interrupt handlers, plays samples, runs at several speeds or busy-loops. Its load and play addresses and its speed field must be 0, and players without RSID support should reject it. |

## Header

All multi-byte values are **big-endian**, unlike the 6510's own byte order.
Text fields are Windows-1252. Version 1 headers are `$76` bytes long;
versions 2 to 5 add fields and are `$7C` bytes long.

| Offset | Size | Field | Notes |
|---|---|---|---|
| `+00` | 4 | magicID | `PSID` or `RSID` |
| `+04` | 2 | version | 1 to 5; RSID and PSID v2NG use 2 or later |
| `+06` | 2 | dataOffset | where the C64 data starts: `$0076` (v1) or `$007C` (v2+) |
| `+08` | 2 | loadAddress | 0 means the first two data bytes give the load address, little-endian, C64 style |
| `+0A` | 2 | initAddress | called with A = song number - 1; 0 means the load address |
| `+0C` | 2 | playAddress | called every frame; 0 means the tune installs its own interrupt handler |
| `+0E` | 2 | songs | 1 to 256 |
| `+10` | 2 | startSong | song to play first, from 1 |
| `+12` | 4 | speed | one bit per song: 0 = vertical blank timing (50 Hz PAL, 60 Hz NTSC), 1 = CIA timer (60 Hz by default) |
| `+16` | 32 | name | null-terminated if shorter than 32 bytes |
| `+36` | 32 | author | |
| `+56` | 32 | released | year and publisher; once called "copyright" |
| `+76` | 2 | flags | v2+ (see below) |
| `+78` | 1 | startPage | v2+: start of the largest free memory range, for relocating a player |
| `+79` | 1 | pageLength | v2+: length of that range in pages |
| `+7A` | 1 | secondSIDAddress / multiSidConfig | v3-v4: address of a second SID; v5: multi-SID setup |
| `+7B` | 1 | thirdSIDAddress / sidAddressConfigStart | v4: address of a third SID; v5: multi-SID setup |
| `+7C` | | data | C64 data for v2+ (`+76` for v1) |

Version 5 also allows the name, author and released strings to share their
96 bytes more flexibly. Readers try that layout first and fall back to the
fixed 32-byte fields.

The **flags** word (v2+):

| Bits | Meaning |
|---|---|
| 0 | 1 = Compute!'s Sidplayer MUS data, which needs an external player |
| 1 | PSID: 1 = needs PlaySID-specific features. RSID: 1 = the tune is a C64 BASIC program |
| 2-3 | Video standard: 01 PAL, 10 NTSC, 11 both, 00 unknown |
| 4-5 | SID model: 01 MOS6581, 10 MOS8580, 11 both, 00 unknown |
| 6-9 | Models or configuration of extra SIDs (v3 to v5) |
| 10 | Embedded song lengths |
| 11 | FM OPL |
| 12-15 | Reserved |

The specification also defines the C64 environment a player must set up
before calling init (memory banking, timers, and the PAL/NTSC flag at
`$02A6`), which differs between PSID and RSID.

## Worked example: `R-type.sid`

This is the tune in the author's COCOSID3 package. The file itself is not
in this repository (see `third-party/README.md`); these are its header
values.

| Field | Value | Meaning |
|---|---|---|
| magicID, version | `PSID`, 2 | ordinary PSID, v2 header (`$7C` bytes) |
| loadAddress | `$0000` | load address is in the data: `$3194` |
| initAddress | `$3194` | |
| playAddress | `$6370` | called every frame |
| songs, startSong | 14, 1 | |
| speed | `$00000000` | every song uses vertical blank timing: 50 Hz on PAL |
| name | `R-type` | |
| author | `Chris Hülsbeck & Ramiro Vaca` | |
| released | `1988 Activision` | |
| flags | `$0014` | PAL, MOS6581 |
| startPage, pageLength | `$04`, `$1B` | free pages `$0400-$1EFF` |

The 40,540 data bytes load at `$3194-$CFEF`.

## From `.sid` to CoCoSID

CoCoSID cannot run a `.sid` file: a 6809 cannot execute 6510 code, and the
CoCo has no SID chip. The music has to be translated into CoCoSID's own
pattern format.

- **COCOSID** (this repository's program, playing *Commando*) was
  converted **by hand**, note by note (see the main README's History
  section).
- **COCOSID2 and COCOSID3** used the author's conversion toolchain, kept in
  `third-party/cocosid3/` and described on
  [his archived CoCoSID3 page](https://web.archive.org/web/20140814204357/https://sites.google.com/site/rveilleux/coco3home/rems-cocosid3).
  The steps:

1. **Dump.** [SIDDUMP](https://github.com/cadaver/siddump) by Covert
   Bitops (BSD-style license) emulates the C64, calls the tune's
   init routine, then calls play once per frame. For every frame it prints
   a table row giving each voice's frequency, note, waveform register, ADSR
   envelope and pulse width. The author's guide runs
   `SIDDUMP r-type.sid -t180 -f3 > dump.txt` for 180 seconds starting at
   frame 3. The dump is then trimmed by hand to a whole number of patterns.
2. **Convert.** `siddump_convert_v3.pl` reads that table one voice at a
   time:
   - From each frame it takes the frequency, note, waveform register and
     ADSR. It does not read the pulse width.
   - From the waveform register it keeps the waveform bits, the sync and
     ring-modulation bits and the gate bit.
   - It splits the dump into patterns of a set length, 96 frames for
     R-Type at 50 frames a second.
   - It writes one `.cid` file per voice.

   The script is adapted from a 2005 MIDIbox SID converter.
3. **Assemble.** `cocosid3.asm` `include`s the three `.cid` files
   (`crazycomets_t1.cid` to `_t3.cid`, names left over from an earlier
   attempt at *Crazy Comets*).

The author warns that not every `.sid` converts well: CoCoSID does not
emulate everything the SID can do, and SIDDUMP does not capture
everything either.
