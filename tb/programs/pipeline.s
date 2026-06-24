# pipeline.s: hazard coverage for the five stage pipeline. Every case here is
# a classic pipeline bug: a value that is correct only if the right bypass,
# stall or flush fires. The arith, mem and branch programs already cover the
# instruction set, so this one deliberately tests nothing but the plumbing.
# x30 counts fall-through markers and must end at 1. x31 counts wrong-path
# instructions and must end at 0.
# Signals done by storing 0x0000600D to the last dmem word at 0x00001FFC.

    .text
    .globl _start
_start:
    lui  x3, 0x1            # x3  = 0x00001000, dmem base
    addi x30, x0, 0         # x30 = fall-through counter
    addi x31, x0, 0         # x31 = wrong-path counter, must stay 0

# 1. back to back dependent ALU ops: the EX/MEM bypass, feeding both operands
    addi x5, x0, 7          # x5  = 0x00000007
    add  x6, x5, x5         # x6  = 0x0000000E, rs1 and rs2 both from EX/MEM
    add  x7, x6, x5         # x7  = 0x00000015, rs1 EX/MEM, rs2 MEM/WB

# 2. dependency at distance two: the MEM/WB bypass
    addi x8, x0, 100        # x8  = 0x00000064
    addi x9, x0, 1          # x9  = 0x00000001, filler
    add  x10, x8, x8        # x10 = 0x000000C8, both operands from MEM/WB

# 3. dependency at distance three: no bypass left, the WB-to-ID read must
#    return the value the register file is being written with this cycle
    addi x11, x0, 50        # x11 = 0x00000032
    addi x12, x0, 2         # x12 = 0x00000002, filler
    addi x13, x0, 3         # x13 = 0x00000003, filler
    add  x14, x11, x11      # x14 = 0x00000064, read through the WB-to-ID bypass

# 4. store data forwarding. A store's alu_b is the immediate, so the new value
#    can only arrive through the rs2 forward into the store data path.
    addi x15, x0, 0x5A      # x15 = 0x0000005A
    sw   x15, 0(x3)         # dmem[0x1000] = 0x5A, store data from EX/MEM
    addi x16, x0, 0x6B      # x16 = 0x0000006B
    addi x17, x0, 0         # x17 = 0x00000000, filler
    sw   x16, 4(x3)         # dmem[0x1004] = 0x6B, store data from MEM/WB

# 5. load then immediate use: one load-use stall, then a MEM/WB forward
    lw   x18, 0(x3)         # x18 = 0x0000005A
    addi x19, x18, 1        # x19 = 0x0000005B

# 6. store right after a load of the same register. The loaded word has to
#    stall once and then come straight back out on the store data path.
    lw   x20, 4(x3)         # x20 = 0x0000006B
    sw   x20, 8(x3)         # dmem[0x1008] = 0x6B

# 7. branches deciding on registers computed one and two instructions earlier,
#    so branch_cmp has to compare the forwarded operands, not the stale ones
    addi x21, x0, 9         # x21 = 0x00000009
    beq  x21, x21, p_beq    # taken, both operands forwarded from EX/MEM
    addi x31, x31, 1        # wrong path
p_beq:
    addi x22, x0, 9         # x22 = 0x00000009
    addi x23, x0, 8         # x23 = 0x00000008
    bne  x22, x23, p_bne    # taken, rs1 from MEM/WB and rs2 from EX/MEM
    addi x31, x31, 1        # wrong path
p_bne:
    addi x24, x0, 4         # x24 = 0x00000004
    blt  x24, x0, p_nt      # not taken, 4 < 0 signed is false
    addi x30, x30, 1        # fall-through marker, x30 = 1
p_nt:

# 8. jalr through a just loaded register: a load-use stall followed by a jalr
#    whose rs1 comes from the forward path, not from the register file
    lui  x25, %hi(p_land)
    addi x25, x25, %lo(p_land)
    sw   x25, 12(x3)        # dmem[0x100C] = address of p_land
    lw   x26, 12(x3)        # x26 = address of p_land
    jalr x0, 0(x26)
    addi x31, x31, 1        # wrong path
p_land:
    addi x27, x0, 0x77      # x27 = 0x00000077, only reached if the jalr landed

# 9. x0 never forwards: a write to x0 is discarded, so a read of x0 one
#    instruction later must still be zero and not the discarded value
    addi x0, x0, 99         # discarded by the register file
    add  x28, x0, x0        # x28 = 0x00000000

# 10. an independent store immediately behind a load, so the data bus stall
#     has to hold the load's address while the store waits its turn
    lw   x29, 4(x3)         # x29 = 0x0000006B
    sw   x21, 16(x3)        # dmem[0x1010] = 0x00000009

# done: store the magic word to the last dmem word
    lui  x1, 0x2
    addi x1, x1, -4         # x1  = 0x00001FFC
    lui  x2, 0x6
    addi x2, x2, 0x00D      # x2  = 0x0000600D
    sw   x2, 0(x1)

done_loop:
    jal  x0, done_loop
