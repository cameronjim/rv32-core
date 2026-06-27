// counter: count up on HEX0..HEX3 in decimal, wrapping at 9999.
// Digits are kept as BCD and carried by hand, so no divide is needed.

#include "mmio.h"
#include "config.h"

#define DIGITS 4u

int main(void)
{
    unsigned digit[DIGITS] = {0u, 0u, 0u, 0u};

    // HEX4 and HEX5 stay dark for the whole run
    HEX4 = HEX_BLANK;
    HEX5 = HEX_BLANK;

    for (;;) {
        for (unsigned i = 0u; i < DIGITS; i++) {
            HEX(i) = seven_seg_digits[digit[i]];
        }

        delay_cycles(COUNTER_DELAY);

        for (unsigned i = 0u; i < DIGITS; i++) {
            digit[i]++;
            if (digit[i] < 10u) {
                break;
            }
            digit[i] = 0u;
        }
    }
}
