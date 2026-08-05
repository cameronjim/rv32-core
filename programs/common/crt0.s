# crt0.s: reset entry for rv32-core programs.
# Sets sp and gp, zeroes .sbss and .bss (nothing else clears dmem), then calls
# main. If main returns, the done magic lands at 0x1FFC and the core spins.
# Pure rv32i, no compressed instructions.

    .section .text.init, "ax"
    .global _start
    .type _start, @function

_start:
    # stack pointer first, so any call below has somewhere to spill
    lui     sp, %hi(__stack_top)
    addi    sp, sp, %lo(__stack_top)

    # gp must be materialized without relaxation, or the linker rewrites the
    # sequence into a gp-relative load of gp itself
.option push
.option norelax
    lui     gp, %hi(__global_pointer$)
    addi    gp, gp, %lo(__global_pointer$)
.option pop

    # zero .sbss + .bss a word at a time; the linker aligns both ends to 4
    lui     t0, %hi(__bss_start)
    addi    t0, t0, %lo(__bss_start)
    lui     t1, %hi(__bss_end)
    addi    t1, t1, %lo(__bss_end)
.Lbss_loop:
    bgeu    t0, t1, .Lbss_done
    sw      zero, 0(t0)
    addi    t0, t0, 4
    jal     zero, .Lbss_loop
.Lbss_done:

    # no argc, no argv, no environment
    addi    a0, zero, 0
    addi    a1, zero, 0
    jal     ra, main

    # demo programs never get here; test style programs do, and the magic word
    # is what tb/cpu_top_tb.sv watches for
    li      t0, 0x0000600D
    li      t1, 0x00001FFC
    sw      t0, 0(t1)
.Lhalt:
    jal     zero, .Lhalt

    .size _start, . - _start
