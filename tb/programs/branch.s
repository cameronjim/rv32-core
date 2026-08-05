# branch.s: control flow coverage. Every conditional branch is exercised once
# taken and once not taken, including a signed/unsigned disagreeing pair.
# Also covers jal plus jalr return, a jalr through an odd target address,
# lui and auipc.
# x31 counts wrong-path instructions and must end at 0. x30 counts the
# fall-through markers after the not-taken branches and must end at 6.
# Signals done by storing 0x0000600D to the last dmem word at 0x00001FFC.

    .text
    .globl _start
_start:
    addi x5, x0, 5          # x5  = 0x00000005
    addi x6, x0, 5          # x6  = 0x00000005
    addi x7, x0, -1         # x7  = 0xFFFFFFFF
    addi x8, x0, 1          # x8  = 0x00000001
    addi x30, x0, 0         # x30 = fall-through counter
    addi x31, x0, 0         # x31 = poison counter, must stay 0

    beq  x5, x6, beq_t      # taken, 5 == 5
    addi x31, x31, 1        # wrong path
beq_t:
    beq  x5, x8, beq_nt     # not taken, 5 != 1
    addi x30, x30, 1        # fall-through marker
beq_nt:

    bne  x5, x8, bne_t      # taken, 5 != 1
    addi x31, x31, 1        # wrong path
bne_t:
    bne  x5, x6, bne_nt     # not taken, 5 == 5
    addi x30, x30, 1        # fall-through marker
bne_nt:

    blt  x7, x8, blt_t      # taken, -1 < 1 signed
    addi x31, x31, 1        # wrong path
blt_t:
    blt  x8, x7, blt_nt     # not taken, 1 < -1 signed is false
    addi x30, x30, 1        # fall-through marker
blt_nt:

    bge  x8, x7, bge_t      # taken, 1 >= -1 signed
    addi x31, x31, 1        # wrong path
bge_t:
    bge  x7, x8, bge_nt     # not taken, -1 >= 1 signed is false
    addi x30, x30, 1        # fall-through marker
bge_nt:

# bltu x7, x8 disagrees with blt x7, x8 above: same operands, opposite outcome
    bltu x8, x7, bltu_t     # taken, 1 < 0xFFFFFFFF unsigned
    addi x31, x31, 1        # wrong path
bltu_t:
    bltu x7, x8, bltu_nt    # not taken, 0xFFFFFFFF < 1 unsigned is false
    addi x30, x30, 1        # fall-through marker
bltu_nt:

    bgeu x7, x8, bgeu_t     # taken, 0xFFFFFFFF >= 1 unsigned
    addi x31, x31, 1        # wrong path
bgeu_t:
    bgeu x8, x7, bgeu_nt    # not taken, 1 >= 0xFFFFFFFF unsigned is false
    addi x30, x30, 1        # fall-through marker
bgeu_nt:

# jal call, subroutine returns with jalr through ra
    jal  x1, subr           # x1  = 0x0000007C, address of the next instruction
    addi x21, x0, 0x33      # x21 = 0x00000033, only runs if the return worked

# jalr through a register holding the target address plus 1: the core must
# clear bit 0, otherwise the auipc below reads back an odd pc
    lui  x23, %hi(after_jalr)
    addi x23, x23, %lo(after_jalr)
    addi x23, x23, 1        # x23 = 0x00000095, after_jalr + 1
    jalr x0, 0(x23)
    addi x31, x31, 1        # wrong path
after_jalr:
    addi x24, x0, 0x55      # x24 = 0x00000055
    auipc x25, 0            # x25 = 0x00000098, address of this instruction
    andi x26, x25, 3        # x26 = 0x00000000 only if bit 0 was cleared

# lui and auipc results
    auipc x27, 0x1          # x27 = 0x000010A0, this address plus 0x1000
    lui  x28, 0xABCDE       # x28 = 0xABCDE000
    lui  x29, 0x80000       # x29 = 0x80000000

# done: store the magic word to the last dmem word
    lui  x9, 0x2
    addi x9, x9, -4         # x9  = 0x00001FFC
    lui  x10, 0x6
    addi x10, x10, 0x00D    # x10 = 0x0000600D
    sw   x10, 0(x9)

done_loop:
    jal  x0, done_loop

subr:
    addi x20, x0, 0x77      # x20 = 0x00000077
    addi x22, x0, 0x99      # x22 = 0x00000099
    jalr x0, 0(x1)          # return
