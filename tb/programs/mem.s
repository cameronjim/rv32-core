# mem.s: load and store coverage against dmem at 0x00001000.
# Every word is fully written with sw before any partial store, so the program
# never assumes dmem powers up as zeros.
# Signals done by storing 0x0000600D to the last dmem word at 0x00001FFC.

    .text
    .globl _start
_start:
    lui  x3, 0x1            # x3  = 0x00001000, dmem base

# sw / lw round trip at 0x1000
    lui  x5, 0xCAFEF
    addi x5, x5, 0x00D      # x5  = 0xCAFEF00D
    sw   x5, 0(x3)          # dmem[0x1000] = 0xCAFEF00D
    lw   x6, 0(x3)          # x6  = 0xCAFEF00D

# sb into each byte lane of the word at 0x1004, then read the merged word
    sw   x0, 4(x3)          # clear the word first, dmem is not assumed zero
    addi x7, x0, 0x11
    sb   x7, 4(x3)          # lane 0 = 0x11
    addi x7, x0, 0x22
    sb   x7, 5(x3)          # lane 1 = 0x22
    addi x7, x0, 0x33
    sb   x7, 6(x3)          # lane 2 = 0x33
    addi x7, x0, -122       # x7  = 0xFFFFFF86, low byte 0x86 is negative
    sb   x7, 7(x3)          # lane 3 = 0x86
    lw   x8, 4(x3)          # x8  = 0x86332211

# lb vs lbu on the negative byte in lane 3, and lb on a positive byte
    lb   x9, 7(x3)          # x9  = 0xFFFFFF86
    lbu  x10, 7(x3)         # x10 = 0x00000086
    lb   x11, 4(x3)         # x11 = 0x00000011

# sh / lh / lhu on both halves of the word at 0x1008
    sw   x0, 8(x3)          # clear the word first
    lui  x12, 0x1
    addi x12, x12, 0x234    # x12 = 0x00001234
    sh   x12, 8(x3)         # low half = 0x1234
    lui  x13, 0xFFFF8
    addi x13, x13, 0x001    # x13 = 0xFFFF8001, low half 0x8001 is negative
    sh   x13, 10(x3)        # high half = 0x8001
    lw   x14, 8(x3)         # x14 = 0x80011234
    lh   x15, 8(x3)         # x15 = 0x00001234
    lh   x16, 10(x3)        # x16 = 0xFFFF8001
    lhu  x17, 10(x3)        # x17 = 0x00008001
    lhu  x18, 8(x3)         # x18 = 0x00001234

# load results feeding later computation
    add  x19, x9, x10       # x19 = 0x0000000C, -122 + 134, lb and lbu differ
    slli x20, x17, 4        # x20 = 0x00080010
    add  x21, x6, x19       # x21 = 0xCAFEF019
    sw   x21, 12(x3)        # dmem[0x100C] = 0xCAFEF019

# sb must leave the other lanes of a nonzero word alone
    sw   x5, 16(x3)         # dmem[0x1010] = 0xCAFEF00D
    addi x22, x0, 0x5A      # x22 = 0x0000005A
    sb   x22, 17(x3)        # lane 1 only
    lw   x23, 16(x3)        # x23 = 0xCAFE5A0D

# negative load offset
    addi x24, x3, 16        # x24 = 0x00001010
    lw   x25, -16(x24)      # x25 = 0xCAFEF00D

# done: store the magic word to the last dmem word
    lui  x28, 0x2
    addi x28, x28, -4       # x28 = 0x00001FFC
    lui  x29, 0x6
    addi x29, x29, 0x00D    # x29 = 0x0000600D
    sw   x29, 0(x28)

done_loop:
    jal  x0, done_loop
