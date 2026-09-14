/* time.h — bare-metal time stubs for PythonOS. */
#pragma once
#include <stddef.h>
#include <stdint.h>

typedef long          time_t;
typedef long          suseconds_t;
typedef long long     clock_t;

#ifndef __clockid_t_defined
typedef int           clockid_t;   /* must match int (not long long) for pymacro.h Py_BUILD_ASSERT */
#define __clockid_t_defined 1
#endif

#ifndef __timeval_defined
# define __timeval_defined 1
struct timeval  { time_t tv_sec; suseconds_t tv_usec; };
#endif
/* Set glibc guard so system bits/types/struct_timespec.h is skipped */
#ifndef _STRUCT_TIMESPEC
#define _STRUCT_TIMESPEC 1
struct timespec { time_t tv_sec; long tv_nsec; };
#endif

#define CLOCK_REALTIME  0
#define CLOCK_MONOTONIC 1

#define CLOCKS_PER_SEC 1000000

struct tm {
    int tm_sec;   int tm_min;   int tm_hour;
    int tm_mday;  int tm_mon;   int tm_year;
    int tm_wday;  int tm_yday;  int tm_isdst;
};

int     gettimeofday(struct timeval *tv, void *tz);
int     clock_gettime(clockid_t id, struct timespec *ts);
int     clock_getres(clockid_t id, struct timespec *ts);
clock_t clock(void);
time_t  time(time_t *t);
int     nanosleep(const struct timespec *req, struct timespec *rem);
struct tm *gmtime_r(const time_t *t, struct tm *tm);
struct tm *localtime_r(const time_t *t, struct tm *tm);
struct tm *gmtime(const time_t *t);
struct tm *localtime(const time_t *t);
time_t     mktime(struct tm *tm);
char      *asctime(const struct tm *tm);
char      *ctime(const time_t *t);
size_t     strftime(char *s, size_t max, const char *fmt, const struct tm *tm);
void       tzset(void);
