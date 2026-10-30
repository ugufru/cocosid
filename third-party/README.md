# Third-party files

The original files by CoCoSID's author, Rémi Veilleux ("Remz"), kept as
downloaded and unmodified. See the History section of the main README for
who he is and how the versions relate.

**Copyright.** These files are not covered by anything else in this
repository. The author's site says "Copyright (c) 2010 Remi Veilleux"
(2012 on later pages), and none of the files carries a license. They are
here for reference and preservation.

All files were retrieved on 2026-10-30. The SHA-256 is of the zip as
downloaded. `.gitattributes` marks this folder `-text`, so git never
rewrites line endings: several files use CRLF.

## `cocosid-coco2/`: CoCoSID for the CoCo 2

From the Color Computer Archive,
[`Disks/Demos/CocoSiD (Remz) (Coco 2).zip`](https://colorcomputerarchive.com/repo/Disks/Demos/CocoSiD%20(Remz)%20(Coco%202).zip)
(SHA-256 `372a37a2fd699ef042bbab4a0697aa7a7a78dc7cefbdec88c9d7fe2cb61735a4`).

| File | Date | What it is |
|---|---|---|
| `cocosid.s` | 2010-02-13 | The author's source for `files/COCOSID.BIN` |
| `cocosid.lis` | 2010-02-13 | Assembler listing of that source |
| `cocosid.cas` | 2010-02-13 | The same program as a cassette image |

Left out, because they are byte-identical to files already in the repository:
`cocosid.dsk` (= `COCOSID2.DSK`) and `Source/cocosid.bin`
(= `files/COCOSID.BIN`).

## `cocosid-coco3/`: CoCoSID for the CoCo 3

From the Color Computer Archive,
[`Disks/Demos/CocoSiD (Remz) (Coco 3).zip`](https://colorcomputerarchive.com/repo/Disks/Demos/CocoSiD%20(Remz)%20(Coco%203).zip)
(SHA-256 `934be074e780fce389e2833471ec7cc0a656d67ff66307561af29cc907b4f638`).

| File | Date | What it is |
|---|---|---|
| `cocosid.dsk` | 2010-02-13 | The author's CoCo 3 demo disk: COCOSID, COCOSID2, SCALE, SPRITE, WOLF, JOYTEST2 |
| `cocosid.asm` | 2010-02-09 | Source of the CoCo 3 COCOSID (hand-converted *Commando*) |
| `cocosid_title_test2.bin` | 2010-02-08 | Background picture the source `includebin`s at `$1000` (by Louis-Philippe Guilbert, per the author's site) |

The two source files came from `CoCoSID_SourceCode.zip` inside the package,
which is not kept separately. The six files on the disk are the ones found
deleted on `COCOSID2.DSK` (see `files/deleted/`).

## `cocosid3/`: COCOSID3 source and conversion script

From the author's CoCoSID3 page, via the Wayback Machine:
[`cocosid3.zip`](https://web.archive.org/web/20201011235912/https://sites.google.com/site/rveilleux/coco3home/rems-cocosid3/cocosid3.zip?attredirects=0&d=1)
(SHA-256 `a8e266aa2a61cecc156371e7450c2e18faf4bd368d03ebcfe3428a29437fd220`).
The page itself, with his step-by-step conversion guide, is
[archived too](https://web.archive.org/web/20140814204357/https://sites.google.com/site/rveilleux/coco3home/rems-cocosid3).

| File | Date | What it is |
|---|---|---|
| `cocosid3.asm` | 2012-10-06 | COCOSID3 player source. Its header still names "CRAZY COMETS.SID"; the guide explains he switched to *R-Type* and kept the old names |
| `siddump_convert_v3.pl` | 2012-10-06 | Converts SIDDUMP output into CoCoSID pattern data. Adapted from a 2005 MIDIbox SID script (header: "Author: tk@midibox.org (2005-12-29)"), with the author's changes |
| `convert_all.bat` | 2010-02-21 | Runs the script once per voice |

Left out, because they are not the author's work:

- `siddump.exe` (32,768 bytes, 2007), the SIDDUMP tool by Covert Bitops.
  It is copyright Lasse Öörni, Stein Pedersen and Michael Troelsen, under
  a BSD-style license. Get it from its official repository instead,
  [github.com/cadaver/siddump](https://github.com/cadaver/siddump), which
  has the current source and the license in `readme.txt`. The copy in the
  author's package is an older build (version 1.04 or earlier, judging by
  its options), with no license text.
- `R-type.sid` (40,666 bytes), the C64 *R-Type* music by Chris Hülsbeck and
  Ramiro Vaca (1988, Activision).

## `rem-texture-demo/`: texture-mapping demo disk

From the author's files page, via the Wayback Machine:
[`REM_TEXTURE_DEMO.zip`](https://web.archive.org/web/20201011235904/https://sites.google.com/site/rveilleux/coco3home/rems-coco-3-files/REM_TEXTURE_DEMO.zip?attredirects=0&d=1)
(SHA-256 `9c33576a036fa18150b2fbdabdc27991d34a17016091570f56206d6dfff2782e`).

| File | Date | What it is |
|---|---|---|
| `REM_TEXTURE_DEMO.dsk` | 2012-01-08 | CoCo 3 disk with `COCOSID3.BIN` (the *R-Type* player, 10,336 bytes), `WOLF.BIN` and `TEXTURE.BIN` (64,592 bytes) |

`COCOSID3.BIN` is extracted to `files/cocosid3/`. The top-level `cocosid3/`
folder rebuilds it from his `cocosid3.asm` (the `cocosid3/` section above).

## Not found

- The automatically converted COCOSID2 that the author's site describes.
  The `COCOSID2.BIN` on his 2010 disk is a 3,668-byte CoCo 3 program, which
  does not fit "takes more memory than the previous version" (issue #9).
- His original 2010 `REMDISK.zip` and his YouTube demo page: no archived
  copies.
