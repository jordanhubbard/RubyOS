#include <stddef.h>
#include <stdint.h>
#include <ruby.h>
#include "kernel_source.h"
#include "../../platform/boot/io.h"

extern int rubyos_tls_init(void);
extern void rubyos_interrupts_init(void);
extern uint64_t rubyos_x86_timer_ticks(void);
extern void rubyos_x86_smp_init(uint64_t);
extern uint32_t rubyos_x86_smp_cpu_count(void);
extern uint32_t rubyos_x86_smp_online_count(void);
extern uint32_t rubyos_x86_smp_selftests(void);
extern int rubyos_x86_smp_hash(uint64_t, uint64_t, uint64_t *);
extern void *aligned_alloc(size_t, size_t);
extern void free(void *);
extern void *memset(void *, int, size_t);
extern void *memcpy(void *, const void *, size_t);
extern size_t malloc_free_bytes(void);
extern size_t malloc_total_bytes(void);
extern uintptr_t rela_dyn_start[], rela_dyn_end[], init_array_start[], init_array_end[];

static void putc1(char c) { while (!(inb(0x3fd) & 0x20)) {} outb(0x3f8, (uint8_t)c); }
static void puts1(const char *s) { while (*s) { if (*s == '\n') putc1('\r'); putc1(*s++); } }
void rubyos_serial_puts(const char *s) { puts1(s); }
static void halt(void) { __asm__ volatile("cli"); for (;;) __asm__ volatile("hlt"); }
static VALUE serial_write(VALUE self, VALUE s) { (void)self; puts1(StringValueCStr(s)); return Qnil; }
static VALUE monotonic_ns(VALUE self) { (void)self; return ULL2NUM(rubyos_x86_timer_ticks() * 10000000ULL); }
static VALUE sleep_us(VALUE self, VALUE us) { uint64_t delay = (NUM2ULL(us) + 9999) / 10000; uint64_t end = rubyos_x86_timer_ticks() + delay; (void)self; while ((int64_t)(end - rubyos_x86_timer_ticks()) > 0) __asm__ volatile("hlt"); return Qnil; }
static VALUE dma_alloc(VALUE self, VALUE n) { size_t size = (NUM2ULL(n) + 4095) & ~(size_t)4095; (void)self; void *p = aligned_alloc(4096, size); if (!p) rb_raise(rb_eNoMemError, "DMA allocation failed"); memset(p, 0, size); return ULL2NUM((uintptr_t)p); }
static VALUE dma_free(VALUE self, VALUE address) { (void)self; free((void *)(uintptr_t)NUM2ULL(address)); return Qnil; }
static VALUE dma_write(VALUE self, VALUE address, VALUE bytes) { (void)self; StringValue(bytes); memcpy((void *)(uintptr_t)NUM2ULL(address), RSTRING_PTR(bytes), (size_t)RSTRING_LEN(bytes)); return LONG2NUM(RSTRING_LEN(bytes)); }
static VALUE heap_total_bytes(VALUE self) { (void)self; return ULL2NUM(malloc_total_bytes()); }
static VALUE heap_free_bytes(VALUE self) { (void)self; return ULL2NUM(malloc_free_bytes()); }
static VALUE ps2_scancode(VALUE self) { uint8_t status; (void)self; status = inb(0x64); if (!(status & 1) || (status & 0x20)) return Qnil; return UINT2NUM(inb(0x60)); }
static int ps2_wait_writable(void) { for (unsigned i = 0; i < 100000; ++i) if (!(inb(0x64) & 2)) return 1; return 0; }
static int ps2_wait_readable(void) { for (unsigned i = 0; i < 100000; ++i) if (inb(0x64) & 1) return 1; return 0; }
static int ps2_command(uint8_t command) { if (!ps2_wait_writable()) return 0; outb(0x64, command); return 1; }
static int ps2_data(uint8_t value) { if (!ps2_wait_writable()) return 0; outb(0x60, value); return 1; }
static int ps2_mouse_command(uint8_t command) { if (!ps2_command(0xd4) || !ps2_data(command) || !ps2_wait_readable()) return 0; return inb(0x60) == 0xfa; }
static VALUE ps2_mouse_init(VALUE self) {
    uint8_t config;
    (void)self;
    while (inb(0x64) & 1) (void)inb(0x60);
    if (!ps2_command(0xa8) || !ps2_command(0x20) || !ps2_wait_readable()) return Qfalse;
    config = inb(0x60); config |= 2; config &= (uint8_t)~0x20;
    if (!ps2_command(0x60) || !ps2_data(config)) return Qfalse;
    if (!ps2_mouse_command(0xf6) || !ps2_mouse_command(0xf4)) return Qfalse;
    return Qtrue;
}
static VALUE ps2_mouse_byte(VALUE self) { uint8_t status; (void)self; status = inb(0x64); if (!(status & 1) || !(status & 0x20)) return Qnil; return UINT2NUM(inb(0x60)); }
static VALUE mmio_read32(VALUE self, VALUE address) { (void)self; return UINT2NUM(*(volatile uint32_t *)(uintptr_t)NUM2ULL(address)); }
static VALUE mmio_write32(VALUE self, VALUE address, VALUE value) { (void)self; *(volatile uint32_t *)(uintptr_t)NUM2ULL(address) = NUM2UINT(value); __asm__ volatile("mfence" ::: "memory"); return Qnil; }
static VALUE mmio_read16(VALUE self, VALUE address) { (void)self; return UINT2NUM(*(volatile uint16_t *)(uintptr_t)NUM2ULL(address)); }
static VALUE mmio_write16(VALUE self, VALUE address, VALUE value) { (void)self; *(volatile uint16_t *)(uintptr_t)NUM2ULL(address) = (uint16_t)NUM2UINT(value); __asm__ volatile("mfence" ::: "memory"); return Qnil; }
static VALUE mmio_read8(VALUE self, VALUE address) { (void)self; return UINT2NUM(*(volatile uint8_t *)(uintptr_t)NUM2ULL(address)); }
static VALUE mmio_write8(VALUE self, VALUE address, VALUE value) { (void)self; *(volatile uint8_t *)(uintptr_t)NUM2ULL(address) = (uint8_t)NUM2UINT(value); __asm__ volatile("mfence" ::: "memory"); return Qnil; }
static uint32_t pci_address(unsigned bus, unsigned device, unsigned function, unsigned offset) { return 0x80000000U | (bus << 16) | (device << 11) | (function << 8) | (offset & 0xfc); }
static VALUE pci_read32(VALUE self, VALUE bus, VALUE device, VALUE function, VALUE offset) { (void)self; outl(0xcf8, pci_address(NUM2UINT(bus), NUM2UINT(device), NUM2UINT(function), NUM2UINT(offset))); return UINT2NUM(inl(0xcfc)); }
static VALUE pci_write32(VALUE self, VALUE bus, VALUE device, VALUE function, VALUE offset, VALUE value) { (void)self; outl(0xcf8, pci_address(NUM2UINT(bus), NUM2UINT(device), NUM2UINT(function), NUM2UINT(offset))); outl(0xcfc, NUM2UINT(value)); return Qnil; }
static VALUE full_message(VALUE e) { return rb_funcall(e, rb_intern("full_message"), 0); }
static VALUE cpu_count(VALUE self) { (void)self; return UINT2NUM(rubyos_x86_smp_cpu_count()); }
static VALUE online_cpus(VALUE self) { (void)self; return UINT2NUM(rubyos_x86_smp_online_count()); }
static VALUE worker_selftests(VALUE self) { (void)self; return UINT2NUM(rubyos_x86_smp_selftests()); }
static VALUE worker_hash(VALUE self, VALUE input, VALUE rounds) { uint64_t result; (void)self; if (!rubyos_x86_smp_hash(NUM2ULL(input),NUM2ULL(rounds),&result)) rb_raise(rb_eRuntimeError,"no native AP worker available"); return ULL2NUM(result); }

void rubyos_x86_64_start(uint64_t magic, uint64_t info) {
    (void)magic; (void)info;
    outb(0x3f9,0); outb(0x3fb,0x80); outb(0x3f8,1); outb(0x3f9,0); outb(0x3fb,3); outb(0x3fa,0xc7); outb(0x3fc,0x0b);
    puts1("[RubyOS/x86_64] boot: entering CRuby 4.0.6\n");
    if (!rubyos_tls_init()) { puts1("[RubyOS/x86_64] FATAL: TLS\n"); halt(); }
    rubyos_interrupts_init();
    uint64_t page_table;
    __asm__ volatile("mov %%cr3,%0" : "=r"(page_table));
    rubyos_x86_smp_init(page_table);
    while (rubyos_x86_timer_ticks() < 3) __asm__ volatile("hlt");
    puts1("[RubyOS/x86_64] boot: IDT/PIT timer IRQs active\n");
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
    rb_define_module_function(hal,"dma_free",dma_free,1);
    rb_define_module_function(hal,"dma_write",dma_write,2);
    rb_define_module_function(hal,"heap_total_bytes",heap_total_bytes,0);
    rb_define_module_function(hal,"heap_free_bytes",heap_free_bytes,0);
    rb_define_module_function(hal,"ps2_scancode",ps2_scancode,0);
    rb_define_module_function(hal,"ps2_mouse_init",ps2_mouse_init,0);
    rb_define_module_function(hal,"ps2_mouse_byte",ps2_mouse_byte,0);
    rb_define_module_function(hal,"mmio_read32",mmio_read32,1);
    rb_define_module_function(hal,"mmio_write32",mmio_write32,2);
    rb_define_module_function(hal,"mmio_read16",mmio_read16,1);
    rb_define_module_function(hal,"mmio_write16",mmio_write16,2);
    rb_define_module_function(hal,"mmio_read8",mmio_read8,1);
    rb_define_module_function(hal,"mmio_write8",mmio_write8,2);
    rb_define_module_function(hal,"pci_read32",pci_read32,4);
    rb_define_module_function(hal,"pci_write32",pci_write32,5);
    rb_define_module_function(hal,"cpu_count",cpu_count,0);
    rb_define_module_function(hal,"online_cpus",online_cpus,0);
    rb_define_module_function(hal,"worker_selftests",worker_selftests,0);
    rb_define_module_function(hal,"worker_hash",worker_hash,2);
    rb_eval_string_protect(rubyos_kernel_source,&state);
    if (state) { puts1("[RubyOS/x86_64] FATAL: embedded Ruby raised\n"); message=rb_protect(full_message,rb_errinfo(),&msg_state); if (!msg_state) puts1(StringValueCStr(message)); }
    halt();
}
