#include <stddef.h>
#include <stdint.h>
extern uint8_t __tls_start[], __tdata_start[], __tdata_end[], __tls_end[];
static uint8_t tls_area[65536] __attribute__((aligned(16)));
static void wrmsr(uint32_t msr, uint64_t value) {
    __asm__ volatile("wrmsr" : : "c"(msr), "a"((uint32_t)value), "d"((uint32_t)(value >> 32)) : "memory");
}
int rubyos_tls_init(void) {
    size_t data_size = (size_t)(__tdata_end - __tdata_start);
    size_t tls_size = (size_t)(__tls_end - __tls_start);
    if (tls_size + 8 > sizeof tls_area || data_size > tls_size) return 0;
    for (size_t i = 0; i < data_size; ++i) tls_area[i] = __tdata_start[i];
    uintptr_t base = (uintptr_t)tls_area + tls_size;
    *(uintptr_t *)base = base;
    wrmsr(0xc0000100U, base);
    return 1;
}
