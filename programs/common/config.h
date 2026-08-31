// config.h: delay and iteration constants for the demo programs.
// -DSIMULATION picks values small enough that a testbench sees several steps
// inside a few thousand cycles; the default values are tuned for the 50 MHz
// CPU clock on the board, which is CLOCK_50 itself now that the pipeline
// closes timing without a divider.
//
// Every time constant in this file is now a CYCLE register count. Its wall
// clock value is exact at 50 MHz and independent of the core
// microarchitecture and of what the compiler makes of a delay loop. The old
// constants were delay_loop iteration counts, which only held while an
// iteration cost two cycles: the pipeline made a taken branch cost a two
// cycle flush, an iteration went to four cycles, and every demo ran at half
// speed on the board. That was measured on hardware, not just in simulation.
// REACT_TIMEOUT was already a CYCLE count and is unchanged.

#ifndef CONFIG_H
#define CONFIG_H

#include <stdint.h>

// delay_cycles needs the CYCLE register, so config.h depends on mmio.h.
// That is the direction that keeps the dependency acyclic: mmio.h is the
// lower layer, a pure register map that includes nothing but <stdint.h> and
// knows nothing about tuning, while config.h is the policy layer on top of
// it. Putting the helper in mmio.h instead would push demo timing policy
// into the register map and give mmio.h a reason to care about SIMULATION.
// Every demo already includes mmio.h before config.h, so no call site moves.
#include "mmio.h"

#ifdef SIMULATION

#define BLINK_DELAY   192u   // led_blink: about 200 cycles per step
#define COUNTER_DELAY 96u    // counter: about 130 cycles per count
#define MIRROR_DELAY  32u    // switch_mirror: samples SW roughly every 50 cycles
#define FIB_DELAY     48u    // fibonacci: about 80 cycles per term

#define MEMTEST_WORDS 8u     // 32 bytes of the test window

#define REACT_DELAY_MIN   64u    // reaction: 64..319 cycles before the go signal
#define REACT_DELAY_MASK  0xFFu
#define REACT_TIMEOUT     2000u  // CYCLE counts before giving up on KEY
#define REACT_HOLD        128u   // CYCLE counts the result stays up

// uart_hello: the line itself dominates here, not this delay. demo_tb drops
// the transmitter's BAUD_DIV to 16, so one character is 160 cycles and a
// sixteen character count line is 2560. 64 cycles between lines keeps the
// pacing visible in a waveform without stretching the run.
#define UART_DELAY 64u

#else

// CYCLE counts at 50 MHz, so 50000000 is exactly one second.
#define BLINK_DELAY   6000000u   // 0.12 s per step
#define COUNTER_DELAY 12000000u  // 0.24 s per count
#define MIRROR_DELAY  50000u     // 1 ms, so switches feel instant
#define FIB_DELAY     25000000u  // 0.5 s per term

#define MEMTEST_WORDS 64u    // the full 256 byte test window

// 50000000 + (0 .. 0x7FFFFFF) cycles, so exactly 1.0 s to about 3.68 s
#define REACT_DELAY_MIN   50000000u
#define REACT_DELAY_MASK  0x7FFFFFFu
#define REACT_TIMEOUT     100000000u  // exactly 2.0 s before giving up on KEY
#define REACT_HOLD        100000000u  // exactly 2.0 s of result on the displays

// uart_hello: exactly 1.0 s between count lines. One line at 115200 baud is
// about 1.4 ms, so the delay is what sets the pace on the board.
#define UART_DELAY 50000000u

#endif // SIMULATION

// dmem window the memory test writes to. It sits above every program's data
// and bss and well below the stack, so nothing else in the image is disturbed.
#define MEMTEST_BASE 0x00001800u

// Busy wait for a number of CPU cycles, timed off the free running CYCLE
// register rather than by counting loop iterations, so the wall clock cost is
// exact and does not move when the core or the compiler changes what one
// iteration costs. CYCLE is a volatile read, which is what keeps -O2 from
// hoisting it out of the loop, so no asm barrier is needed.
//
// The subtraction is unsigned, so the comparison stays correct across the
// 32 bit wraparound of CYCLE: the difference is exact modulo 2^32 for any
// span shorter than the full counter period, which is about 86 s at 50 MHz,
// and every delay in this file is far shorter than that.
static inline void delay_cycles(uint32_t cycles)
{
    uint32_t start = CYCLE;

    while ((CYCLE - start) < cycles) {
        // spin
    }
}

#endif // CONFIG_H
