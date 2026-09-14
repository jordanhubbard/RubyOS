#include <stdint.h>
#include <ruby.h>
#include "kernel_source.h"

extern void *aligned_alloc(size_t alignment, size_t size);
extern void *memset(void *destination, int byte, size_t length);

#define PL011_BASE 0x09000000UL
#define PL011_DR   (*(volatile uint32_t *)(PL011_BASE + 0x000))
#define PL011_FR   (*(volatile uint32_t *)(PL011_BASE + 0x018))
#define PL011_TXFF (1U << 5)
#define PL011_RXFE (1U << 4)

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
        if (*text == '\n') serial_putc('\r');
        serial_putc(*text++);
    }
}

void rubyos_serial_puts(const char *text)
{
    serial_puts(text);
}

static void serial_put_hex(uint64_t value)
{
    static const char digits[] = "0123456789abcdef";
    int shift;

    serial_puts("0x");
    for (shift = 60; shift >= 0; shift -= 4) {
        serial_putc(digits[(value >> shift) & 0xf]);
    }
}

__attribute__((noreturn))
void rubyos_exception_report(uint64_t esr, uint64_t elr, uint64_t far)
{
    serial_puts("[RubyOS/arm64] EXCEPTION esr=");
    serial_put_hex(esr);
    serial_puts(" elr=");
    serial_put_hex(elr);
    serial_puts(" far=");
    serial_put_hex(far);
    serial_puts("\n");
    for (;;) __asm__ volatile("wfe");
}

static VALUE hal_serial_write(VALUE self, VALUE message)
{
    (void)self;
    serial_puts(StringValueCStr(message));
    return Qnil;
}

static VALUE hal_serial_readline(VALUE self)
{
    char buffer[1024];
    size_t length = 0;
    (void)self;

    for (;;) {
        unsigned char byte;
        while (PL011_FR & PL011_RXFE) __asm__ volatile("yield");
        byte = (unsigned char)PL011_DR;
        if (byte == 4 && length == 0) return Qnil;
        if (byte == '\r' || byte == '\n') {
            serial_puts("\n");
            break;
        }
        if ((byte == 8 || byte == 127) && length > 0) {
            --length;
            serial_puts("\b \b");
            continue;
        }
        if (byte >= 32 && length + 1 < sizeof(buffer)) {
            buffer[length++] = (char)byte;
            serial_putc((char)byte);
        }
    }
    return rb_utf8_str_new(buffer, (long)length);
}

static VALUE hal_mmio_read32(VALUE self, VALUE address)
{
    uintptr_t location = (uintptr_t)NUM2ULL(address);
    (void)self;
    return UINT2NUM(*(volatile uint32_t *)location);
}

static VALUE hal_mmio_write32(VALUE self, VALUE address, VALUE value)
{
    uintptr_t location = (uintptr_t)NUM2ULL(address);
    (void)self;
    *(volatile uint32_t *)location = NUM2UINT(value);
    __asm__ volatile("dmb sy" ::: "memory");
    return Qnil;
}

static VALUE hal_mmio_read8(VALUE self, VALUE address)
{
    uintptr_t location = (uintptr_t)NUM2ULL(address);
    (void)self;
    return UINT2NUM(*(volatile uint8_t *)location);
}

static VALUE hal_mmio_write8(VALUE self, VALUE address, VALUE value)
{
    uintptr_t location = (uintptr_t)NUM2ULL(address);
    (void)self;
    *(volatile uint8_t *)location = (uint8_t)NUM2UINT(value);
    __asm__ volatile("dmb sy" ::: "memory");
    return Qnil;
}

static VALUE hal_dma_alloc(VALUE self, VALUE requested)
{
    size_t size = (size_t)NUM2ULL(requested);
    size_t rounded = (size + 4095U) & ~(size_t)4095U;
    void *memory;
    (void)self;
    if (rounded < size || rounded == 0) rb_raise(rb_eArgError, "invalid DMA size");
    memory = aligned_alloc(4096, rounded);
    if (memory == NULL) rb_raise(rb_eNoMemError, "RubyOS DMA allocation failed");
    memset(memory, 0, rounded);
    return ULL2NUM((unsigned long long)(uintptr_t)memory);
}

static VALUE exception_full_message(VALUE error)
{
    return rb_funcall(error, rb_intern("full_message"), 0);
}

void rubyos_kernel_main(uint64_t dtb_address)
{
    static char program_name[] = "rubyos";
    static char eval_option[] = "-e";
    static char empty_program[] = "";
    static char *arguments[] = { program_name, eval_option, empty_program, NULL };
    int argument_count = 3;
    char **argument_values = arguments;
    VALUE stack_anchor;
    VALUE rubyos;
    VALUE hal;
    int state;

    (void)dtb_address;
    serial_puts("[RubyOS/arm64] boot: entering CRuby 4.0.6\n");

    serial_puts("[RubyOS/arm64] boot: RubyOS libc initialized\n");

    ruby_sysinit(&argument_count, &argument_values);
    ruby_init_stack(&stack_anchor);
    state = ruby_setup();
    if (state != 0) {
        VALUE error = rb_errinfo();
        int message_state = 0;
        VALUE message;

        serial_puts("[RubyOS/arm64] FATAL: ruby_setup failed state=");
        serial_put_hex((uint64_t)(unsigned)state);
        serial_puts("\n");
        message = rb_protect(exception_full_message, error, &message_state);
        if (message_state == 0) serial_puts(StringValueCStr(message));
        for (;;) __asm__ volatile("wfe");
    }
    (void)ruby_options(argument_count, argument_values);

    rubyos = rb_define_module("RubyOS");
    hal = rb_define_module_under(rubyos, "HAL");
    rb_define_module_function(hal, "serial_write", hal_serial_write, 1);
    rb_define_module_function(hal, "serial_readline", hal_serial_readline, 0);
    rb_define_module_function(hal, "mmio_read32", hal_mmio_read32, 1);
    rb_define_module_function(hal, "mmio_write32", hal_mmio_write32, 2);
    rb_define_module_function(hal, "mmio_read8", hal_mmio_read8, 1);
    rb_define_module_function(hal, "mmio_write8", hal_mmio_write8, 2);
    rb_define_module_function(hal, "dma_alloc", hal_dma_alloc, 1);
    rb_eval_string_protect(rubyos_kernel_source, &state);
    if (state != 0) {
        VALUE error = rb_errinfo();
        int message_state = 0;
        VALUE message;

        serial_puts("[RubyOS/arm64] FATAL: embedded Ruby raised\n");
        message = rb_protect(exception_full_message, error, &message_state);
        if (message_state == 0) serial_puts(StringValueCStr(message));
    }

    for (;;) __asm__ volatile("wfe");
}
