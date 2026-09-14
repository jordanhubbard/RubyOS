/* pthread.h — minimal POSIX thread substrate for PythonOS bare-metal.
 *
 * Mutexes/condvars/TLS are SMP-aware. On x86_64, pthread_create() dispatches
 * joinable or detached workers onto initialized APs.
 */
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <time.h>

/* ── Types ──────────────────────────────────────────────────────────────── */

/* Set glibc file guard so bits/pthreadtypes.h is skipped when system
 * signal.h or other headers transitively include it; this prevents
 * redefinition conflicts with PythonOS pthread types below. */
#define _BITS_PTHREADTYPES_COMMON_H 1

typedef unsigned long  pthread_t;
typedef int            pthread_once_t;
typedef unsigned       pthread_key_t;
/* Define __have_pthread_attr_t so bits/types/sigevent_t.h skips its
 * definition of 'union pthread_attr_t' which conflicts with our struct. */
#ifndef __have_pthread_attr_t
typedef struct {
    int detachstate;
    size_t stacksize;
} pthread_attr_t;
#define __have_pthread_attr_t 1
#endif
typedef struct { int locked; }   pthread_mutex_t;
typedef struct { int dummy; }    pthread_mutexattr_t;
typedef struct { int seq; }      pthread_cond_t;
typedef struct { int dummy; }    pthread_condattr_t;
typedef struct { int dummy; }    pthread_rwlock_t;
typedef struct { int dummy; }    pthread_rwlockattr_t;

/* ── Constants ──────────────────────────────────────────────────────────── */

#define PTHREAD_MUTEX_INITIALIZER   {0}
#define PTHREAD_COND_INITIALIZER    {0}
#define PTHREAD_ONCE_INIT           0
#define PTHREAD_KEYS_MAX            128

#define PTHREAD_CREATE_JOINABLE     0
#define PTHREAD_CREATE_DETACHED     1

#define PTHREAD_CANCEL_ENABLE       0
#define PTHREAD_CANCEL_DISABLE      1
#define PTHREAD_CANCEL_DEFERRED     0
#define PTHREAD_CANCEL_ASYNCHRONOUS 1

#define PTHREAD_MUTEX_DEFAULT       0
#define PTHREAD_MUTEX_NORMAL        0
#define PTHREAD_MUTEX_ERRORCHECK    1
#define PTHREAD_MUTEX_RECURSIVE     2

/* ── Function declarations ──────────────────────────────────────────────── */

int       pthread_key_create(pthread_key_t *key, void (*dtor)(void *));
int       pthread_key_delete(pthread_key_t key);
void     *pthread_getspecific(pthread_key_t key);
int       pthread_setspecific(pthread_key_t key, const void *val);

pthread_t pthread_self(void);
int       pthread_equal(pthread_t a, pthread_t b);
int       pthread_create(pthread_t *, const pthread_attr_t *,
                         void *(*)(void *), void *);
int       pthread_join(pthread_t, void **);
int       pthread_detach(pthread_t);

int       pthread_attr_init(pthread_attr_t *);
int       pthread_attr_destroy(pthread_attr_t *);
int       pthread_attr_setstacksize(pthread_attr_t *, size_t);
int       pthread_attr_getstacksize(pthread_attr_t *, size_t *);
int       pthread_attr_setdetachstate(pthread_attr_t *, int);

int       pthread_mutex_init(pthread_mutex_t *, const pthread_mutexattr_t *);
int       pthread_mutex_destroy(pthread_mutex_t *);
int       pthread_mutex_lock(pthread_mutex_t *);
int       pthread_mutex_trylock(pthread_mutex_t *);
int       pthread_mutex_unlock(pthread_mutex_t *);
int       pthread_mutexattr_init(pthread_mutexattr_t *);
int       pthread_mutexattr_destroy(pthread_mutexattr_t *);
int       pthread_mutexattr_settype(pthread_mutexattr_t *, int);

int       pthread_cond_init(pthread_cond_t *, const pthread_condattr_t *);
int       pthread_cond_destroy(pthread_cond_t *);
int       pthread_cond_signal(pthread_cond_t *);
int       pthread_cond_broadcast(pthread_cond_t *);
int       pthread_cond_wait(pthread_cond_t *, pthread_mutex_t *);
int       pthread_cond_timedwait(pthread_cond_t *, pthread_mutex_t *,
                                  const struct timespec *);
int       pthread_condattr_init(pthread_condattr_t *);
int       pthread_condattr_destroy(pthread_condattr_t *);
int       pthread_condattr_setclock(pthread_condattr_t *, clockid_t);

int       pthread_rwlock_init(pthread_rwlock_t *, const pthread_rwlockattr_t *);
int       pthread_rwlock_destroy(pthread_rwlock_t *);
int       pthread_rwlock_rdlock(pthread_rwlock_t *);
int       pthread_rwlock_wrlock(pthread_rwlock_t *);
int       pthread_rwlock_tryrdlock(pthread_rwlock_t *);
int       pthread_rwlock_trywrlock(pthread_rwlock_t *);
int       pthread_rwlock_unlock(pthread_rwlock_t *);

int       pthread_once(pthread_once_t *, void (*)(void));
int       pthread_setcancelstate(int, int *);
int       pthread_setcanceltype(int, int *);
int       pthread_cancel(pthread_t);
void      pthread_testcancel(void);
void      pthread_exit(void *retval) __attribute__((noreturn));
