#include <stddef.h>
#include <stdint.h>
#include <ruby.h>
#include "kernel_source.h"
#include "../../platform/boot/io.h"

extern int rubyos_tls_init(void);
extern void *aligned_alloc(size_t, size_t);
extern void *memset(void *, int, size_t);
extern uintptr_t rela_dyn_start[], rela_dyn_end[], init_array_start[], init_array_end[];

static void putc1(char c) { while (!(inb(0x3fd) & 0x20)) {} outb(0x3f8, (uint8_t)c); }
static void puts1(const char *s) { while (*s) { if (*s == '\n') putc1('\r'); putc1(*s++); } }
void rubyos_serial_puts(const char *s) { puts1(s); }
static void halt(void) { __asm__ volatile("cli"); for (;;) __asm__ volatile("hlt"); }
static uint64_t ticks(void) { uint32_t lo, hi; __asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi)); return ((uint64_t)hi << 32) | lo; }
static VALUE serial_write(VALUE self, VALUE s) { (void)self; puts1(StringValueCStr(s)); return Qnil; }
static VALUE monotonic_ns(VALUE self) { (void)self; return ULL2NUM(ticks()); }
static VALUE sleep_us(VALUE self, VALUE us) { uint64_t end = ticks() + NUM2ULL(us) * 1000; (void)self; while ((int64_t)(end - ticks()) > 0) __asm__ volatile("pause"); return Qnil; }
static VALUE dma_alloc(VALUE self, VALUE n) { size_t size = (NUM2ULL(n) + 4095) & ~(size_t)4095; (void)self; void *p = aligned_alloc(4096, size); if (!p) rb_raise(rb_eNoMemError, "DMA allocation failed"); memset(p, 0, size); return ULL2NUM((uintptr_t)p); }
static VALUE full_message(VALUE e) { return rb_funcall(e, rb_intern("full_message"), 0); }

void rubyos_x86_64_start(uint64_t magic, uint64_t info) {
    (void)magic; (void)info;
    outb(0x3f9,0); outb(0x3fb,0x80); outb(0x3f8,1); outb(0x3f9,0); outb(0x3fb,3); outb(0x3fa,0xc7); outb(0x3fc,0x0b);
    puts1("[RubyOS/x86_64] boot: entering CRuby 4.0.6\n");
    if (!rubyos_tls_init()) { puts1("[RubyOS/x86_64] FATAL: TLS\n"); halt(); }
    static char n[]="rubyos", e[]="-e", empty[]=""; static char *av[]={n,e,empty,0};
    int ac=3, state, msg_state=0; char **argv=av; VALUE anchor, os, hal, message;
    ruby_sysinit(&ac, &argv); ruby_init_stack(&anchor);
    state=ruby_setup();
    if (state) { puts1("[RubyOS/x86_64] FATAL: ruby_setup\n"); halt(); }
    (void)ruby_options(ac, argv);
    os=rb_define_module("RubyOS"); hal=rb_define_module_under(os,"HAL");
    rb_define_module_function(hal,"serial_write",serial_write,1);
    rb_define_module_function(hal,"monotonic_ns",monotonic_ns,0);
    rb_define_module_function(hal,"sleep_us",sleep_us,1);
    rb_define_module_function(hal,"dma_alloc",dma_alloc,1);
    rb_eval_string_protect(rubyos_kernel_source,&state);
    if (state) { puts1("[RubyOS/x86_64] FATAL: embedded Ruby raised\n"); message=rb_protect(full_message,rb_errinfo(),&msg_state); if (!msg_state) puts1(StringValueCStr(message)); }
    halt();
}
