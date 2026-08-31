// mmio.h: memory mapped peripheral registers for the rv32-core board.
// Addresses come from the MMIO register map in claude-docs/architecture.md.
// Every access goes through a volatile pointer so -O2 cannot reorder or drop it.

#ifndef MMIO_H
#define MMIO_H

#include <stdint.h>

#define MMIO_BASE 0xFFFF0000u

#define MMIO_REG(offset) (*(volatile uint32_t *)(MMIO_BASE + (offset)))

// bits 9:0 drive the red LEDs, readable back for read-modify-write
#define LEDR MMIO_REG(0x0000u)

// bits 9:0, current slide switch positions, read only
#define SW MMIO_REG(0x0004u)

// bits 3:0, pushbuttons, 1 means pressed, read only
#define KEY MMIO_REG(0x0008u)

// HEX0..HEX5, bits 6:0 are segments a..g active high
#define HEX(index) MMIO_REG(0x0010u + 4u * (index))
#define HEX0 HEX(0u)
#define HEX1 HEX(1u)
#define HEX2 HEX(2u)
#define HEX3 HEX(3u)
#define HEX4 HEX(4u)
#define HEX5 HEX(5u)

// free running 32 bit cycle counter, 0 at reset, read only
#define CYCLE MMIO_REG(0x0030u)

// uart transmitter, 115200 8N1 on the board. Write bits 7:0 of UART_DATA to
// send one byte; the write is dropped while the transmitter is busy, so poll
// UART_STATUS for a clear busy bit first. The helpers in uart.h do that.
#define UART_DATA   MMIO_REG(0x0040u)
#define UART_STATUS MMIO_REG(0x0044u)

#define UART_BUSY_MASK 0x1u

#define LEDR_MASK 0x3FFu
#define SW_MASK   0x3FFu
#define KEY_MASK  0xFu

#define HEX_COUNT 6u
#define HEX_BLANK 0x00u

// segment patterns for 0..F, bit 0 is segment a through bit 6 segment g.
// External linkage on purpose: this lives in .rodata in dmem whether or not a
// given demo reads it, which keeps the data hex path exercised everywhere.
const uint8_t seven_seg_digits[16] = {
    0x3F, // 0
    0x06, // 1
    0x5B, // 2
    0x4F, // 3
    0x66, // 4
    0x6D, // 5
    0x7D, // 6
    0x07, // 7
    0x7F, // 8
    0x6F, // 9
    0x77, // A
    0x7C, // b
    0x39, // C
    0x5E, // d
    0x79, // E
    0x71  // F
};

// write one hex digit of value to display index
static inline void hex_digit(unsigned index, uint32_t value)
{
    HEX(index) = seven_seg_digits[value & 0xFu];
}

// spread the low 24 bits of value across HEX0..HEX5 as six hex digits
static inline void hex_show_u24(uint32_t value)
{
    for (unsigned i = 0u; i < HEX_COUNT; i++) {
        HEX(i) = seven_seg_digits[(value >> (4u * i)) & 0xFu];
    }
}

static inline void hex_blank_all(void)
{
    for (unsigned i = 0u; i < HEX_COUNT; i++) {
        HEX(i) = HEX_BLANK;
    }
}

#endif // MMIO_H
