/*
 * utime.h — bare-metal stub for PythonOS.
 * Provides struct utimbuf and utime() so posixmodule.c compiles.
 */
#pragma once
#include <time.h>

struct utimbuf {
    time_t actime;
    time_t modtime;
};

int utime(const char *path, const struct utimbuf *times);
