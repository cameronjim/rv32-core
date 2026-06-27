// config.h: delay and iteration constants for the demo programs.
// -DSIMULATION picks values small enough that a testbench sees several steps
// inside a few thousand cycles; the default values are tuned for the 50 MHz
// CPU clock on the board, which is CLOCK_50 itself now that the pipeline
// closes timing without a divider. delay_loop costs roughly two cycles per
// iteration, so 25 million iterations is about one second.
//
// Most constants here are delay_loop iteration counts, which means their wall
// clock cost depends on what a loop iteration costs on the current core.
// REACT_TIMEOUT is the exception: it is a deadline, not a delay, so it is a
// CYCLE register count and reaction.c compares it against elapsed cycles. Its
// wall clock value is exact and does not move when the core changes.

#ifndef CONFIG_H
#define CONFIG_H

#include <stdint.h>

#ifdef SIMULATION

#define BLINK_DELAY   48u    // led_blink: about 100 cycles per step
#define COUNTER_DELAY 24u    // counter: about 100 cycles per count
#define MIRROR_DELAY  8u     // switch_mirror: samples SW roughly every 40 cycles
#define FIB_DELAY     12u    // fibonacci: about 80 cycles per term

#define MEMTEST_WORDS 8u     // 32 bytes of the test window

#define REACT_DELAY_MIN   16u    // reaction: 16..79 iterations before the go signal
#define REACT_DELAY_MASK  0x3Fu
#define REACT_TIMEOUT     2000u  // CYCLE counts before giving up on KEY
#define REACT_HOLD        32u    // delay_loop iterations the result stays up

#else

// The delay_loop counts here are back to their 50 MHz values now that the
// pipeline runs the CPU domain at CLOCK_50 with no divider. Their wall clock
// times are approximate, since they depend on the cost of a loop iteration.
#define BLINK_DELAY   3000000u   // about 0.12 s per step
#define COUNTER_DELAY 6000000u   // about 0.24 s per count
#define MIRROR_DELAY  25000u     // about 1 ms, so switches feel instant
#define FIB_DELAY     12000000u  // about 0.5 s per term

#define MEMTEST_WORDS 64u    // the full 256 byte test window

#define REACT_DELAY_MIN   25000000u   // reaction: 1.0 s to about 3.7 s
#define REACT_DELAY_MASK  0x3FFFFFFu
#define REACT_TIMEOUT     100000000u  // CYCLE counts: exactly 2.0 s at 50 MHz
#define REACT_HOLD        50000000u   // about 2 s of result on the displays

#endif // SIMULATION

// dmem window the memory test writes to. It sits above every program's data
// and bss and well below the stack, so nothing else in the image is disturbed.
#define MEMTEST_BASE 0x00001800u

// Busy wait. The empty asm keeps -O2 from deleting the loop, and taking the
// count by value keeps it off the stack.
static inline void delay_loop(uint32_t iterations)
{
    while (iterations != 0u) {
        iterations--;
        __asm__ volatile("" ::: "memory");
    }
}

#endif // CONFIG_H
