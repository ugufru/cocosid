#!/usr/bin/env python3
"""Code-tracing 6809 disassembler for CoCo LOADM (DECB) binaries.

Follows control flow from the exec address (and any extra entry points given
with -e), so code and data are separated. Output is lwasm source that
reassembles byte-for-byte to the original segments.

usage: dis6809.py FILE.BIN [-e ADDR ...] [-d ADDR[-ADDR] ...] > out.asm
"""
import argparse
import sys

IDXREG = ["X", "Y", "U", "S"]
TFRREG = {0: "D", 1: "X", 2: "Y", 3: "U", 4: "S", 5: "PC",
          8: "A", 9: "B", 10: "CC", 11: "DP"}
STACKBITS = ["CC", "A", "B", "DP", "X", "Y", None, "PC"]  # bit 6 is U or S

# ---------------------------------------------------------------- opcode table
OPS = {}  # (page, opcode) -> (mnemonic, mode)

def _row(page, base, names, wide=()):
    """Fill a 4-row ALU block: imm, dir, idx, ext."""
    for col, name in enumerate(names):
        if name is None:
            continue
        for row, mode in enumerate(("imm", "dir", "idx", "ext")):
            if mode == "imm":
                if name in ("STA", "STB", "STD", "STU", "STX", "JSR",
                            "STY", "STS"):
                    continue
                mode = "imm16" if name in wide else "imm8"
            OPS[(page, base + row * 0x10 + col)] = (name, mode)

UNARY = {0x0: "NEG", 0x3: "COM", 0x4: "LSR", 0x6: "ROR", 0x7: "ASR",
         0x8: "ASL", 0x9: "ROL", 0xA: "DEC", 0xC: "INC", 0xD: "TST",
         0xE: "JMP", 0xF: "CLR"}
for lo, name in UNARY.items():
    OPS[(0, 0x00 + lo)] = (name, "dir")
    OPS[(0, 0x60 + lo)] = (name, "idx")
    OPS[(0, 0x70 + lo)] = (name, "ext")
    if name != "JMP":
        OPS[(0, 0x40 + lo)] = (name + "A", "inh")
        OPS[(0, 0x50 + lo)] = (name + "B", "inh")

_row(0, 0x80, ["SUBA", "CMPA", "SBCA", "SUBD", "ANDA", "BITA", "LDA", "STA",
               "EORA", "ADCA", "ORA", "ADDA", "CMPX", "JSR", "LDX", "STX"],
     wide=("SUBD", "CMPX", "LDX"))
_row(0, 0xC0, ["SUBB", "CMPB", "SBCB", "ADDD", "ANDB", "BITB", "LDB", "STB",
               "EORB", "ADCB", "ORB", "ADDB", "LDD", "STD", "LDU", "STU"],
     wide=("ADDD", "LDD", "LDU"))
OPS[(0, 0x8D)] = ("BSR", "rel8")

for op, name, mode in [
        (0x12, "NOP", "inh"), (0x13, "SYNC", "inh"), (0x16, "LBRA", "rel16"),
        (0x17, "LBSR", "rel16"), (0x19, "DAA", "inh"), (0x1A, "ORCC", "imm8"),
        (0x1C, "ANDCC", "imm8"), (0x1D, "SEX", "inh"), (0x1E, "EXG", "reg"),
        (0x1F, "TFR", "reg"), (0x30, "LEAX", "idx"), (0x31, "LEAY", "idx"),
        (0x32, "LEAS", "idx"), (0x33, "LEAU", "idx"), (0x34, "PSHS", "stk"),
        (0x35, "PULS", "stk"), (0x36, "PSHU", "stk"), (0x37, "PULU", "stk"),
        (0x39, "RTS", "inh"), (0x3A, "ABX", "inh"), (0x3B, "RTI", "inh"),
        (0x3C, "CWAI", "imm8"), (0x3D, "MUL", "inh"), (0x3F, "SWI", "inh")]:
    OPS[(0, op)] = (name, mode)

BRANCHES = ["BRA", "BRN", "BHI", "BLS", "BCC", "BCS", "BNE", "BEQ",
            "BVC", "BVS", "BPL", "BMI", "BGE", "BLT", "BGT", "BLE"]
for i, name in enumerate(BRANCHES):
    OPS[(0, 0x20 + i)] = (name, "rel8")
    if i:
        OPS[(1, 0x20 + i)] = ("L" + name, "rel16")

OPS[(1, 0x3F)] = ("SWI2", "inh")
OPS[(2, 0x3F)] = ("SWI3", "inh")
for base, mode in ((0x80, "imm16"), (0x90, "dir"), (0xA0, "idx"), (0xB0, "ext")):
    OPS[(1, base + 0x3)] = ("CMPD", mode)
    OPS[(1, base + 0xC)] = ("CMPY", mode)
    OPS[(1, base + 0xE)] = ("LDY", mode)
    OPS[(2, base + 0x3)] = ("CMPU", mode)
    OPS[(2, base + 0xC)] = ("CMPS", mode)
    if mode != "imm16":
        OPS[(1, base + 0xF)] = ("STY", mode)
for base, mode in ((0xC0, "imm16"), (0xD0, "dir"), (0xE0, "idx"), (0xF0, "ext")):
    OPS[(1, base + 0xE)] = ("LDS", mode)
    if mode != "imm16":
        OPS[(1, base + 0xF)] = ("STS", mode)

# ------------------------------------------------------------- known addresses
EQUATES = {
    0xFF00: "PIA0DA", 0xFF01: "PIA0CRA", 0xFF02: "PIA0DB", 0xFF03: "PIA0CRB",
    0xFF20: "PIA1DA", 0xFF21: "PIA1CRA", 0xFF22: "PIA1DB", 0xFF23: "PIA1CRB",
    0xFF40: "DSKREG", 0xFF48: "FDCREG",
    0x0100: "SW3VEC", 0x0103: "SW2VEC", 0x0106: "SWIVEC", 0x0109: "NMIVEC",
    0x010C: "IRQVEC", 0x010F: "FRQVEC",
    0xA000: "POLCAT", 0xA002: "CHROUT", 0xA004: "CSRDON", 0xA006: "BLKIN",
    0xA008: "BLKOUT", 0xA00A: "JOYIN", 0xA00C: "WRTLDR",
    0xFFF2: "VSWI3", 0xFFF4: "VSWI2", 0xFFF6: "VFIRQ", 0xFFF8: "VIRQ",
    0xFFFA: "VSWI", 0xFFFC: "VNMI", 0xFFFE: "VRESET",
}
for i, n in enumerate(["V0", "V1", "V2", "F0", "F1", "F2", "F3", "F4", "F5",
                       "F6", "P1", "R0", "R1", "M0", "M1", "TY"]):
    EQUATES[0xFFC0 + 2 * i] = f"SAM_{n}C"
    EQUATES[0xFFC1 + 2 * i] = f"SAM_{n}S"
for i in range(25):
    EQUATES[0x015E + 3 * i] = f"RVEC{i}"


def s8(v):
    return v - 0x100 if v & 0x80 else v


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def hexs(v, digits):
    if v < 0:
        return f"-${-v:0{digits}X}"
    return f"${v:0{digits}X}"


# ------------------------------------------------------------------- decoding
class Insn:
    __slots__ = ("addr", "size", "mnem", "mode", "fields", "flow", "target",
                 "ref")

class Image:
    def __init__(self, data):
        self.mem = {}
        self.segments = []
        self.exec_addr = None
        p = 0
        while p < len(data):
            kind = data[p]
            n = (data[p + 1] << 8) | data[p + 2]
            a = (data[p + 3] << 8) | data[p + 4]
            if kind == 0x00:
                for i in range(n):
                    self.mem[a + i] = data[p + 5 + i]
                self.segments.append((a, n))
                p += 5 + n
            elif kind == 0xFF:
                self.exec_addr = a
                break
            else:
                raise ValueError(f"bad LOADM block type ${kind:02X} at {p}")

    def byte(self, a):
        return self.mem.get(a & 0xFFFF)


DP = None        # default direct page register value (--dp)
DP_RANGES = []   # (lo, hi, value) overrides (--dp-at LO-HI=VV)


def dp_at(addr):
    for lo, hi, v in DP_RANGES:
        if lo <= addr <= hi:
            return v
    return DP


def decode(img, addr):
    """Decode one instruction. Returns Insn or None if undefined/off-image."""
    b = [img.byte(addr + i) for i in range(5)]
    if b[0] is None:
        return None
    page, p = 0, 0
    if b[0] in (0x10, 0x11):
        if b[1] is None:
            return None
        page, p = (1 if b[0] == 0x10 else 2), 1
    op = b[p]
    entry = OPS.get((page, op))
    if entry is None:
        return None
    mnem, mode = entry
    ins = Insn()
    ins.addr, ins.mnem, ins.mode = addr, mnem, mode
    ins.flow, ins.target, ins.ref = "next", None, None
    q = p + 1  # offset of operand
    need = {"inh": 0, "imm8": 1, "imm16": 2, "dir": 1, "ext": 2, "rel8": 1,
            "rel16": 2, "reg": 1, "stk": 1, "idx": 1}[mode]
    if any(b[q + i] is None for i in range(need)):
        return None

    if mode == "inh":
        ins.fields = ()
    elif mode == "imm8":
        ins.fields = (b[q],)
    elif mode == "imm16":
        ins.fields = ((b[q] << 8) | b[q + 1],)
    elif mode == "dir":
        ins.fields = (b[q],)
        if dp_at(addr) is not None:
            ins.ref = (dp_at(addr) << 8) | b[q]
    elif mode == "ext":
        ins.fields = ((b[q] << 8) | b[q + 1],)
        ins.ref = ins.fields[0]
    elif mode == "rel8":
        ins.target = (addr + q + 1 + s8(b[q])) & 0xFFFF
        ins.fields = ()
    elif mode == "rel16":
        ins.target = (addr + q + 2 + s16((b[q] << 8) | b[q + 1])) & 0xFFFF
        ins.fields = ()
        need = 2
    elif mode == "reg":
        r1, r2 = TFRREG.get(b[q] >> 4), TFRREG.get(b[q] & 15)
        if r1 is None or r2 is None:
            return None
        ins.fields = (r1, r2)
    elif mode == "stk":
        other = "S" if mnem.endswith("U") else "U"
        regs = [(STACKBITS[i] or other) for i in range(8) if b[q] >> i & 1]
        ins.fields = (regs,)
    elif mode == "idx":
        pb = b[q]
        reg = IDXREG[(pb >> 5) & 3]
        extra = 0
        if not pb & 0x80:
            off = pb & 0x1F
            ins.fields = ("o5", reg, off - 32 if off & 0x10 else off, False)
        else:
            ind = bool(pb & 0x10)
            t = pb & 0x0F
            if t in (0x8, 0xC):
                extra = 1
            elif t in (0x9, 0xD, 0xF):
                extra = 2
            if any(b[q + 1 + i] is None for i in range(extra)):
                return None
            if t == 0x0 and not ind:
                ins.fields = ("post", f",{reg}+", ind)
            elif t == 0x1:
                ins.fields = ("post", f",{reg}++", ind)
            elif t == 0x2 and not ind:
                ins.fields = ("post", f",-{reg}", ind)
            elif t == 0x3:
                ins.fields = ("post", f",--{reg}", ind)
            elif t == 0x4:
                ins.fields = ("post", f",{reg}", ind)
            elif t == 0x5:
                ins.fields = ("post", f"B,{reg}", ind)
            elif t == 0x6:
                ins.fields = ("post", f"A,{reg}", ind)
            elif t == 0xB:
                ins.fields = ("post", f"D,{reg}", ind)
            elif t == 0x8:
                ins.fields = ("o8", reg, s8(b[q + 1]), ind)
            elif t == 0x9:
                ins.fields = ("o16", reg, s16((b[q + 1] << 8) | b[q + 2]), ind)
            elif t == 0xC:
                ea = (addr + q + 2 + s8(b[q + 1])) & 0xFFFF
                ins.fields = ("pcr8", ea, ind)
                ins.ref = ea
            elif t == 0xD:
                ea = (addr + q + 3 + s16((b[q + 1] << 8) | b[q + 2])) & 0xFFFF
                ins.fields = ("pcr16", ea, ind)
                ins.ref = ea
            elif t == 0xF and ind and reg == "X":
                ea = (b[q + 1] << 8) | b[q + 2]
                ins.fields = ("ext_ind", ea)
                ins.ref = ea
            else:
                return None
        need = 1 + extra
    ins.size = q + need

    # control flow classification
    if mnem in ("RTS", "RTI", "SWI2", "SWI3"):
        ins.flow = "stop"
    elif mnem in ("PULS", "PULU") and "PC" in ins.fields[0]:
        ins.flow = "stop"
    elif mnem in ("BRA", "LBRA"):
        ins.flow = "jump"
    elif mnem in ("BSR", "LBSR"):
        ins.flow = "call"
    elif mnem == "BRN":
        ins.flow = "next"
        ins.target = None
    elif ins.target is not None:
        ins.flow = "branch"
    elif mnem == "JMP":
        ins.flow = "jump"
        if mode in ("ext", "dir") or (
                mode == "idx" and ins.fields[0] in ("pcr8", "pcr16")
                and not ins.fields[-1]):
            ins.target = ins.ref
    elif mnem == "JSR":
        ins.flow = "call"
        if mode in ("ext", "dir") or (
                mode == "idx" and ins.fields[0] in ("pcr8", "pcr16")
                and not ins.fields[-1]):
            ins.target = ins.ref
    elif mnem in ("TFR", "EXG") and "PC" in ins.fields[1:]:
        ins.flow = "stop" if mnem == "TFR" and ins.fields[1] == "PC" else "next"
    return ins


# ------------------------------------------------------------------- tracing
def trace(img, entries):
    code = {}           # addr -> Insn
    calls = set()
    q = list(entries)
    while q:
        a = q.pop()
        while a not in code:
            ins = decode(img, a)
            if ins is None:
                print(f"; warning: undecodable byte at ${a:04X}", file=sys.stderr)
                break
            if any((a + i) in code for i in range(1, ins.size)):
                print(f"; warning: overlap at ${a:04X}", file=sys.stderr)
            code[a] = ins
            t = ins.target
            if t is not None and img.byte(t) is not None:
                q.append(t)
                if ins.flow == "call":
                    calls.add(t)
            if ins.flow in ("stop", "jump"):
                break
            a += ins.size
    return code, calls


# ------------------------------------------------------------------- output
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("-e", "--entry", action="append", default=[],
                    help="extra code entry point (hex)")
    ap.add_argument("-d", "--data", action="append", default=[],
                    help="force a range to be data (hex, A or A-B inclusive)")
    ap.add_argument("--dp", help="direct page register value (hex)")
    ap.add_argument("--dp-at", action="append", default=[],
                    help="DP value for an address range: LO-HI=VV (hex)")
    args = ap.parse_args()
    global DP
    if args.dp:
        DP = int(args.dp, 16)
    for spec in args.dp_at:
        rng, _, val = spec.partition("=")
        lo, _, hi = rng.partition("-")
        DP_RANGES.append((int(lo, 16), int(hi or lo, 16), int(val, 16)))

    img = Image(open(args.file, "rb").read())
    entries = [img.exec_addr] + [int(e, 16) for e in args.entry]
    code, calls = trace(img, entries)
    for spec in args.data:
        lo, _, hi = spec.partition("-")
        lo, hi = int(lo, 16), int(hi or lo, 16)
        for a in list(code):
            if lo <= a <= hi:
                del code[a]

    covered = set()
    for a, ins in code.items():
        covered.update(range(a, a + ins.size))

    # labels: every in-image target or operand reference
    labels = {}
    for a, ins in code.items():
        for t, kind in ((ins.target, "code"), (ins.ref, "data")):
            if t is None or img.byte(t) is None:
                continue
            if t in calls:
                labels[t] = f"S{t:04X}"
            elif t in code and kind == "code":
                labels.setdefault(t, f"L{t:04X}")
            elif t in code:
                labels.setdefault(t, f"L{t:04X}")
            else:
                labels.setdefault(t, f"D{t:04X}")
    labels[img.exec_addr] = "START"

    # a label is "placeable" if it lands on an instruction start, or in data
    def placeable(a):
        return a in code or a not in covered
    equ_labels = {a: n for a, n in labels.items() if not placeable(a)}

    used_equ = set()

    def name(a, digits=4):
        a &= 0xFFFF
        if a in labels:
            return labels[a]
        if a in EQUATES:
            used_equ.add(a)
            return EQUATES[a]
        return f"${a:0{digits}X}"

    def operand(ins):
        m, f = ins.mode, ins.fields
        if m == "inh":
            return ""
        if m == "imm8":
            return f"#${f[0]:02X}"
        if m == "imm16":
            v = f[0]
            # immediate 16-bit values pointing into the image become labels
            if v in labels:
                return "#" + labels[v]
            return f"#${v:04X}"
        if m == "dir":
            if ins.ref in labels:
                return "<" + labels[ins.ref]
            return f"<${f[0]:02X}"
        if m == "ext":
            n = name(f[0])
            dp = dp_at(ins.addr)
            direct_able = f[0] < 0x100 or (dp is not None and f[0] >> 8 == dp)
            return (">" + n) if direct_able else n
        if m in ("rel8", "rel16"):
            return name(ins.target)
        if m == "reg":
            return f"{f[0]},{f[1]}"
        if m == "stk":
            return ",".join(f[0])
        kind = f[0]
        if kind == "o5":
            return f"{f[2]},{f[1]}"
        if kind == "post":
            s = f[1]
            return f"[{s}]" if f[2] else s
        if kind in ("o8", "o16"):
            force = "<" if kind == "o8" else ">"
            s = f"{force}{hexs(f[2], 2 if kind == 'o8' else 4)},{f[1]}"
            return f"[{s}]" if f[3] else s
        if kind in ("pcr8", "pcr16"):
            force = "<" if kind == "pcr8" else ">"
            s = f"{force}{name(f[1])},PCR"
            return f"[{s}]" if f[2] else s
        if kind == "ext_ind":
            return f"[{name(f[1])}]"
        raise AssertionError(kind)

    body = []
    cur_dp = [DP]
    for seg_addr, seg_len in img.segments:
        body.append("")
        body.append(f"\t\tORG\t${seg_addr:04X}")
        a, end = seg_addr, seg_addr + seg_len
        while a < end:
            lab = labels.get(a) if a not in equ_labels else None
            if a in code and a + code[a].size <= end:
                ins = code[a]
                if dp_at(a) != cur_dp[0] and dp_at(a) is not None:
                    cur_dp[0] = dp_at(a)
                    body.append(f"\t\tSETDP\t${cur_dp[0]:02X}")
                raw = " ".join(f"{img.byte(a + i):02X}" for i in range(ins.size))
                ops = operand(ins)
                text = f"{(lab or ''):<8}\t{ins.mnem}\t{ops}"
                pad = max(1, 40 - len(text.expandtabs(8)))
                body.append(f"{text}{' ' * pad}; {a:04X}: {raw}")
                if ins.flow in ("stop", "jump"):
                    body.append("")
                a += ins.size
                continue
            # data run: up to 8 bytes, stopping at code or another label
            run = [img.byte(a)]
            b = a + 1
            while (b < end and len(run) < 8 and b not in code
                   and (b not in labels or b in equ_labels)):
                run.append(img.byte(b))
                b += 1
            asc = "".join(chr(c) if 32 <= c < 127 else "." for c in run)
            text = f"{(lab or ''):<8}\tFCB\t" + ",".join(f"${c:02X}" for c in run)
            pad = max(1, 56 - len(text.expandtabs(8)))
            body.append(f"{text}{' ' * pad}; {a:04X}: {asc}")
            a = b

    out = []
    out.append(f"; Disassembly of {args.file}")
    out.append("; Generated by:")
    out.append(";   python3 tools/dis6809.py " + " ".join(sys.argv[1:]))
    out.append("; Reassemble with:")
    out.append(";   lwasm --format=decb -o OUT.BIN THIS.asm")
    out.append(";")
    out.append("; Segments:")
    for sa, sl in img.segments:
        out.append(f";   ${sa:04X}-${sa + sl - 1:04X} ({sl} bytes)")
    out.append(f"; Exec: ${img.exec_addr:04X}")
    out.append("")
    if DP is not None:
        out.append(f"\t\tSETDP\t${DP:02X}")
        out.append("")
    for a in sorted(used_equ):
        out.append(f"{EQUATES[a]:<8}\tEQU\t${a:04X}")
    for a in sorted(equ_labels):
        out.append(f"{equ_labels[a]:<8}\tEQU\t${a:04X}\t; inside an instruction")
    out.extend(body)
    out.append("")
    out.append("\t\tEND\tSTART")
    print("\n".join(out))

    n_code = sum(i.size for i in code.values())
    total = sum(l for _, l in img.segments)
    print(f"; {n_code} of {total} bytes traced as code, "
          f"{len(calls)} subroutines", file=sys.stderr)


if __name__ == "__main__":
    main()
