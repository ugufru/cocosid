#!/usr/bin/env python3
"""Decode the CoCoSID song data into readable lwasm source.

usage: songdump.py COCOSID.BIN > song/song.asm
       songdump.py --summary COCOSID.BIN

The output assembles byte for byte to the song block of COCOSID.BIN
($542D-$6394) and is INCLUDEd by cocosid.asm. The format is described in
song/README.md.
"""
import argparse
import sys

# Where the song lives in this build of the player (see cocosid.asm).
SONGS = [0x542D, 0x5478, 0x54C1]   # SONG1, SONG2, SONG3
PATTERNS = 0x553B                  # pattern pointer table
NPATTERNS = 0x32                   # highest pattern number used
SONG_END = 0x6395                  # first byte after the song block

ARGLEN = {0: 0, 1: 0, 2: 31, 3: 3, 4: 1, 5: 1, 6: 1, 7: 3, 8: 3}
WAVES = ["W_OFF", "W_SINE", "W_SAW", "W_TRI", "W_PULSE",
         "W_SINE2", "W_SAW2", "W_TRI2", "W_PULSE2",
         "W_SINE4", "W_SAW4", "W_TRI4", "W_PULSE4",
         "W_PWM", "W_PWM2", "W_PWM4"] + [f"W_NOISE{i}" for i in range(8)]
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def note_name(n):
    return f"{NOTE_NAMES[n % 12]}{n // 12 - 1}"


def s8(v):
    return v - 256 if v & 0x80 else v


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def load(path):
    data = open(path, "rb").read()
    mem, p = {}, 0
    while data[p] == 0:
        n = (data[p + 1] << 8) | data[p + 2]
        a = (data[p + 3] << 8) | data[p + 4]
        for i in range(n):
            mem[a + i] = data[p + 5 + i]
        p += 5 + n
    return mem


def word(mem, a):
    return (mem[a] << 8) | mem[a + 1]


def pattern_addr(mem, n):
    return word(mem, PATTERNS + 2 * n)


def parse_pattern(mem, a):
    """List of (addr, cmd, args) up to and including the 0 command."""
    cmds = []
    while True:
        c = mem[a]
        if c not in ARGLEN:
            raise ValueError(f"bad command ${c:02X} at ${a:04X}")
        cmds.append((a, c, [mem[a + 1 + i] for i in range(ARGLEN[c])]))
        a += 1 + ARGLEN[c]
        if c == 0:
            return cmds, a


def note_ticks(d, r):
    """Ticks a note command occupies, as the sequencer counts them."""
    return d + r if r else d


def simulate(mem):
    """Run the sequencer's timing until voice 1 restarts the song.

    Returns the song length in ticks and, per voice, the list of
    (start tick, list address, pattern number) entries actually played.
    """
    voices = [{"song": s, "pat": 0, "dur": 0, "gap": 0, "log": []}
              for s in SONGS]
    t = 0
    while True:
        for v in voices:
            while True:
                if v["pat"] == 0:
                    b = mem[v["song"]]
                    if b == 0:
                        break                       # voice finished
                    if b == 0xFF:
                        return t, [v["log"] for v in voices]
                    v["log"].append((t, v["song"], b))
                    v["song"] += 1
                    v["pat"] = pattern_addr(mem, b)
                if v["dur"]:
                    v["dur"] -= 1
                    break
                if v["gap"]:
                    v["gap"] -= 1
                    break
                c = mem[v["pat"]]
                if c == 0:
                    v["pat"] = 0
                    continue
                if c == 3:
                    d, r = mem[v["pat"] + 2], mem[v["pat"] + 3]
                    v["pat"] += 4
                    v["dur"], v["gap"] = (d - 1) & 0xFF, r
                    if r:
                        v["gap"] -= 1
                        v["dur"] += 1
                    break
                v["pat"] += 1 + ARGLEN[c]
        t += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--summary", action="store_true",
                    help="print song structure instead of source")
    args = ap.parse_args()
    mem = load(args.file)

    pats = {}
    for n in range(1, NPATTERNS + 1):
        pats[n] = parse_pattern(mem, pattern_addr(mem, n))
    length, logs = simulate(mem)

    used_by = {n: set() for n in pats}
    for v, log in enumerate(logs, 1):
        for _, _, n in log:
            used_by[n].add(v)

    def pat_ticks(n):
        return sum(note_ticks(a[1], a[2]) for _, c, a in pats[n][0] if c == 3)

    if args.summary:
        print(f"song length: {length} ticks")
        for v, log in enumerate(logs, 1):
            print(f"voice {v}: " + " ".join(f"{n:02X}" for _, _, n in log))
        for n in pats:
            cmds = pats[n][0]
            notes = [a for _, c, a in cmds if c == 3]
            inst = sorted({a[0] for _, c, a in cmds if c in (4, 5, 6)})
            rng = (f"{note_name(min(x[0] for x in notes))}-"
                   f"{note_name(max(x[0] for x in notes))}") if notes else ""
            print(f"PAT{n:02X} ticks {pat_ticks(n):3} voices "
                  f"{','.join(map(str, sorted(used_by[n]))) or '-':5} "
                  f"notes {len(notes):3} {rng:9} instruments {inst}")
        return

    out = []
    w = out.append

    def line(text, cmt=""):
        w((text.ljust(41) + " ; " + cmt).rstrip() if cmt else text)

    w("; CoCoSID song data: song lists, pattern table and patterns.")
    w("; Generated by: python3 tools/songdump.py " + args.file)
    w("; INCLUDEd by cocosid.asm; assembles to $%04X-$%04X." % (SONGS[0], SONG_END - 1))
    w("; The format is described in song/README.md.")
    w(";")
    w(f"; Song length {length} ticks. All three voices reach the end of their")
    w("; lists together, on the tick where voice 1's $FF restarts the song.")
    w("; Note names assume note 60 = C4; the player actually sounds about half")
    w("; a semitone flat.")
    w("")
    w("; ---------------------------------------------------------------- macros")
    for name, body, cmt in [
            ("ENDPAT", ["FCB    0"], "end of pattern"),
            ("NOP", ["FCB    1"], "no operation (unused)"),
            ("DEFINS", ["FCB    2,\\1"], "define instrument \\1; 15 FRAMEs follow"),
            ("FRAME", ["FCB    \\1,(\\2)&$FF"], "instrument frame: wave, pitch offset"),
            ("NOTE", ["FCB    3,\\1,\\2,\\3"], "note, duration, rest"),
            ("INSTR", ["FCB    6,\\1"], "select instrument (4 and 5 do the same)"),
            ("BEND", ["FCB    7,\\1", "FDB    (\\2)&$FFFF"], "ignored byte, pitch bend"),
            ("BRATE", ["FCB    8,\\1", "FDB    (\\2)&$FFFF"], "ignored byte, bend rate")]:
        line(f"{name:<10}MACRO", cmt)
        for b in body:
            w(f"{'':<10}{b}")
        w(f"{'':<10}ENDM")
    w("")
    w("; ---------------------------------------------------------------- waves")
    for i, n in enumerate(WAVES):
        w(f"{n:<10}EQU    {i}")
    w("")

    # song lists
    w("; ---------------------------------------------------------------- song lists")
    w("; One pattern number per byte. 0 stops the voice; $FF restarts the song.")
    starts = [{addr: t for t, addr, _ in log} for log in logs]
    ends = SONGS[1:] + [PATTERNS]
    for v, (lo, hi) in enumerate(zip(SONGS, ends)):
        w("")
        a = lo
        first = True
        while a < hi:
            run = []
            while a < hi and len(run) < 8:
                if mem[a] in (0, 0xFF) and run:
                    break               # end markers get a line of their own
                run.append(a)
                a += 1
                if mem[run[-1]] in (0, 0xFF):
                    break
            vals = ",".join(f"${mem[x]:02X}" for x in run)
            if run[0] in starts[v]:
                cmt = f"tick {starts[v][run[0]]}"
            elif mem[run[0]] == 0xFF:
                cmt = f"tick {length}: restart the song"
            elif mem[run[0]] == 0 and v == 1:
                cmt = f"stop (never reached: voice 1 restarts first)"
            else:
                cmt = "never reached"
            line(f"{('SONG%d' % (v + 1)) if first else '':<10}FCB    {vals}", cmt)
            first = False

    # pattern table
    w("")
    w("; ---------------------------------------------------------------- patterns")
    w("; Pattern number to address. Entry 0 is never used as a pointer, but its")
    w("; bytes $2C,$00 are read as the end of SONG3: pattern $2C, then stop.")
    t0 = starts[2].get(PATTERNS)
    line(f"{'PATTERNS':<10}FCB    ${mem[PATTERNS]:02X},${mem[PATTERNS + 1]:02X}",
         f"SONG3 tick {t0}, then stop (never reached)")
    for n in range(1, NPATTERNS + 1, 4):
        refs = ",".join(f"PAT{k:02X}" for k in range(n, min(n + 4, NPATTERNS + 1)))
        line(f"{'':<10}FDB    {refs}")

    # patterns
    for n in range(1, NPATTERNS + 1):
        cmds, _ = pats[n]
        users = sorted(used_by[n])
        w("")
        w(f"; PAT{n:02X}: {pat_ticks(n)} ticks, voice "
          + (", ".join(map(str, users)) if users else "none"))
        label = f"PAT{n:02X}"
        t = 0
        for a, c, args in cmds:
            lab = f"{label:<10}"
            label = ""
            if c == 0:
                line(f"{lab}ENDPAT")
            elif c == 1:
                line(f"{lab}NOP")
            elif c == 2:
                line(f"{lab}DEFINS {args[0]}", f"instrument {args[0]}")
                for f in range(15):
                    wave, pitch = args[1 + 2 * f], s8(args[2 + 2 * f])
                    part = ("attack" if f < 3 else "sustain" if f < 12
                            else "release")
                    cmt = f"{f:2} {part}"
                    if wave >= 16:
                        cmt += f", sounds {pitch - 40:+d}"
                    line(f"{'':<10}FRAME  {WAVES[wave]},{pitch}", cmt)
            elif c == 3:
                note, d, r = args
                line(f"{lab}NOTE   {note},{d},{r}",
                     f"{note_name(note):<4} t {t}" + ("" if r else ", tied"))
                t += note_ticks(d, r)
            elif c in (4, 5, 6):
                op = "INSTR" if c == 6 else None
                if op is None:   # never occurs in this song
                    line(f"{lab}FCB    {c},{args[0]}", f"select instrument {args[0]}")
                else:
                    line(f"{lab}INSTR  {args[0]}")
            elif c in (7, 8):
                v = s16((args[1] << 8) | args[2])
                line(f"{lab}{'BEND' if c == 7 else 'BRATE':<7}{args[0]},{v}")
    w("")
    print("\n".join(out))


if __name__ == "__main__":
    main()
