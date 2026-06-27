// led_blink: walk a single lit LED back and forth across LEDR[9:0].

#include "mmio.h"
#include "config.h"

#define LED_COUNT 10u

int main(void)
{
    unsigned pos = 0u;
    int      step = 1;

    for (;;) {
        LEDR = 1u << pos;
        delay_cycles(BLINK_DELAY);

        // bounce off both ends without ever repeating an endpoint
        if (step > 0) {
            if (pos == LED_COUNT - 1u) {
                step = -1;
                pos--;
            } else {
                pos++;
            }
        } else {
            if (pos == 0u) {
                step = 1;
                pos++;
            } else {
                pos--;
            }
        }
    }
}
