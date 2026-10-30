#!/usr/bin/env python3
"""Extract files from a CoCo Disk BASIC (RS-DOS) .DSK image."""
import sys, os

SECTOR = 256
SPT = 18
TYPES = {0: "BASIC", 1: "DATA", 2: "ML", 3: "TEXT"}

def sector(img, track, sec):  # sec is 1-based
    off = (track * SPT + sec - 1) * SECTOR
    return img[off:off + SECTOR]

def granule_offset(g):
    track = g // 2
    if track >= 17:
        track += 1
    return (track * SPT + (g % 2) * 9) * SECTOR

def main(path, outdir):
    img = open(path, "rb").read()
    fat = sector(img, 17, 2)[:68]
    os.makedirs(outdir, exist_ok=True)
    for s in range(3, 12):
        d = sector(img, 17, s)
        for i in range(0, SECTOR, 32):
            e = d[i:i + 32]
            if e[0] == 0xFF:
                return
            if e[0] == 0x00:
                continue
            name = e[0:8].decode("latin-1").rstrip()
            ext = e[8:11].decode("latin-1").rstrip()
            ftype, ascii_flag, g = e[11], e[12], e[13]
            last_bytes = (e[14] << 8) | e[15]
            data = bytearray()
            chain = []
            while True:
                chain.append(g)
                nxt = fat[g]
                off = granule_offset(g)
                if nxt >= 0xC0:
                    nsec = nxt & 0x1F
                    data += img[off:off + (nsec - 1) * SECTOR + last_bytes]
                    break
                data += img[off:off + 9 * SECTOR]
                g = nxt
            fname = f"{name}.{ext}" if ext else name
            open(os.path.join(outdir, fname), "wb").write(data)
            print(f"{fname:14} {TYPES.get(ftype, ftype):6} "
                  f"{'ASCII' if ascii_flag else 'BIN':5} {len(data):6} bytes  granules {chain}")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
