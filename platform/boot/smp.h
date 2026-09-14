#ifndef PYTHONOS_BOOT_SMP_H
#define PYTHONOS_BOOT_SMP_H

#include <stdint.h>

typedef uint64_t (*smp_worker_fn_t)(void *cpu, void *arg);

void smp_init(void *mb2_info);
void smp_bsp_early_init(void);
uint32_t smp_cpu_count(void);
uint32_t smp_online_count(void);
uint32_t smp_worker_selftest_count(void);
uint8_t smp_bsp_apic_id(void);
void smp_lapic_eoi(void);

int smp_submit_worker(smp_worker_fn_t fn, void *arg, uint64_t *handle);
int smp_worker_done(uint64_t handle);
uint64_t smp_worker_result(uint64_t handle);
int smp_join_worker(uint64_t handle, uint64_t *result);

#endif
