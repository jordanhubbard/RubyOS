/* sys/syscall.h — bare-metal stub for PythonOS.
 * CPython's thread_pthread.h uses syscall(SYS_gettid) on Linux targets.
 * syscalls.c returns the current native CPU/thread ID for SYS_gettid.
 */
#pragma once
#include <stdarg.h>

#define SYS_gettid 186

long syscall(long number, ...);
