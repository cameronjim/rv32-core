"""Convert a RISC-V program image into a $readmemh file for imem or dmem.

One 32-bit little-endian word per line, preceded by an @00000000 word-index
header. objcopy -O verilog packs four words per line and its byte order has
moved between binutils releases, so the hex files are generated here instead.

Two input forms are accepted:

  flat binary  every byte of the file lands in memory starting at word index 0
  ELF          the loadable sections inside the requested address window are
               gathered, and word index 0 corresponds to --base

Usage:
  python tools/hex_gen.py <input.bin> <output.hex>
  python tools/hex_gen.py --base 0x1000 --size 4096 <input.elf> <output.hex>

Options:
  --base ADDR       byte address that becomes word index 0 (default 0)
  --size BYTES      size of the memory region, sections outside it are skipped
  --sections LIST   comma separated section names to take instead of every
                    allocated PROGBITS section in the window
"""

import struct
import sys

ELF_MAGIC = b"\x7fELF"

SHT_PROGBITS = 1
SHF_ALLOC = 0x2


def parse_int(text):
    return int(text, 0)


def elf_sections(blob):
    """Yield (name, addr, data) for every section header in an ELF32 LE file."""
    if blob[4] != 1 or blob[5] != 1:
        raise ValueError("only 32-bit little-endian ELF files are supported")

    (e_shoff,) = struct.unpack_from("<I", blob, 0x20)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", blob, 0x2E)
    if e_shoff == 0 or e_shnum == 0:
        raise ValueError("ELF file has no section headers")

    def header(index):
        off = e_shoff + index * e_shentsize
        # sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size
        return struct.unpack_from("<IIIIII", blob, off)

    str_off = header(e_shstrndx)[4]

    def name_at(offset):
        end = blob.index(b"\x00", str_off + offset)
        return blob[str_off + offset:end].decode("ascii")

    for index in range(e_shnum):
        sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size = header(index)
        if sh_type != SHT_PROGBITS or not (sh_flags & SHF_ALLOC) or sh_size == 0:
            continue
        yield name_at(sh_name), sh_addr, blob[sh_offset:sh_offset + sh_size]


def image_from_elf(blob, base, size, wanted):
    """Flatten the selected sections into one contiguous image starting at base."""
    limit = None if size is None else base + size
    chunks = []

    for name, addr, data in elf_sections(blob):
        if wanted is not None:
            if name not in wanted:
                continue
        elif addr < base or (limit is not None and addr >= limit):
            continue

        end = addr + len(data)
        if addr < base or (limit is not None and end > limit):
            raise ValueError(
                "section %s at 0x%08x..0x%08x does not fit the window "
                "0x%08x..%s" % (name, addr, end, base,
                                "unbounded" if limit is None else "0x%08x" % limit))
        chunks.append((addr, data))

    if not chunks:
        return b""

    top = max(addr + len(data) for addr, data in chunks)
    image = bytearray(top - base)
    for addr, data in chunks:
        image[addr - base:addr - base + len(data)] = data
    return bytes(image)


def write_hex(path, data):
    # pad the tail so the last partial word still lands in memory
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)

    words = struct.unpack("<%dI" % (len(data) // 4), data)

    with open(path, "w", newline="\n") as dst:
        dst.write("@00000000\n")
        for word in words:
            dst.write("%08x\n" % word)


def main(argv):
    base = 0
    size = None
    wanted = None
    positional = []

    args = argv[1:]
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--base":
            base = parse_int(args[i + 1])
            i += 2
        elif arg == "--size":
            size = parse_int(args[i + 1])
            i += 2
        elif arg == "--sections":
            wanted = set(part for part in args[i + 1].split(",") if part)
            i += 2
        elif arg.startswith("--"):
            sys.stderr.write("hex_gen.py: unknown option %s\n" % arg)
            return 2
        else:
            positional.append(arg)
            i += 1

    if len(positional) != 2:
        sys.stderr.write(__doc__)
        return 2

    with open(positional[0], "rb") as src:
        blob = src.read()

    if blob[:4] == ELF_MAGIC:
        try:
            data = image_from_elf(blob, base, size, wanted)
        except ValueError as err:
            sys.stderr.write("hex_gen.py: %s\n" % err)
            return 1
    else:
        if base != 0:
            sys.stderr.write("hex_gen.py: --base needs an ELF input\n")
            return 2
        data = blob

    write_hex(positional[1], data)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
