# arith.s: R-type and I-type coverage for the single-cycle core.
# Leaves a distinctive value in x5 through x28, then signals done by storing
# 0x0000600D to the last dmem word at 0x00001FFC.
# x29, x30 and x31 are scratch and are not checked.

    .text
    .globl _start
_start:

# scratch operands
    lui  x29, 0x12345       # x29 = 0x12345000
    addi x29, x29, 0x678    # x29 = 0x12345678
    addi x30, x0, -16       # x30 = 0xFFFFFFF0
    addi x31, x0, 15        # x31 = 0x0000000F

# I-type arithmetic and logic
    addi x5, x29, 0x111     # x5  = 0x12345789
    addi x6, x30, -1        # x6  = 0xFFFFFFEF
    andi x7, x29, 0x0FF     # x7  = 0x00000078
    ori  x8, x29, 0x707     # x8  = 0x1234577F
    xori x9, x29, 0x0FF     # x9  = 0x12345687
    xori x10, x29, -1       # x10 = 0xEDCBA987, xori with -1 is a bitwise not

# I-type shifts, srli and srai on the same negative value disagree
    slli x11, x29, 4        # x11 = 0x23456780
    srli x12, x30, 4        # x12 = 0x0FFFFFFF
    srai x13, x30, 4        # x13 = 0xFFFFFFFF

# I-type compares, slti and sltiu on the same negative value disagree
    slti  x14, x30, 1       # x14 = 0x00000001, -16 < 1 signed
    sltiu x15, x30, 1       # x15 = 0x00000000, 0xFFFFFFF0 < 1 unsigned is false

# a shifted constant used as the operand for the remaining shift cases
    slli x16, x31, 28       # x16 = 0xF0000000
    srli x17, x16, 4        # x17 = 0x0F000000
    srai x18, x16, 4        # x18 = 0xFF000000

# R-type arithmetic and logic
    add x19, x29, x30       # x19 = 0x12345668
    sub x20, x29, x31       # x20 = 0x12345669
    and x21, x29, x16       # x21 = 0x10000000
    or  x22, x16, x31       # x22 = 0xF000000F
    xor x23, x29, x30       # x23 = 0xEDCBA988

# R-type shifts by x31 = 15, srl and sra disagree on a negative operand
    sll x24, x29, x31       # x24 = 0x2B3C0000
    srl x25, x16, x31       # x25 = 0x0001E000
    sra x26, x16, x31       # x26 = 0xFFFFE000

# R-type compares, slt and sltu on the same pair disagree
    slt  x27, x30, x31      # x27 = 0x00000001, -16 < 15 signed
    sltu x28, x30, x31      # x28 = 0x00000000, 0xFFFFFFF0 < 15 unsigned is false

# done: store the magic word to the last dmem word
    lui  x29, 0x2
    addi x29, x29, -4       # x29 = 0x00001FFC
    lui  x30, 0x6
    addi x30, x30, 0x00D    # x30 = 0x0000600D
    sw   x30, 0(x29)

done_loop:
    jal  x0, done_loop
