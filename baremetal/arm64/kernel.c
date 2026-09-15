#include <stdint.h>

__attribute__((noreturn)) void rubyos_exception_report(uint64_t esr, uint64_t elr, uint64_t far)
{ (void)esr; (void)elr; (void)far; for (;;) __asm__ volatile("wfe"); }

#define PL011_BASE 0x09000000UL
#define PL011_DR   (*(volatile uint32_t *)(PL011_BASE + 0x000))
#define PL011_FR   (*(volatile uint32_t *)(PL011_BASE + 0x018))
#define PL011_TXFF (1U << 5)

/* The bootstrap assembly is shared with the complete CRuby kernel. These
 * entry points keep this deliberately single-core, pre-runtime rung linkable
 * while secondary CPUs remain parked and interrupts remain disabled. */
uint64_t rubyos_ap_stack_top[4];

__attribute__((noreturn)) void rubyos_ap_main(uint32_t index)
{
    (void)index;
    for (;;) __asm__ volatile("wfe");
}

void rubyos_irq_handler(void) {}

static void serial_putc(char value)
{
    while (PL011_FR & PL011_TXFF) {
        __asm__ volatile("yield");
    }
    PL011_DR = (uint32_t)(unsigned char)value;
}

static void serial_puts(const char *text)
{
    while (*text != '\0') {
        if (*text == '\n') {
            serial_putc('\r');
        }
        serial_putc(*text++);
    }
}

void rubyos_kernel_main(uint64_t dtb_address)
{
    (void)dtb_address;
    serial_puts("[RubyOS/arm64] boot: serial OK\n");
    serial_puts("[RubyOS/arm64] boot: EL1 and FPU ready\n");
    serial_puts("[RubyOS/arm64] next: freestanding CRuby\n");

    for (;;) {
        __asm__ volatile("wfe");
    }
}
