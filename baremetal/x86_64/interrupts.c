#include <stdint.h>
#include "../../platform/boot/io.h"

struct idt_entry {
    uint16_t low;
    uint16_t selector;
    uint8_t ist;
    uint8_t attributes;
    uint16_t middle;
    uint32_t high;
    uint32_t reserved;
} __attribute__((packed));

struct idt_pointer { uint16_t limit; uint64_t base; } __attribute__((packed));
static struct idt_entry idt[256] __attribute__((aligned(16)));
extern void *isr_stub_table[];
extern void isr_default(void);
extern void pit_tick(void);
extern void rubyos_serial_puts(const char *);
static volatile uint64_t ticks;
static volatile uint64_t breakpoint_probes;

static void set_gate(int vector, void *handler) {
    uint64_t address = (uint64_t)(uintptr_t)handler;
    idt[vector].low = (uint16_t)address;
    idt[vector].selector = 0x08;
    idt[vector].ist = 0;
    idt[vector].attributes = 0x8e;
    idt[vector].middle = (uint16_t)(address >> 16);
    idt[vector].high = (uint32_t)(address >> 32);
    idt[vector].reserved = 0;
}

static void io_wait(void) { outb(0x80, 0); }

void rubyos_interrupts_init(void) {
    for (int vector = 0; vector < 256; ++vector) set_gate(vector, isr_default);
    for (int vector = 0; vector <= 32; ++vector) set_gate(vector, isr_stub_table[vector]);
    struct idt_pointer pointer = { sizeof idt - 1, (uint64_t)(uintptr_t)idt };
    __asm__ volatile("lidt %0" : : "m"(pointer));
    __asm__ volatile("int3");
    if (breakpoint_probes != 1) {
        rubyos_serial_puts("[RubyOS/x86_64] FATAL: IDT exception probe\n");
        for (;;) __asm__ volatile("hlt");
    }

    outb(0x20, 0x11); io_wait(); outb(0xa0, 0x11); io_wait();
    outb(0x21, 0x20); io_wait(); outb(0xa1, 0x28); io_wait();
    outb(0x21, 4); io_wait(); outb(0xa1, 2); io_wait();
    outb(0x21, 1); io_wait(); outb(0xa1, 1); io_wait();
    outb(0x21, 0xfe); outb(0xa1, 0xff);
    uint16_t divisor = 1193180U / 100U;
    outb(0x43, 0x36);
    outb(0x40, (uint8_t)divisor);
    outb(0x40, (uint8_t)(divisor >> 8));
    __asm__ volatile("sti");
}

void rubyos_x86_interrupt(uint64_t vector, uint64_t error, uint64_t rip) {
    (void)error;
    (void)rip;
    if (vector == 3) { ++breakpoint_probes; return; }
    if (vector == 32) {
        ++ticks;
        pit_tick();
        outb(0x20, 0x20);
        return;
    }
    rubyos_serial_puts("[RubyOS/x86_64] EXCEPTION\n");
    __asm__ volatile("cli");
    for (;;) __asm__ volatile("hlt");
}

uint64_t rubyos_x86_timer_ticks(void) { return ticks; }
