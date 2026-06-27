// switch_mirror: mirror SW onto LEDR and show its value on HEX0..HEX2.
// Ten switches are exactly three hex digits, so no decimal conversion is needed.

#include "mmio.h"
#include "config.h"

int main(void)
{
    // the top three displays are not part of this demo
    HEX3 = HEX_BLANK;
    HEX4 = HEX_BLANK;
    HEX5 = HEX_BLANK;

    for (;;) {
        uint32_t value = SW & SW_MASK;

        LEDR = value;
        HEX0 = seven_seg_digits[value & 0xFu];
        HEX1 = seven_seg_digits[(value >> 4) & 0xFu];
        HEX2 = seven_seg_digits[(value >> 8) & 0xFu];

        delay_cycles(MIRROR_DELAY);
    }
}
