#pragma once
#include <stdint.h>

#define PL011_BASE  0x09000000UL
#define PL011_DR    (PL011_BASE + 0x000)   // Data Register
#define PL011_FR    (PL011_BASE + 0x018)   // Flag Register
#define PL011_FR_TXFF (1U << 5)            // TX FIFO full

static inline void pl011_putc(char c) {
    volatile uint32_t *fr = (volatile uint32_t *)PL011_FR;
    volatile uint32_t *dr = (volatile uint32_t *)PL011_DR;
    while (*fr & PL011_FR_TXFF) {}
    *dr = (uint32_t)(unsigned char)c;
}

static inline void pl011_puts(const char *s) {
    for (; *s; s++) {
        if (*s == '\n') pl011_putc('\r');
        pl011_putc(*s);
    }
}
