// uart.h: text output helpers over the memory mapped uart transmitter.
// The register contract is in mmio.h: a byte written to UART_DATA is dropped
// while UART_STATUS bit 0 is set, so every helper here polls first.
//
// Same shape as the mmio.h helpers: everything is static inline, because a
// program is one translation unit and the compiler drops whatever it does not
// call. Nothing here needs a delay constant, so this file does not pull in
// config.h and can be included on its own.

#ifndef UART_H
#define UART_H

#include <stdint.h>

#include "mmio.h"

// Send one byte. The spin is on a volatile read, so -O2 cannot hoist it out of
// the loop. busy already reads 1 in the cycle a write is accepted, which is
// what makes poll-then-write safe with no gap in between.
static inline void uart_putc(char c)
{
    while ((UART_STATUS & UART_BUSY_MASK) != 0u) {
        // spin until the transmitter goes idle
    }

    UART_DATA = (uint32_t)(unsigned char)c;
}

static inline void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putc(*s);
        s++;
    }
}

// eight lowercase hex digits, most significant first, no 0x prefix
static inline void uart_put_hex(uint32_t value)
{
    for (int i = 7; i >= 0; i--) {
        unsigned nibble = (unsigned)((value >> (4 * i)) & 0xFu);

        uart_putc((char)(nibble < 10u ? ('0' + nibble) : ('a' + nibble - 10u)));
    }
}

// Unsigned decimal, no leading zeros. RV32I has no divide instruction, so each
// digit comes out of repeated subtraction against a power of ten, which costs
// at most nine subtractions per digit and needs no soft divide from libgcc.
static inline void uart_put_dec(uint32_t value)
{
    static const uint32_t powers[10] = {
        1000000000u, 100000000u, 10000000u, 1000000u, 100000u,
        10000u,      1000u,      100u,      10u,      1u
    };

    unsigned started = 0u;

    for (unsigned i = 0u; i < 10u; i++) {
        unsigned digit = 0u;

        while (value >= powers[i]) {
            value -= powers[i];
            digit++;
        }

        // the last place always prints, so a value of 0 comes out as "0"
        if ((digit != 0u) || (started != 0u) || (i == 9u)) {
            started = 1u;
            uart_putc((char)('0' + digit));
        }
    }
}

#endif // UART_H
