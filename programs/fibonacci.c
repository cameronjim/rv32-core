// fibonacci: show the sequence on HEX0..HEX5 as six hex digits, restarting
// once the next term no longer fits in the 24 bits the displays can show.

#include "mmio.h"
#include "config.h"

#define FIB_MAX 0x00FFFFFFu

int main(void)
{
    for (;;) {
        uint32_t a = 0u;
        uint32_t b = 1u;

        // LEDR pulses for the length of the first term of each sequence
        LEDR = 0x001u;
        hex_show_u24(a);
        delay_cycles(FIB_DELAY);
        LEDR = 0x000u;

        for (;;) {
            uint32_t next = a + b;
            a = b;
            b = next;

            // the displays hold six hex digits, so stop before the term that
            // would no longer fit and start the sequence over
            if (a > FIB_MAX) {
                break;
            }

            hex_show_u24(a);
            delay_cycles(FIB_DELAY);
        }
    }
}
