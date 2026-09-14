#include <stdint.h>

#define GICD_BASE 0x08000000UL
#define GICC_BASE 0x08010000UL
#define GICR_BASE 0x080a0000UL
#define GICR_SGI_OFFSET 0x10000UL
#define TIMER_IRQ 30U
#define TIMER_HZ 100U

static int gic_version;
static uint64_t timer_interval;
static volatile uint64_t timer_ticks;

static uint32_t r32(uint64_t a) { return *(volatile uint32_t *)a; }
static void w32(uint64_t a, uint32_t v) { *(volatile uint32_t *)a = v; }
static void w64(uint64_t a, uint64_t v) { *(volatile uint64_t *)a = v; }

static uint64_t redistributor(void) {
    uint64_t mpidr;
    __asm__ volatile("mrs %0, mpidr_el1" : "=r"(mpidr));
    uint64_t index = (mpidr & 0xff) + (((mpidr >> 8) & 0xff) << 4) +
                     (((mpidr >> 16) & 0xff) << 8) + (((mpidr >> 32) & 0xff) << 12);
    return GICR_BASE + index * 0x20000UL;
}

static void init_v2(void) {
    w32(GICD_BASE, 0);
    uint32_t lines = 32U * ((r32(GICD_BASE + 4) & 0x1fU) + 1U);
    for (uint32_t i = 1; i < lines / 32; ++i) w32(GICD_BASE + 0x180 + i * 4, 0xffffffffU);
    for (uint32_t i = 0; i < lines / 4; ++i) w32(GICD_BASE + 0x400 + i * 4, 0xa0a0a0a0U);
    for (uint32_t i = 8; i < lines / 4; ++i) w32(GICD_BASE + 0x800 + i * 4, 0x01010101U);
    w32(GICD_BASE, 1);
    w32(GICC_BASE + 4, 0xff);
    w32(GICC_BASE + 8, 7);
    w32(GICC_BASE, 1);
    w32(GICD_BASE + 0x100, 1U << TIMER_IRQ);
}

static void init_v3(void) {
    uint64_t rd = redistributor(), sgi = rd + GICR_SGI_OFFSET;
    uint32_t waker = r32(rd + 0x14) & ~(1U << 1);
    w32(rd + 0x14, waker);
    while (r32(rd + 0x14) & (1U << 2)) {}
    w32(sgi + 0x080, 0xffffffffU);
    w32(sgi + 0x180, 0xffffffffU);
    for (int i = 0; i < 8; ++i) w32(sgi + 0x400 + (uint64_t)i * 4, 0xa0a0a0a0U);
    w32(GICD_BASE, (1U << 4) | (1U << 5));
    uint32_t lines = 32U * ((r32(GICD_BASE + 4) & 0x1fU) + 1U);
    for (uint32_t i = 1; i < lines / 32; ++i) w32(GICD_BASE + 0x180 + i * 4, 0xffffffffU);
    for (uint32_t i = 32; i < lines; ++i) w64(GICD_BASE + 0x6000 + (uint64_t)i * 8, 0);
    w32(GICD_BASE, (1U << 4) | (1U << 5) | (1U << 1));
    uint64_t sre;
    __asm__ volatile("mrs %0, S3_0_C12_C12_5" : "=r"(sre));
    sre |= 1;
    __asm__ volatile("msr S3_0_C12_C12_5, %0; isb" : : "r"(sre));
    __asm__ volatile("msr S3_0_C4_C6_0, %0" : : "r"((uint64_t)0xff));
    __asm__ volatile("msr S3_0_C12_C12_7, %0; isb" : : "r"((uint64_t)1));
    w32(sgi + 0x100, 1U << TIMER_IRQ);
}

void rubyos_timer_init(void) {
    int v2 = (int)((r32(GICD_BASE + 0x0fe8) >> 4) & 0xf);
    gic_version = v2 == 2 ? 2 : (int)((r32(GICD_BASE + 0xffe8) >> 4) & 0xf);
    if (gic_version >= 3) init_v3(); else { gic_version = 2; init_v2(); }
    uint64_t frequency;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(frequency));
    timer_interval = frequency / TIMER_HZ;
    __asm__ volatile("msr cntp_tval_el0, %0" : : "r"(timer_interval));
    __asm__ volatile("msr cntp_ctl_el0, %0; isb" : : "r"((uint64_t)1));
}

void rubyos_irq_handler(void) {
    uint32_t id;
    if (gic_version >= 3) {
        uint64_t value;
        __asm__ volatile("mrs %0, S3_0_C12_C12_0" : "=r"(value));
        id = (uint32_t)value & 0xffffffU;
    } else id = r32(GICC_BASE + 0x0c);
    if (id == TIMER_IRQ) {
        ++timer_ticks;
        __asm__ volatile("msr cntp_tval_el0, %0" : : "r"(timer_interval));
    }
    if (id < 1020) {
        if (gic_version >= 3) __asm__ volatile("msr S3_0_C12_C12_1, %0; isb" : : "r"((uint64_t)id));
        else w32(GICC_BASE + 0x10, id);
    }
}

uint64_t rubyos_timer_ticks(void) { return timer_ticks; }
