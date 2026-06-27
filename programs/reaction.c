// reaction: wait a pseudo random delay, light an LED, then measure how many
// cycles pass before a KEY press. The count shows on HEX0..HEX5 in hex.
// The seed comes from the free running cycle counter, so the first delay
// depends on when the core was released from reset.

#include "mmio.h"
#include "config.h"

#define REACT_GO_LED   0x020u // the LED that means "press now"
#define REACT_DONE_LED 0x3FFu // all lit once a press was measured
#define REACT_MISS_LED 0x001u // nobody pressed before the timeout

// 32 bit maximal length LFSR, taps 32, 22, 2, 1 in right shifting form
static uint32_t lfsr_next(uint32_t state)
{
    uint32_t feedback = (state & 1u) ? 0xA3000000u : 0u;
    return (state >> 1) ^ feedback;
}

int main(void)
{
    // CYCLE is never 0 by the time this runs, but force a nonzero seed anyway
    uint32_t state = CYCLE | 1u;

    for (;;) {
        state = lfsr_next(state);

        LEDR = 0x000u;
        hex_blank_all();
        delay_cycles(REACT_DELAY_MIN + (state & REACT_DELAY_MASK));

        LEDR = REACT_GO_LED;
        uint32_t start = CYCLE;

        // bounded poll so the demo cannot wedge when no button ever arrives.
        // The deadline is read off CYCLE, so it is an exact wall clock window
        // and does not shift with the cost of one poll iteration.
        uint32_t missed = 0u;
        while ((KEY & KEY_MASK) == 0u) {
            if ((CYCLE - start) >= REACT_TIMEOUT) {
                missed = 1u;
                break;
            }
        }

        uint32_t elapsed = CYCLE - start;

        LEDR = missed ? REACT_MISS_LED : REACT_DONE_LED;
        hex_show_u24(elapsed);

        // hold the result, then wait for the button to come back up so one
        // long press cannot count as the next round. Same wall clock bound,
        // with its own start so a stuck button cannot wedge the demo either.
        delay_cycles(REACT_HOLD);
        start = CYCLE;
        while ((KEY & KEY_MASK) != 0u && (CYCLE - start) < REACT_TIMEOUT) {
            // spin
        }
    }
}
