#!/usr/bin/env python3
"""Compare what two DECB (LOADM) binaries load into memory.

Two files can load identical bytes yet differ as files, because an
assembler is free to split or merge contiguous blocks. This compares the
loaded memory images and exec addresses instead. Exit status 0 means the
same.

usage: decb_cmp.py A.BIN B.BIN
"""
import sys


def load(path):
    b = open(path, "rb").read()
    mem, p = {}, 0
    while b[p] == 0:
        n = (b[p + 1] << 8) | b[p + 2]
        a = (b[p + 3] << 8) | b[p + 4]
        for i in range(n):
            mem[a + i] = b[p + 5 + i]
        p += 5 + n
    if b[p] != 0xFF:
        sys.exit(f"{path}: bad block type ${b[p]:02X} at offset {p}")
    return mem, (b[p + 3] << 8) | b[p + 4]


def main(a, b):
    (ma, xa), (mb, xb) = load(a), load(b)
    diff = sorted(x for x in ma.keys() | mb.keys() if ma.get(x) != mb.get(x))
    if xa != xb:
        print(f"exec addresses differ: ${xa:04X} ${xb:04X}")
    if diff:
        print(f"{len(diff)} bytes differ, first at ${diff[0]:04X}")
    if diff or xa != xb:
        sys.exit(1)
    print(f"same: {len(ma)} bytes loaded, exec ${xa:04X}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
