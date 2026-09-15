#include <stddef.h>
#include <stdint.h>

#define MAX_CPUS 8
#define AP_STACK_SIZE (64U * 1024U)
#define PSCI_CPU_ON UINT64_C(0xc4000003)

typedef uint64_t (*worker_fn_t)(void *);

typedef struct {
    volatile uint32_t online;
    volatile uint32_t sequence;
    volatile uint32_t completed;
    worker_fn_t function;
    void *argument;
    volatile uint64_t result;
    uint64_t tcb[4] __attribute__((aligned(16)));
    uint8_t stack[AP_STACK_SIZE] __attribute__((aligned(16)));
} cpu_t;

static cpu_t cpus[MAX_CPUS];
static uint32_t cpu_count = 1;
static volatile uint32_t online_count = 1;
static volatile uint32_t selftests = 1;
uint64_t rubyos_ap_stack_top[MAX_CPUS];
extern void rubyos_ap_entry(void);

static int64_t psci(uint64_t function, uint64_t target, uint64_t entry, uint64_t context)
{
    register uint64_t x0 __asm__("x0") = function;
    register uint64_t x1 __asm__("x1") = target;
    register uint64_t x2 __asm__("x2") = entry;
    register uint64_t x3 __asm__("x3") = context;
    __asm__ volatile("hvc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3) : "memory");
    return (int64_t)x0;
}

void rubyos_ap_main(uint32_t index)
{
    cpu_t *cpu = &cpus[index];
    uintptr_t thread_pointer = (uintptr_t)&cpu->tcb[0];
    cpu->tcb[0] = thread_pointer;
    __asm__ volatile("msr tpidr_el0, %0; msr tpidrro_el0, %0; isb" : : "r"(thread_pointer));
    cpu->online = 1;
    __sync_add_and_fetch(&online_count, 1);
    for (;;) {
        uint32_t sequence = cpu->sequence;
        if (sequence != cpu->completed) {
            worker_fn_t function = cpu->function;
            cpu->result = function ? function(cpu->argument) : 0;
            __sync_synchronize();
            cpu->completed = sequence;
            __asm__ volatile("dsb sy; sev");
        } else {
            __asm__ volatile("wfe");
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
    __asm__ volatile("dsb sy; sev");
    *handle = ((uint64_t)index << 32) | sequence;
    return 1;
}

static int join(uint64_t handle, uint64_t *result)
{
    uint32_t index = (uint32_t)(handle >> 32);
    uint32_t sequence = (uint32_t)handle;
    if (index == 0 || index >= cpu_count || !sequence) return 0;
    while (cpus[index].completed != sequence) __asm__ volatile("wfe");
    if (result) *result = cpus[index].result;
    return 1;
}

static uint64_t selftest_job(void *argument)
{
    return __sync_add_and_fetch((volatile uint64_t *)argument, 1);
}

void rubyos_smp_init(void)
{
    uint64_t mpidr;
    __asm__ volatile("mrs %0, mpidr_el1" : "=r"(mpidr));
    uint64_t cluster = mpidr & ((UINT64_C(0xff) << 32) | (UINT64_C(0xff) << 16) | (UINT64_C(0xff) << 8));
    for (uint32_t index = 1; index < MAX_CPUS; ++index) {
        rubyos_ap_stack_top[index] = (uint64_t)(uintptr_t)&cpus[index].stack[AP_STACK_SIZE];
        if (psci(PSCI_CPU_ON, cluster | index, (uint64_t)(uintptr_t)rubyos_ap_entry, index) != 0) break;
        cpu_count++;
        for (uint32_t spin = 0; spin < 50000000U && !cpus[index].online; ++spin)
            __asm__ volatile("yield");
    }
    volatile uint64_t count = 1;
    for (uint32_t index = 1; index < cpu_count; ++index) {
        uint64_t handle = 0;
        if (submit_to(index, selftest_job, (void *)&count, &handle)) join(handle, NULL);
    }
    selftests = (uint32_t)count;
}

uint32_t rubyos_smp_cpu_count(void) { return cpu_count; }
uint32_t rubyos_smp_online_count(void) { return online_count; }
uint32_t rubyos_smp_selftests(void) { return selftests; }

typedef struct { uint64_t value; uint64_t rounds; } hash_job_t;
static uint64_t hash_job(void *opaque)
{
    hash_job_t *job = opaque;
    uint64_t value = job->value;
    for (uint64_t index = 0; index < job->rounds; ++index)
        value = (value ^ (value >> 12)) * UINT64_C(0x9e3779b97f4a7c15) + index;
    return value;
}

int rubyos_smp_hash(uint64_t value, uint64_t rounds, uint64_t *result)
{
    hash_job_t job = { value, rounds };
    for (uint32_t index = 1; index < cpu_count; ++index) {
        uint64_t handle = 0;
        if (submit_to(index, hash_job, &job, &handle)) return join(handle, result);
    }
    return 0;
}
