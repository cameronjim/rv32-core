// uart_hello: print a banner once over the serial line, then a counting line
// forever. The low bits of the count also go to LEDR, so the board shows the
// program is alive even with no serial adapter plugged into the header.
//
// On hardware: 115200 baud, 8N1, on GPIO_0[0], which is JP1 physical pin 1.

#include "mmio.h"
#include "config.h"
#include "uart.h"

int main(void)
{
    uint32_t count = 0u;

    uart_puts("rv32-core says hello over uart\r\n");

    for (;;) {
        LEDR = count & LEDR_MASK;

        uart_puts("count ");
        uart_put_hex(count);
        uart_puts("\r\n");

        count++;
        delay_cycles(UART_DELAY);
    }
}
