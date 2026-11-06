# REMDISK: the February 2010 CoCoSID builds

`third-party/remdisk/REMDISK.dsk` is the author's CoCo 3 demo disk, dated
2010-02-21. It holds the automatically converted COCOSID2 that this project
had been missing, and an early build of COCOSID3. Both programs are extracted
to `files/remdisk/`.

| Program | Song | Patterns per voice | Frames | Length at 50 Hz | Song data |
|---|---|---|---|---|---|
| `COCOSID2.BIN` (29,056 bytes) | *Battle Valley*, Jeroen Tel (1988, Rack-It) | 82 of 256 frames | 20,992 | 6:59.8 | 27,337 bytes |
| `COCOSID3.BIN` (11,577 bytes) | *R-Type*, Chris Hülsbeck and Ramiro Vaca | 93 of 96 frames | 8,928 | 2:58.6 | 9,852 bytes |

The lengths come from the frame counts. Nobody has timed these builds.

## Running them

```sh
xroar -machine coco3 -rompath ~/.xroar/roms -cart rsdos -run files/remdisk/COCOSID2.BIN
xroar -machine coco3 -rompath ~/.xroar/roms -cart rsdos -run files/remdisk/COCOSID3.BIN
```

## Identifying the songs

The author's YouTube page has a video titled `CoCoSID2 playing "Battle
Valley.SID"`, uploaded 2010-02-16. The song data agrees with that title.
`tools/sid_match.py` decodes a binary's frames and compares each frequency
with a [SIDDUMP](https://github.com/cadaver/siddump) dump of the `.sid`:

```sh
siddump Battle_Valley.sid -t430 > bv.txt
python3 tools/sid_match.py cocosid2-2010 files/remdisk/COCOSID2.BIN bv.txt
siddump R-Type.sid -t180 -f3 > rt.txt
python3 tools/sid_match.py cocosid3-2010 files/remdisk/COCOSID3.BIN rt.txt
python3 tools/sid_match.py cocosid3-2012 files/cocosid3/COCOSID3.BIN rt.txt
```

Both `.sid` files are from the High Voltage SID Collection, in
`MUSICIANS/T/Tel_Jeroen/` and `MUSICIANS/H/Huelsbeck_Chris/`. They are not in
this repository.

| Binary | Dump | Voice 1 | Voice 2 | Voice 3 | Offset | Ratio |
|---|---|---|---|---|---|---|
| REMDISK `COCOSID2.BIN` | *Battle Valley* | 97.0% | 90.2% | 89.2% | 0 | 6.118 to 6.119 |
| REMDISK `COCOSID3.BIN` | *R-Type* | 75.1% | 87.1% | 88.1% | -2 | 6.118 to 6.139 |
| 2012 `COCOSID3.BIN` | *R-Type* | 75.1% | 87.1% | 88.1% | 0 | 6.118 to 6.139 |

The ratios are close to the constant in the author's source, 6.1174. As a
negative check, the REMDISK `COCOSID2.BIN` scores under 6% on every voice
against *R-Type* and against the first subtune of Rob Hubbard's *Crazy Comets*.

## COCOSID3 already existed in 2010

The REMDISK build differs from the 2012 build only in its song data and the
addresses that follow from that:

- **Same player:** with the REMDISK song recovered by `tools/cid3dump.py`,
  the `cocosid3/cocosid3.asm` generated from the source dated 2012-10-06
  assembles to exactly what REMDISK's `COCOSID3.BIN` loads (11,552 bytes,
  exec `$1000`, checked with `tools/decb_cmp.py`).
- **Same music:** every frame compared is identical once the two-frame shift
  is allowed for, on all three voices (8,926 frames each).
- **Different start frame:** the 2012 song matches SIDDUMP's `-f3`, as the
  author's guide says. The REMDISK song starts two frames earlier, so it was
  presumably dumped with `-f1`.
- **Smaller in 2012:** the later alignment takes the song from 83 unique
  patterns and 9,852 bytes to 70 patterns and 8,611 bytes. Better pattern
  repeats were probably the reason for the change, but that is an inference.

So 2012 is the date of the source package, and the player itself is at least
as old as this disk. That rests on the zip's 2010-02-21 timestamp, since Disk
BASIC directories hold no dates. Two things are consistent with it:
`convert_all.bat` carries the same date, and the author's files page says "as
of today February 21th, 2010".

## From COCOSID2 to COCOSID3

The site calls COCOSID3 "almost the same as COCOSID2 with only some minor
tweaks". Comparing the disassembled instructions of the two REMDISK builds,
with addresses set aside, shows two changes:

| | COCOSID2 | COCOSID3 |
|---|---|---|
| Pattern length | 256 frames: the counter is incremented until it wraps | 96 frames: `lda #$60`, then decremented |
| Frequency in a frame word | Stored divided by 2 | Stored divided by 4, which doubles the top frequency |

Mixer, batch compression, wave tables and start-up code are otherwise the
same instructions. The much smaller COCOSID3 song comes from its data: a
shorter tune, and more repeated patterns at the shorter length.

COCOSID2's voice 2 and 3 song lists have no terminator. Voice 1 is processed
first and its `$FFFF` restarts the song, so the player never reads past them.

## What has been checked

Running each program headless in XRoar with `-trap pc=0x1080` and a RAM
snapshot at the 1,000th song step puts voice 1 at exactly frame 1,000: list
entry 4 with counter 232 for COCOSID2 (3 x 256 + 232), and list entry 11 with
counter 56 for COCOSID3 (10 x 96 + 96 - 56). Both programs have also been run
in XRoar and confirmed working by ear.

## Sources

- Rémi Veilleux, [YouTube demos](https://sites.google.com/view/rveilleux/coco3home/coco3youtube)
  and [files page](https://sites.google.com/view/rveilleux/coco3home/rems-coco-3-files)
- [`CoCoSID2 playing "Battle Valley.SID"`](https://www.youtube.com/watch?v=s87EswP4xeE)
- [GameBase64, Battle Valley](https://gb64.com/game.php?h=0&id=680) for the
  composer credit, which the `.sid` header also gives
