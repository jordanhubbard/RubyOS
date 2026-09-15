#include <stddef.h>
#include <stdint.h>

#define MAX_CPUS 8
#define STACK_SIZE (64U * 1024U)
#define APIC_BASE 0xfee00000UL
#define APIC_ID 0x020
#define APIC_SVR 0x0f0
#define APIC_ICR_LOW 0x300
#define APIC_ICR_HIGH 0x310

typedef uint64_t (*worker_fn_t)(void *);
typedef struct {
    volatile uint32_t online, sequence, completed;
    worker_fn_t function;
    void *argument;
    volatile uint64_t result;
    uint64_t tcb[4] __attribute__((aligned(16)));
    uint8_t stack[STACK_SIZE] __attribute__((aligned(16)));
} cpu_t;

static cpu_t cpus[MAX_CPUS];
static uint32_t cpu_count = 1;
static volatile uint32_t online_count = 1;
static volatile uint32_t selftests = 1;
extern const uint8_t _binary_ap_trampoline_bin_start[];
extern const uint8_t _binary_ap_trampoline_bin_end[];

static uint32_t apic_read(uint32_t offset) { return *(volatile uint32_t *)(APIC_BASE + offset); }
static void apic_write(uint32_t offset, uint32_t value) { *(volatile uint32_t *)(APIC_BASE + offset) = value; (void)apic_read(APIC_ID); }
static void delay(void) { for (volatile uint32_t index = 0; index < 100000; ++index) __asm__ volatile("pause"); }
static void wait_delivery(void) { while (apic_read(APIC_ICR_LOW) & (1U << 12)) __asm__ volatile("pause"); }
static void ipi(uint8_t id, uint32_t command) { apic_write(APIC_ICR_HIGH, (uint32_t)id << 24); apic_write(APIC_ICR_LOW, command); wait_delivery(); }

void rubyos_x86_ap_main(uint64_t index)
{
    cpu_t *cpu = &cpus[index];
    uint64_t cr0, cr4;
    __asm__ volatile("mov %%cr0,%0" : "=r"(cr0));
    cr0 &= ~(1ULL << 2); cr0 |= 2;
    __asm__ volatile("mov %0,%%cr0" : : "r"(cr0));
    __asm__ volatile("mov %%cr4,%0" : "=r"(cr4));
    cr4 |= 3ULL << 9;
    __asm__ volatile("mov %0,%%cr4" : : "r"(cr4));
    __asm__ volatile("finit");
    cpu->tcb[0] = (uint64_t)(uintptr_t)&cpu->tcb[0];
    cpu->online = 1;
    __sync_add_and_fetch(&online_count, 1);
    for (;;) {
        uint32_t sequence = cpu->sequence;
        if (sequence != cpu->completed) {
            worker_fn_t function = cpu->function;
            cpu->result = function ? function(cpu->argument) : 0;
            __sync_synchronize();
            cpu->completed = sequence;
        } else {
            __asm__ volatile("pause");
        }
    }
}

static int submit_to(uint32_t index, worker_fn_t function, void *argument, uint64_t *handle)
{
    cpu_t *cpu = &cpus[index];
    if (!cpu->online || cpu->sequence != cpu->completed) return 0;
    uint32_t sequence = cpu->sequence + 1;
    if (!sequence) sequence = 1;
    cpu->function = function;
    cpu->argument = argument;
    __sync_synchronize();
    cpu->sequence = sequence;
    *handle = ((uint64_t)index << 32) | sequence;
    return 1;
}

static int join(uint64_t handle, uint64_t *result)
{
    uint32_t index = (uint32_t)(handle >> 32), sequence = (uint32_t)handle;
    if (!index || index >= cpu_count || !sequence) return 0;
    while (cpus[index].completed != sequence) __asm__ volatile("pause");
    if (result) *result = cpus[index].result;
    return 1;
}

static uint64_t selftest_job(void *argument)
{
    return __sync_add_and_fetch((volatile uint64_t *)argument, 1);
}

void rubyos_x86_smp_init(uint64_t pml4)
{
    uint32_t low, high;
    __asm__ volatile("rdmsr" : "=a"(low), "=d"(high) : "c"(0x1b));
    uint64_t value = ((uint64_t)high << 32) | low | (1ULL << 11);
    __asm__ volatile("wrmsr" : : "a"((uint32_t)value), "d"((uint32_t)(value >> 32)), "c"(0x1b));
    apic_write(APIC_SVR, apic_read(APIC_SVR) | 0x1ff);

    size_t length = (size_t)(_binary_ap_trampoline_bin_end - _binary_ap_trampoline_bin_start);
    for (size_t index = 0; index < length; ++index)
        ((volatile uint8_t *)0x8000)[index] = _binary_ap_trampoline_bin_start[index];
    *(volatile uint64_t *)0x8ff0 = pml4;
    uint8_t bsp = (uint8_t)(apic_read(APIC_ID) >> 24);
    for (uint32_t index = 1; index < MAX_CPUS; ++index) {
        uint8_t apic_id = (uint8_t)(bsp + index);
        *(volatile uint64_t *)0x8fe0 = (uint64_t)(uintptr_t)&cpus[index].stack[STACK_SIZE];
        *(volatile uint64_t *)0x8fd8 = index;
        *(volatile uint64_t *)0x8fd0 = (uint64_t)(uintptr_t)rubyos_x86_ap_main;
        __sync_synchronize();
        ipi(apic_id, (5U << 8) | (1U << 14) | (1U << 15));
        delay();
        ipi(apic_id, (6U << 8) | 8U);
        delay();
        ipi(apic_id, (6U << 8) | 8U);
        for (uint32_t spin = 0; spin < 5000000U && !cpus[index].online; ++spin)
            __asm__ volatile("pause");
        if (!cpus[index].online) break;
        cpu_count++;
    }
    volatile uint64_t count = 1;
    for (uint32_t index = 1; index < cpu_count; ++index) {
        uint64_t handle;
        if (submit_to(index, selftest_job, (void *)&count, &handle)) join(handle, NULL);
    }
    selftests = (uint32_t)count;
}

uint32_t rubyos_x86_smp_cpu_count(void) { return cpu_count; }
uint32_t rubyos_x86_smp_online_count(void) { return online_count; }
uint32_t rubyos_x86_smp_selftests(void) { return selftests; }

typedef struct { uint64_t value, rounds; } hash_job_t;
static uint64_t hash_job(void *opaque)
{
    hash_job_t *job = opaque;
    uint64_t value = job->value;
    for (uint64_t index = 0; index < job->rounds; ++index)
        value = (value ^ (value >> 12)) * UINT64_C(0x9e3779b97f4a7c15) + index;
    return value;
}

int rubyos_x86_smp_hash(uint64_t value, uint64_t rounds, uint64_t *result)
{
    hash_job_t job = { value, rounds };
    for (uint32_t index = 1; index < cpu_count; ++index) {
        uint64_t handle;
        if (submit_to(index, hash_job, &job, &handle)) return join(handle, result);
    }
    return 0;
}
