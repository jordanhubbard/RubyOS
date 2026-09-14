/*
 * pthread.c — Minimal SMP-aware pthread substrate for PythonOS.
 *
 * AP-backed pthread_create() is sufficient for CPython _thread workers in the
 * no-GIL smoke path. The substrate is intentionally small: mutexes are atomic,
 * condition variables have sequence semantics, and pthread TLS is partitioned
 * by native CPU/thread id.
 */

#include "include/libc.h"
#include "include/spinlock.h"
#include <stdint.h>
#include "../boot/smp.h"

#define MAX_KEYS 64
#define MAX_THREAD_SLOTS 16
#define MAX_PTHREADS 16
#define PTHREAD_T_BASE 0x1000UL
#define TIMEDWAIT_MIN_FALLBACK_SPINS 2000000ULL
#define TIMEDWAIT_MAX_FALLBACK_SPINS 12000000ULL
#define TIMEDWAIT_NS_PER_FALLBACK_SPIN 100ULL

typedef struct {
    int in_use;
    int detached;
    volatile int done;
    pthread_t tid;
    uint64_t worker_handle;
    void *(*fn)(void *);
    void *arg;
    void *retval;
} pthread_record_t;

static struct {
    int in_use;
    void (*destructor)(void *);
} tsd_keys[MAX_KEYS];

static void *tsd_values[MAX_THREAD_SLOTS][MAX_KEYS];
static pthread_t tsd_thread_ids[MAX_THREAD_SLOTS];
static spinlock_t tsd_lock = SPINLOCK_INITIALIZER;
static pthread_record_t pthread_records[MAX_PTHREADS];
static pthread_t active_tid_by_native_slot[MAX_THREAD_SLOTS];
static spinlock_t pthread_records_lock = SPINLOCK_INITIALIZER;

static pthread_t native_thread_id(void) {
#ifdef ARCH_ARM64
    /* MPIDR_EL1 holds the affinity register identifying the running core.
     * Aff0 (bits 0..7) is the core index within a cluster; we add 1 so
     * the value is nonzero (matches the x86 cpuid arm). With single-core
     * arm64 boot today this returns 1; once secondary cores are brought
     * up (beads pythonos-bjr.1), each AP returns its own distinct id. */
    uint64_t mpidr;
    __asm__ volatile("mrs %0, MPIDR_EL1" : "=r"(mpidr));
    return (pthread_t)((mpidr & 0xffU) + 1);
#else
    uint32_t eax, ebx, ecx, edx;
    __asm__ volatile("cpuid"
                     : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
                     : "a"(1), "c"(0));
    return ((pthread_t)((ebx >> 24) & 0xffU)) + 1;
#endif
}

static unsigned native_slot(void) {
    return (unsigned)(native_thread_id() % MAX_THREAD_SLOTS);
}

static unsigned tsd_slot_for(pthread_t tid) {
    spin_lock(&tsd_lock);

    unsigned free_slot = MAX_THREAD_SLOTS;
    for (unsigned i = 0; i < MAX_THREAD_SLOTS; i++) {
        if (tsd_thread_ids[i] == tid) {
            spin_unlock(&tsd_lock);
            return i;
        }
        if (tsd_thread_ids[i] == 0 && free_slot == MAX_THREAD_SLOTS) {
            free_slot = i;
        }
    }

    if (free_slot < MAX_THREAD_SLOTS) {
        tsd_thread_ids[free_slot] = tid;
        for (unsigned k = 0; k < MAX_KEYS; k++) {
            tsd_values[free_slot][k] = NULL;
        }
        spin_unlock(&tsd_lock);
        return free_slot;
    }

    spin_unlock(&tsd_lock);
    return 0;
}

static void tsd_run_destructors(pthread_t tid) {
    unsigned slot = tsd_slot_for(tid);

    for (unsigned pass = 0; pass < 4; pass++) {
        int ran_destructor = 0;
        for (unsigned k = 0; k < MAX_KEYS; k++) {
            void *value = NULL;
            void (*destructor)(void *) = NULL;

            spin_lock(&tsd_lock);
            if (tsd_keys[k].in_use && tsd_values[slot][k]) {
                value = tsd_values[slot][k];
                destructor = tsd_keys[k].destructor;
                tsd_values[slot][k] = NULL;
            }
            spin_unlock(&tsd_lock);

            if (value && destructor) {
                ran_destructor = 1;
                destructor(value);
            }
        }

        if (!ran_destructor) {
            break;
        }
    }

    spin_lock(&tsd_lock);
    if (tsd_thread_ids[slot] == tid) {
        tsd_thread_ids[slot] = 0;
        for (unsigned k = 0; k < MAX_KEYS; k++) {
            tsd_values[slot][k] = NULL;
        }
    }
    spin_unlock(&tsd_lock);
}

int pthread_key_create(pthread_key_t *key, void (*destructor)(void *)) {
    spin_lock(&tsd_lock);
    for (unsigned k = 0; k < MAX_KEYS; k++) {
        if (!tsd_keys[k].in_use) {
            tsd_keys[k].in_use = 1;
            tsd_keys[k].destructor = destructor;
            for (unsigned slot = 0; slot < MAX_THREAD_SLOTS; slot++) {
                tsd_values[slot][k] = NULL;
            }
            *key = k;
            spin_unlock(&tsd_lock);
            return 0;
        }
    }
    spin_unlock(&tsd_lock);
    return ENOMEM;
}

int pthread_key_delete(pthread_key_t key) {
    if (key >= MAX_KEYS) {
        return EINVAL;
    }
    spin_lock(&tsd_lock);
    tsd_keys[key].in_use = 0;
    for (unsigned slot = 0; slot < MAX_THREAD_SLOTS; slot++) {
        tsd_values[slot][key] = NULL;
    }
    spin_unlock(&tsd_lock);
    return 0;
}

void *pthread_getspecific(pthread_key_t key) {
    if (key >= MAX_KEYS || !tsd_keys[key].in_use) {
        return NULL;
    }
    unsigned slot = tsd_slot_for(pthread_self());
    return tsd_values[slot][key];
}

int pthread_setspecific(pthread_key_t key, const void *val) {
    if (key >= MAX_KEYS || !tsd_keys[key].in_use) {
        return EINVAL;
    }
    unsigned slot = tsd_slot_for(pthread_self());
    tsd_values[slot][key] = (void *)val;
    return 0;
}

pthread_t pthread_self(void) {
    pthread_t active = active_tid_by_native_slot[native_slot()];
    if (active) {
        return active;
    }
    return native_thread_id();
}

int pthread_equal(pthread_t a, pthread_t b) {
    return a == b;
}

static uint64_t pthread_worker_entry(void *cpu, void *arg) {
    (void)cpu;
    pthread_record_t *record = (pthread_record_t *)arg;
    unsigned slot = native_slot();
    active_tid_by_native_slot[slot] = record->tid;

    void *ret = record->fn(record->arg);

    tsd_run_destructors(record->tid);
    active_tid_by_native_slot[slot] = 0;
    spin_lock(&pthread_records_lock);
    record->retval = ret;
    record->done = 1;
    if (record->detached) {
        record->in_use = 0;
    }
    spin_unlock(&pthread_records_lock);
    return (uint64_t)(uintptr_t)ret;
}

int pthread_create(pthread_t *tid, const pthread_attr_t *attr,
                   void *(*fn)(void *), void *arg) {
    if (!tid || !fn) {
        return EINVAL;
    }
    spin_lock(&pthread_records_lock);
    pthread_record_t *record = NULL;
    int detached = attr && attr->detachstate == PTHREAD_CREATE_DETACHED;
    for (unsigned i = 0; i < MAX_PTHREADS; i++) {
        if (!pthread_records[i].in_use) {
            record = &pthread_records[i];
            record->in_use = 1;
            record->detached = detached;
            record->done = 0;
            record->tid = PTHREAD_T_BASE + i;
            record->worker_handle = 0;
            record->fn = fn;
            record->arg = arg;
            record->retval = NULL;
            break;
        }
    }
    spin_unlock(&pthread_records_lock);

    if (!record) {
        return EAGAIN;
    }

    uint64_t handle = 0;
    if (!smp_submit_worker(pthread_worker_entry, record, &handle)) {
        spin_lock(&pthread_records_lock);
        record->in_use = 0;
        spin_unlock(&pthread_records_lock);
        return EAGAIN;
    }

    if (!detached) {
        record->worker_handle = handle;
    }
    *tid = record->tid;
    return 0;
}

int pthread_join(pthread_t tid, void **retval) {
    if (tid < PTHREAD_T_BASE || tid >= PTHREAD_T_BASE + MAX_PTHREADS) {
        return EINVAL;
    }
    pthread_record_t *record = &pthread_records[tid - PTHREAD_T_BASE];
    if (!record->in_use || record->detached) {
        return EINVAL;
    }

    uint64_t result = 0;
    if (!smp_join_worker(record->worker_handle, &result)) {
        return EINVAL;
    }

    if (retval) {
        *retval = (void *)(uintptr_t)result;
    }

    spin_lock(&pthread_records_lock);
    record->in_use = 0;
    spin_unlock(&pthread_records_lock);
    return 0;
}

int pthread_detach(pthread_t tid) {
    if (tid < PTHREAD_T_BASE || tid >= PTHREAD_T_BASE + MAX_PTHREADS) {
        return EINVAL;
    }
    spin_lock(&pthread_records_lock);
    pthread_record_t *record = &pthread_records[tid - PTHREAD_T_BASE];
    if (!record->in_use) {
        spin_unlock(&pthread_records_lock);
        return EINVAL;
    }
    if (record->done) {
        record->in_use = 0;
    } else {
        record->detached = 1;
    }
    spin_unlock(&pthread_records_lock);
    return 0;
}

int pthread_attr_init(pthread_attr_t *a) {
    if (!a) {
        return EINVAL;
    }
    a->detachstate = PTHREAD_CREATE_JOINABLE;
    a->stacksize = 65536;
    return 0;
}

int pthread_attr_destroy(pthread_attr_t *a) {
    (void)a;
    return 0;
}

int pthread_attr_setstacksize(pthread_attr_t *a, size_t s) {
    if (!a || s < 32768) {
        return EINVAL;
    }
    a->stacksize = s;
    return 0;
}

int pthread_attr_getstacksize(pthread_attr_t *a, size_t *s) {
    if (!a || !s) {
        return EINVAL;
    }
    *s = a->stacksize ? a->stacksize : 65536;
    return 0;
}

int pthread_attr_setdetachstate(pthread_attr_t *a, int s) {
    if (!a || (s != PTHREAD_CREATE_JOINABLE && s != PTHREAD_CREATE_DETACHED)) {
        return EINVAL;
    }
    a->detachstate = s;
    return 0;
}

int pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *a) {
    (void)a;
    m->locked = 0;
    return 0;
}

int pthread_mutex_destroy(pthread_mutex_t *m) {
    (void)m;
    return 0;
}

int pthread_mutex_lock(pthread_mutex_t *m) {
    while (__sync_lock_test_and_set(&m->locked, 1)) {
        while (m->locked) {
            spin_pause();
        }
    }
    __sync_synchronize();
    return 0;
}

int pthread_mutex_trylock(pthread_mutex_t *m) {
    if (__sync_lock_test_and_set(&m->locked, 1)) {
        return EBUSY;
    }
    __sync_synchronize();
    return 0;
}

int pthread_mutex_unlock(pthread_mutex_t *m) {
    __sync_synchronize();
    __sync_lock_release(&m->locked);
    return 0;
}

int pthread_mutexattr_init(pthread_mutexattr_t *a) {
    (void)a;
    return 0;
}

int pthread_mutexattr_destroy(pthread_mutexattr_t *a) {
    (void)a;
    return 0;
}

int pthread_mutexattr_settype(pthread_mutexattr_t *a, int t) {
    (void)a;
    (void)t;
    return 0;
}

int pthread_cond_init(pthread_cond_t *c, const pthread_condattr_t *a) {
    (void)a;
    c->seq = 0;
    return 0;
}

int pthread_cond_destroy(pthread_cond_t *c) {
    (void)c;
    return 0;
}

int pthread_cond_signal(pthread_cond_t *c) {
    __sync_add_and_fetch(&c->seq, 1);
    return 0;
}

int pthread_cond_broadcast(pthread_cond_t *c) {
    __sync_add_and_fetch(&c->seq, 1);
    return 0;
}

static int pthread_cond_seq(pthread_cond_t *c) {
    return __atomic_load_n(&c->seq, __ATOMIC_ACQUIRE);
}

static int pthread_timespec_valid(const struct timespec *t) {
    return t && t->tv_nsec >= 0 && t->tv_nsec < 1000000000L;
}

static int pthread_timespec_reached(const struct timespec *deadline) {
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    if (now.tv_sec > deadline->tv_sec) {
        return 1;
    }
    return now.tv_sec == deadline->tv_sec && now.tv_nsec >= deadline->tv_nsec;
}

static uint64_t pthread_timespec_fallback_spins(const struct timespec *deadline) {
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);

    uint64_t delta_ns = 0;
    if (deadline->tv_sec > now.tv_sec ||
        (deadline->tv_sec == now.tv_sec && deadline->tv_nsec > now.tv_nsec)) {
        uint64_t delta_sec = (uint64_t)(deadline->tv_sec - now.tv_sec);
        if (delta_sec > 1) {
            return TIMEDWAIT_MAX_FALLBACK_SPINS;
        }
        delta_ns = delta_sec * 1000000000ULL;
        if (deadline->tv_nsec >= now.tv_nsec) {
            delta_ns += (uint64_t)(deadline->tv_nsec - now.tv_nsec);
        } else {
            delta_ns -= (uint64_t)(now.tv_nsec - deadline->tv_nsec);
        }
    }

    uint64_t spins = TIMEDWAIT_MIN_FALLBACK_SPINS +
                     delta_ns / TIMEDWAIT_NS_PER_FALLBACK_SPIN;
    if (spins > TIMEDWAIT_MAX_FALLBACK_SPINS) {
        return TIMEDWAIT_MAX_FALLBACK_SPINS;
    }
    return spins;
}

int pthread_cond_wait(pthread_cond_t *c, pthread_mutex_t *m) {
    int seq = pthread_cond_seq(c);
    pthread_mutex_unlock(m);
    while (pthread_cond_seq(c) == seq) {
        spin_pause();
    }
    return pthread_mutex_lock(m);
}

int pthread_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m,
                           const struct timespec *t) {
    if (!pthread_timespec_valid(t)) {
        return EINVAL;
    }

    int seq = pthread_cond_seq(c);
    uint64_t spins = 0;
    uint64_t fallback_spins = pthread_timespec_fallback_spins(t);
    pthread_mutex_unlock(m);
    while (pthread_cond_seq(c) == seq) {
        if (pthread_timespec_reached(t) || ++spins >= fallback_spins) {
            pthread_mutex_lock(m);
            return ETIMEDOUT;
        }
        spin_pause();
    }
    return pthread_mutex_lock(m);
}

int pthread_condattr_init(pthread_condattr_t *a) {
    (void)a;
    return 0;
}

int pthread_condattr_destroy(pthread_condattr_t *a) {
    (void)a;
    return 0;
}

int pthread_condattr_setclock(pthread_condattr_t *a, clockid_t c) {
    (void)a;
    (void)c;
    return 0;
}

int pthread_rwlock_init(pthread_rwlock_t *l, const pthread_rwlockattr_t *a) {
    (void)a;
    l->dummy = 0;
    return 0;
}

int pthread_rwlock_destroy(pthread_rwlock_t *l) {
    (void)l;
    return 0;
}

int pthread_rwlock_rdlock(pthread_rwlock_t *l) {
    while (__sync_lock_test_and_set(&l->dummy, 1)) {
        spin_pause();
    }
    return 0;
}

int pthread_rwlock_wrlock(pthread_rwlock_t *l) {
    return pthread_rwlock_rdlock(l);
}

int pthread_rwlock_tryrdlock(pthread_rwlock_t *l) {
    return __sync_lock_test_and_set(&l->dummy, 1) ? EBUSY : 0;
}

int pthread_rwlock_trywrlock(pthread_rwlock_t *l) {
    return pthread_rwlock_tryrdlock(l);
}

int pthread_rwlock_unlock(pthread_rwlock_t *l) {
    __sync_lock_release(&l->dummy);
    return 0;
}

int pthread_once(pthread_once_t *once, void (*fn)(void)) {
    if (__sync_bool_compare_and_swap(once, 0, 1)) {
        fn();
        __sync_synchronize();
        *once = 2;
        return 0;
    }
    while (*once != 2) {
        spin_pause();
    }
    return 0;
}

int pthread_setcancelstate(int state, int *old) {
    (void)state;
    if (old) {
        *old = 0;
    }
    return 0;
}

int pthread_setcanceltype(int type, int *old) {
    (void)type;
    if (old) {
        *old = 0;
    }
    return 0;
}

int pthread_cancel(pthread_t tid) {
    (void)tid;
    return 0;
}

void pthread_testcancel(void) {
}

void pthread_exit(void *retval) {
    (void)retval;
#ifdef ARCH_ARM64
    for (;;) {
        __asm__ volatile("wfe");
    }
#else
    __asm__ volatile("cli");
    for (;;) {
        __asm__ volatile("hlt");
    }
#endif
}
