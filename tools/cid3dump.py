#!/usr/bin/env python3
"""Recover COCOSID3's song files (crazycomets_t1-3.cid) from COCOSID3.BIN.

The author's package has the player source (cocosid3.asm) but not the three
.cid files it includes, which siddump_convert_v3.pl generated. This decodes
the song data in the binary back into that format, with the same labels
(pattern_tN_MM, song_voiceN), so the author's source can be assembled.

usage: cid3dump.py COCOSID3.BIN OUTDIR
"""
import os
import sys

SONG_START = 0x1377     # just after waveform_lookup (24 words at $1347)
SONG_PTRS = 0x11C2      # operand of init_sound's ldd #song_voice1 (then +6, +12)
PATTERN_LEN = 96        # frames per pattern, as in cocosid3.asm


def load(path):
    b = open(path, "rb").read()
    mem, p = {}, 0
    while b[p] == 0:
        n = (b[p + 1] << 8) | b[p + 2]
        a = (b[p + 3] << 8) | b[p + 4]
        for i in range(n):
            mem[a + i] = b[p + 5 + i]
        p += 5 + n
    return mem


def word(mem, a):
    return (mem[a] << 8) | mem[a + 1]


def describe(w):
    """An uncompressed frame: 5-bit wave, 11-bit frequency stored >> 2."""
    return f"wave={w >> 11} freq={(w & 0x7FF) << 2}"


def pattern_lines(mem, a, label):
    """Decode one pattern at a; return (lines, end address)."""
    out = [label, "; start of compressed data information header"]
    count = mem[a]
    out.append(f"\tfcb\t{count}\t; batch groups in header")
    a += 1
    lookup = {}                     # (len, no) -> batch words
    for _ in range(count):
        h = mem[a]
        blen, nb = (h & 7) + 1, (h >> 3) & 15
        out.append(f"\tfcb\t{h}\t; {nb} batch(es) of length {blen}")
        a += 1
        for k in range(nb):
            ws = [word(mem, a + 2 * i) for i in range(blen)]
            lookup[(blen, k)] = ws
            out.append("\tfdb\t" + ",".join(f"${w:04X}" for w in ws)
                       + f"\t; batch {k}")
            a += 2 * blen
    out.append("; start of data stream")
    frames = 0
    while frames < PATTERN_LEN:
        b = mem[a]
        wave = b >> 3
        if wave >= 24:
            blen, no = wave - 23, b & 7
            if (blen, no) not in lookup:
                sys.exit(f"${a:04X}: compressed byte for missing batch")
            out.append(f"\tfcb\t{b}\t; compressed, batch_len={blen}, batch no={no}")
            frames += blen
            a += 1
        else:
            w = word(mem, a)
            out.append(f"\tfdb\t${w:04X}\t; {describe(w)}")
            frames += 1
            a += 2
    if frames != PATTERN_LEN:
        sys.exit(f"{label}: {frames} frames, expected {PATTERN_LEN}")
    out.append("")
    return out, a


def main(binpath, outdir):
    mem = load(binpath)
    lists = [word(mem, SONG_PTRS + 6 * i) for i in range(3)]
    os.makedirs(outdir, exist_ok=True)
    a = SONG_START
    for track, lst in enumerate(lists, 1):
        # The song list: pattern pointers, then $FFFF (restart) and 0000.
        seq, p = [], lst
        while word(mem, p) not in (0x0000, 0xFFFF):
            seq.append(word(mem, p))
            p += 2
        tail = []
        while word(mem, p) in (0x0000, 0xFFFF):
            tail.append(word(mem, p))
            p += 2
            if tail[-1] == 0:
                break
        # The script names a pattern after the position where it first plays.
        names = {}
        for i, ptr in enumerate(seq):
            names.setdefault(ptr, f"pattern_t{track}_{i:02d}")
        lines = [f"; Track {track}, recovered from {os.path.basename(binpath)} "
                 f"by tools/cid3dump.py", ""]
        while a < lst:
            if a not in names:
                sys.exit(f"track {track}: no song entry plays ${a:04X}")
            pl, a = pattern_lines(mem, a, names[a])
            lines += pl
        if a != lst:
            sys.exit(f"track {track}: patterns overrun the song list")
        lines.append(f"; pattern list for this track {track}, "
                     f"total length of song is {len(seq)} pattern:")
        lines.append(f"song_voice{track}")
        lines += [f"\tfdb\t{names[ptr]}" for ptr in seq]
        lines += ["\tfdb\t$ffff" if t else "\tfdb\t00" for t in tail]
        a = p
        path = os.path.join(outdir, f"crazycomets_t{track}.cid")
        open(path, "w").write("\n".join(lines) + "\n")
        print(f"{path}: {len(names)} patterns, {len(seq)} in the song, "
              f"${lst:04X} song list")
    print(f"song data ends at ${a - 1:04X}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
