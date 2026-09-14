#pragma once

typedef struct {
    volatile int locked;
} spinlock_t;

#define SPINLOCK_INITIALIZER {0}

static inline void spin_pause(void) {
#ifdef ARCH_ARM64
    __asm__ volatile("yield");
#else
    __asm__ volatile("pause");
#endif
}

static inline void spin_lock(spinlock_t *lock) {
    while (__sync_lock_test_and_set(&lock->locked, 1)) {
        while (lock->locked) {
            spin_pause();
        }
    }
    __sync_synchronize();
}

static inline int spin_trylock(spinlock_t *lock) {
    if (__sync_lock_test_and_set(&lock->locked, 1)) {
        return 0;
    }
    __sync_synchronize();
    return 1;
}

static inline void spin_unlock(spinlock_t *lock) {
    __sync_synchronize();
    __sync_lock_release(&lock->locked);
}
