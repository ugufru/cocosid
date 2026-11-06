#!/usr/bin/env python3
"""Check a CoCoSID binary's song data against a SIDDUMP dump of a .sid.

Decodes the frames of each voice, then compares each frame's frequency with
the C64 frequency in the dump, trying small frame offsets. A real match gives
most frames in agreement at a ratio near 6.117, the C64-to-CoCo frequency
constant in the author's cocosid3.asm. Frames where the voice is silent, or
where either frequency is 0, are skipped. Noise frames lower the score.

usage: sid_match.py PRESET COCOSID.BIN DUMP.TXT
presets: cocosid2-2010, cocosid3-2010, cocosid3-2012
"""
import statistics
import sys

# Song list addresses, list length, frames per pattern, frequency shift.
PRESETS = {
    "cocosid2-2010": ((0x2A2C, 0x4CA7, 0x7D96), 82, 256, 1),
    "cocosid3-2010": ((0x1F7A, 0x2C78, 0x3935), 93, 96, 2),
    "cocosid3-2012": ((0x1C9D, 0x286F, 0x345C), 93, 96, 2),
}
MAX_OFFSET = 30
TOLERANCE = 0.02


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


def pattern(mem, a, length):
    """Expand one pattern's batch references into a list of frame words."""
    count = mem[a]
    a += 1
    batches = {}
    for _ in range(count):
        h = mem[a]
        a += 1
        blen, nb = (h & 7) + 1, (h >> 3) & 15
        for k in range(nb):
            batches[(blen, k)] = [word(mem, a + 2 * i) for i in range(blen)]
            a += 2 * blen
    frames = []
    while len(frames) < length:
        b = mem[a]
        if b >> 3 >= 24:
            frames += batches[((b >> 3) - 23, b & 7)]
            a += 1
        else:
            frames.append(word(mem, a))
            a += 2
    if len(frames) != length:
        sys.exit(f"pattern ends at ${a:04X} with {len(frames)} frames")
    return frames


def voices(path, preset):
    lists, n, length, shift = PRESETS[preset]
    mem = load(path)
    out = []
    for lst in lists:
        frames = []
        for i in range(n):
            frames += pattern(mem, word(mem, lst + 2 * i), length)
        out.append([(w >> 11, (w & 0x7FF) << shift) for w in frames])
    return out


def dump_freqs(path):
    """Per-frame frequency of each voice; '....' in a dump means unchanged."""
    out, cur = [[], [], []], [0, 0, 0]
    for line in open(path, errors="replace"):
        if not line.startswith("|") or "Frame" in line:
            continue
        cols = line.split("|")
        for v in range(3):
            f = cols[2 + v].split()[0]
            if f != "....":
                cur[v] = int(f, 16)
            out[v].append(cur[v])
    return out


def best(coco, sid):
    """Return (fraction matching, frame offset, ratio, frames compared)."""
    top = (0, 0, 0, 0)
    for off in range(-MAX_OFFSET, MAX_OFFSET + 1):
        rs = [sid[i + off] / f for i, (wave, f) in enumerate(coco)
              if 0 <= i + off < len(sid) and wave and f and sid[i + off]]
        if not rs:
            continue
        ratio = statistics.median(rs)
        hit = sum(abs(r / ratio - 1) < TOLERANCE for r in rs) / len(rs)
        if hit > top[0]:
            top = (hit, off, ratio, len(rs))
    return top


def main(preset, binpath, dumppath):
    sid = dump_freqs(dumppath)
    for v, coco in enumerate(voices(binpath, preset)):
        hit, off, ratio, n = best(coco, sid[v])
        print(f"voice {v + 1}: {hit:6.1%} match, offset {off:+d}, "
              f"ratio {ratio:.3f}, {n} frames, song {len(coco)} frames")


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in PRESETS:
        sys.exit(__doc__)
    main(*sys.argv[1:])
