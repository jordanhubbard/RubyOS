/*
 * sys/times.h — bare-metal stub for PythonOS.
 * Provides struct tms and times() so posixmodule.c compiles; always returns errors.
 */
#pragma once
#include <time.h>

struct tms {
    clock_t tms_utime;
    clock_t tms_stime;
    clock_t tms_cutime;
    clock_t tms_cstime;
};

clock_t times(struct tms *buf);
