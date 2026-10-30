#!/usr/bin/env python3
"""Code-tracing 6809 disassembler for CoCo LOADM (DECB) binaries.

Follows control flow from the exec address (and any extra entry points given
with -e), so code and data are separated. Output is lwasm source that
reassembles byte-for-byte to the original segments.

usage: dis6809.py FILE.BIN [-a FILE.ann] [-e ADDR ...] [-d ADDR[-ADDR] ...]
                  > out.asm

The optional annotation file supplies labels, symbols, comments and options;
see the Annotations class for its format.
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


# --------------------------------------------------------------- annotations
class Annotations:
    """Hand-written knowledge merged into the output. One directive per line:

    dp VV                   default direct page value
    dp-at LO-HI VV          direct page value for an address range
    entry ADDR ...          extra code entry points
    data LO-HI              force a range to be data
    words LO-HI             emit a data range as FDB words (numeric)
    ptrs LO-HI              emit a data range as FDB words, named where possible
    label ADDR NAME         name an address (outside the image or inside an
                            instruction it becomes an EQU)
    expr ADDR TEXT          render references to ADDR as TEXT (e.g. VOICE1+V_NOTE)
    equ NAME VALUE [; c]    define a free symbol (e.g. a structure offset)
    field REG OFF NAME      render OFF,REG (5-bit offset) as NAME,REG
    comment ADDR TEXT       end-of-line comment
    block ADDR [TEXT]       full-line comment before ADDR (repeat for more lines)
    header [TEXT]           comment line in the file header

    Addresses and values are hex. '#' starts a comment line.
    """

    def __init__(self):
        self.dp, self.dp_at = None, []
        self.entries, self.data, self.words, self.ptrs = [], [], [], []
        self.labels, self.exprs, self.fields = {}, {}, {}
        self.equs, self.comments, self.blocks, self.header = [], {}, {}, []


def hexrange(spec):
    lo, _, hi = spec.partition("-")
    return int(lo, 16), int(hi or lo, 16)


def load_annotations(path):
    ann = Annotations()
    for n, line in enumerate(open(path), 1):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        kw, _, rest = line.partition(" ")
        try:
            if kw in ("block", "header"):
                # keep the text verbatim after one separating space
                if kw == "header":
                    ann.header.append(rest)
                    continue
                addr, _, text = rest.partition(" ")
                ann.blocks.setdefault(int(addr, 16), []).append(text)
                continue
            args = rest.split(None, 2)
            if kw == "dp":
                ann.dp = int(args[0], 16)
            elif kw == "dp-at":
                ann.dp_at.append((*hexrange(args[0]), int(args[1], 16)))
            elif kw == "entry":
                ann.entries += [int(x, 16) for x in rest.split()]
            elif kw == "data":
                ann.data.append(hexrange(args[0]))
            elif kw == "words":
                ann.words.append(hexrange(args[0]))
            elif kw == "ptrs":
                ann.ptrs.append(hexrange(args[0]))
            elif kw == "label":
                ann.labels[int(args[0], 16)] = args[1]
            elif kw == "expr":
                ann.exprs[int(args[0], 16)] = " ".join(args[1:])
            elif kw == "equ":
                value, _, cmt = " ".join(args[1:]).partition(";")
                ann.equs.append((args[0], value.strip(), cmt.strip()))
            elif kw == "field":
                reg, off, name = rest.split()
                ann.fields[(reg.upper(), int(off, 16))] = name
            elif kw == "comment":
                addr, _, text = rest.partition(" ")
                ann.comments[int(addr, 16)] = text.strip()
            else:
                raise ValueError(f"unknown directive {kw!r}")
        except (IndexError, ValueError) as e:
            sys.exit(f"{path}:{n}: {e}")
    return ann


# ------------------------------------------------------------------- output
CODE_COL = 42   # column of the "; ADDR: bytes" field on code lines
DATA_COL = 56   # same, on data lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("-a", "--annotations",
                    help="annotation file with labels, comments and options")
    ap.add_argument("-e", "--entry", action="append", default=[],
                    help="extra code entry point (hex)")
    ap.add_argument("-d", "--data", action="append", default=[],
                    help="force a range to be data (hex, A or A-B inclusive)")
    ap.add_argument("--dp", help="direct page register value (hex)")
    ap.add_argument("--dp-at", action="append", default=[],
                    help="DP value for an address range: LO-HI=VV (hex)")
    args = ap.parse_args()

    ann = load_annotations(args.annotations) if args.annotations else Annotations()
    global DP
    DP = int(args.dp, 16) if args.dp else ann.dp
    DP_RANGES.extend(ann.dp_at)
    for spec in args.dp_at:
        rng, _, val = spec.partition("=")
        DP_RANGES.append((*hexrange(rng), int(val, 16)))

    img = Image(open(args.file, "rb").read())
    entries = [img.exec_addr] + ann.entries + [int(e, 16) for e in args.entry]
    code, calls = trace(img, entries)
    for lo, hi in ann.data + [hexrange(d) for d in args.data]:
        for a in list(code):
            if lo <= a <= hi:
                del code[a]

    covered = set()
    for a, ins in code.items():
        covered.update(range(a, a + ins.size))

    # labels: every in-image target or operand reference, then hand-named ones
    labels = {}
    for a, ins in code.items():
        for t in (ins.target, ins.ref):
            if t is None or img.byte(t) is None:
                continue
            if t in calls:
                labels[t] = f"S{t:04X}"
            elif t in code:
                labels.setdefault(t, f"L{t:04X}")
            else:
                labels.setdefault(t, f"D{t:04X}")
    labels[img.exec_addr] = "START"
    labels.update(ann.labels)

    # a label is placed in the listing if it lands on an instruction start or
    # in data inside the image; anything else is defined with EQU
    def placeable(a):
        return img.byte(a) is not None and (a in code or a not in covered)
    equ_labels = {a: n for a, n in labels.items() if not placeable(a)}

    words, ptrs = set(), set()
    for lo, hi in ann.words:
        words.update(range(lo, hi + 1))
    for lo, hi in ann.ptrs:
        ptrs.update(range(lo, hi + 1))
    words |= ptrs

    used_equ = set()

    def name(a):
        a &= 0xFFFF
        if a in ann.exprs:
            return ann.exprs[a]
        if a in labels:
            return labels[a]
        if a in EQUATES:
            used_equ.add(a)
            return EQUATES[a]
        return f"${a:04X}"

    def operand(ins):
        m, f = ins.mode, ins.fields
        if m == "inh":
            return ""
        if m == "imm8":
            return f"#${f[0]:02X}"
        if m == "imm16":
            v = f[0]
            # only hand-named or traced addresses become symbols; other
            # 16-bit constants stay numeric
            if v in labels:
                return "#" + labels[v]
            if v >= 0xFF00 and v in EQUATES:
                return "#" + name(v)
            if v in ann.exprs:
                return "#" + ann.exprs[v]
            return f"#${v:04X}"
        if m == "dir":
            if ins.ref in ann.exprs or ins.ref in labels:
                return "<" + name(ins.ref)
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
            field = ann.fields.get((f[1], f[2]))
            return f"{field or f[2]},{f[1]}"
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

    def emit(label, text, col, tail, addr):
        """One listing line. Long labels go on a line of their own."""
        if label and len(label) >= 10:
            body.append(label)
            label = ""
        line = f"{(label or ''):<10}{text}"
        line = line.ljust(col - 1) + " ; " + tail
        cmt = ann.comments.get(addr)
        if cmt:
            line = line.ljust(col + 22) + cmt
        body.append(line.rstrip())

    def emit_blocks(a):
        if a in ann.blocks:
            if body and body[-1] != "":
                body.append("")
            for text in ann.blocks[a]:
                body.append(("; " + text).rstrip())

    cur_dp = DP
    for seg_addr, seg_len in img.segments:
        body.append("")
        body.append(f"{'':<10}ORG    ${seg_addr:04X}")
        a, end = seg_addr, seg_addr + seg_len
        while a < end:
            emit_blocks(a)
            lab = labels.get(a) if a not in equ_labels else None
            if a in code and a + code[a].size <= end:
                ins = code[a]
                if dp_at(a) is not None and dp_at(a) != cur_dp:
                    cur_dp = dp_at(a)
                    body.append(f"{'':<10}SETDP  ${cur_dp:02X}")
                raw = " ".join(f"{img.byte(a + i):02X}" for i in range(ins.size))
                emit(lab, f"{ins.mnem:<7}{operand(ins)}", CODE_COL,
                     f"{a:04X}: {raw}", a)
                if ins.flow in ("stop", "jump"):
                    body.append("")
                a += ins.size
                continue

            def stop(b):
                return (b >= end or b in code or b in ann.blocks
                        or b in ann.comments
                        or (b in labels and b not in equ_labels))

            if a in words and a + 1 in words:
                # FDB run: up to 4 words, symbolic where the value is named
                vals = []
                b = a
                while (len(vals) < 4 and b + 1 in words and b + 1 < end
                       and (b == a or not stop(b))):
                    v = (img.byte(b) << 8) | img.byte(b + 1)
                    named = b in ptrs and (v in ann.exprs or v in labels)
                    vals.append(name(v) if named else f"${v:04X}")
                    b += 2
                emit(lab, "FDB    " + ",".join(vals), DATA_COL, f"{a:04X}", a)
                a = b
                continue
            # FCB run: up to 8 bytes
            run = [img.byte(a)]
            b = a + 1
            while len(run) < 8 and not stop(b) and b not in words:
                run.append(img.byte(b))
                b += 1
            asc = "".join(chr(c) if 32 <= c < 127 else "." for c in run)
            emit(lab, "FCB    " + ",".join(f"${c:02X}" for c in run),
                 DATA_COL, f"{a:04X}: {asc}", a)
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
    if ann.header:
        out.append(";")
        out.extend(("; " + h).rstrip() for h in ann.header)
    out.append("")
    if DP is not None:
        out.append(f"{'':<10}SETDP  ${DP:02X}")
        out.append("")

    def equ_line(name_, value, cmt=""):
        line = f"{name_ + ' ':<10}EQU    {value}"
        return (line.ljust(CODE_COL - 1) + " ; " + cmt) if cmt else line

    for n, v, c in ann.equs:
        out.append(equ_line(n, v, c))
    if ann.equs:
        out.append("")
    for a in sorted(used_equ):
        out.append(equ_line(EQUATES[a], f"${a:04X}"))
    if used_equ:
        out.append("")
    for a in sorted(equ_labels):
        where = "operand byte patched at run time" if a in covered else ""
        out.append(equ_line(equ_labels[a], f"${a:04X}",
                            ann.comments.get(a) or where))
    out.extend(body)
    out.append("")
    out.append(f"{'':<10}END    START")
    print("\n".join(out))

    n_code = sum(i.size for i in code.values())
    total = sum(l for _, l in img.segments)
    print(f"; {n_code} of {total} bytes traced as code, "
          f"{len(calls)} subroutines", file=sys.stderr)


if __name__ == "__main__":
    main()
