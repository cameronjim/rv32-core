// memtest: walking-ones and address-pattern checks over a fixed dmem window.
// The window starts at MEMTEST_BASE, above every program's data and bss and
// far below the stack, so nothing the test writes disturbs the running image.
// LEDR reports the result: 0x3FF on success, a failure code otherwise.

#include "mmio.h"
#include "config.h"

// LEDR codes
#define MEMTEST_PHASE_WALK 0x001u
#define MEMTEST_PHASE_ADDR 0x002u
#define MEMTEST_PASS       0x3FFu
#define MEMTEST_FAIL_WALK  0x200u // or'ed with the failing bit index
#define MEMTEST_FAIL_ADDR  0x100u // or'ed with the failing word index

static void halt(uint32_t code)
{
    LEDR = code;
    for (;;) {
        __asm__ volatile("" ::: "memory");
    }
}

int main(void)
{
    volatile uint32_t *window = (volatile uint32_t *)MEMTEST_BASE;

    LEDR = MEMTEST_PHASE_WALK;

    // walking ones: every bit of every word must hold both states
    for (unsigned i = 0u; i < MEMTEST_WORDS; i++) {
        for (unsigned bit = 0u; bit < 32u; bit++) {
            uint32_t pattern = 1u << bit;
            window[i] = pattern;
            if (window[i] != pattern) {
                halt(MEMTEST_FAIL_WALK | bit);
            }
        }
    }

    LEDR = MEMTEST_PHASE_ADDR;

    // address pattern: write the whole window first, then read it all back, so
    // an address line that aliases two words shows up as a mismatch
    for (unsigned i = 0u; i < MEMTEST_WORDS; i++) {
        window[i] = MEMTEST_BASE + (i << 2);
    }
    for (unsigned i = 0u; i < MEMTEST_WORDS; i++) {
        if (window[i] != MEMTEST_BASE + (i << 2)) {
            halt(MEMTEST_FAIL_ADDR | i);
        }
    }

    // leave the window holding its address pattern and report the word count
    hex_digit(0u, MEMTEST_WORDS);
    hex_digit(1u, MEMTEST_WORDS >> 4);
    halt(MEMTEST_PASS);

    return 0;
}
