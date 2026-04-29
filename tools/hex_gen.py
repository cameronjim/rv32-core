"""Convert a flat RISC-V binary into a $readmemh image for imem.

One 32-bit little-endian word per line, preceded by an @00000000 word-index
header. objcopy -O verilog packs four words per line and its byte order has
moved between binutils releases, so the hex files are generated here instead.

Usage: python tools/hex_gen.py <input.bin> <output.hex>
"""

import struct
import sys


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: hex_gen.py <input.bin> <output.hex>\n")
        return 2

    with open(argv[1], "rb") as src:
        data = src.read()

    # pad the tail so the last partial word still lands in memory
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)

    words = struct.unpack("<%dI" % (len(data) // 4), data)

    with open(argv[2], "w", newline="\n") as dst:
        dst.write("@00000000\n")
        for word in words:
            dst.write("%08x\n" % word)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
