/* Monotonic time from the ARM generic counter or the legacy PIT ticks. */

#include "include/libc.h"
#include <stdint.h>

// Written by pit_tick(); read by time functions
volatile uint64_t _pit_ticks = 0;
#define TICK_HZ 100

#ifndef ARCH_ARM64
void pit_tick(void) { _pit_ticks++; }
#endif

#ifdef ARCH_ARM64
static uint64_t counter_ticks(void) {
    uint64_t value;
    __asm__ volatile("isb; mrs %0, cntpct_el0" : "=r"(value));
    return value;
}

static uint64_t counter_frequency(void) {
    uint64_t value;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(value));
    return value;
}
#endif

uint64_t rubyos_monotonic_ns(void) {
#ifdef ARCH_ARM64
    uint64_t ticks = counter_ticks();
    uint64_t frequency = counter_frequency();
    return ticks / frequency * 1000000000ULL +
           ticks % frequency * 1000000000ULL / frequency;
#else
    return _pit_ticks * (1000000000ULL / TICK_HZ);
#endif
}

void rubyos_sleep_ns(uint64_t nanoseconds) {
#ifdef ARCH_ARM64
    uint64_t frequency = counter_frequency();
    uint64_t delay = nanoseconds / 1000000000ULL * frequency;
    uint64_t remainder = nanoseconds % 1000000000ULL;
    uint64_t deadline;
    delay += (remainder * frequency + 999999999ULL) / 1000000000ULL;
    deadline = counter_ticks() + delay;
    while ((int64_t)(deadline - counter_ticks()) > 0)
        __asm__ volatile("yield");
#else
    uint64_t deadline = rubyos_monotonic_ns() + nanoseconds;
    while ((int64_t)(deadline - rubyos_monotonic_ns()) > 0)
        __asm__ volatile("pause");
#endif
}

// ── time_t / gettimeofday ─────────────────────────────────────────────────────

// We don't have a real-time clock yet — report time-since-boot
time_t time(time_t *t) {
    time_t sec = (time_t)(rubyos_monotonic_ns() / 1000000000ULL);
    if (t) *t = sec;
    return sec;
}

int gettimeofday(struct timeval *tv, void *tz) {
    (void)tz;
    if (tv) {
        uint64_t now = rubyos_monotonic_ns();
        tv->tv_sec  = (time_t)(now / 1000000000ULL);
        tv->tv_usec = (suseconds_t)((now % 1000000000ULL) / 1000ULL);
    }
    return 0;
}

int clock_gettime(clockid_t id, struct timespec *ts) {
    (void)id;
    if (ts) {
        uint64_t now = rubyos_monotonic_ns();
        ts->tv_sec  = (time_t)(now / 1000000000ULL);
        ts->tv_nsec = (long)(now % 1000000000ULL);
    }
    return 0;
}

clock_t clock(void) {
    return (clock_t)(rubyos_monotonic_ns() / 1000ULL);
}

int clock_getres(clockid_t id, struct timespec *ts) {
    (void)id;
    if (ts) {
        ts->tv_sec = 0;
#ifdef ARCH_ARM64
        ts->tv_nsec = (long)((1000000000ULL + counter_frequency() - 1) /
                             counter_frequency());
#else
        ts->tv_nsec = 1000000000LL / TICK_HZ;
#endif
    }
    return 0;
}

static struct tm _gmtime_buf;

struct tm *gmtime_r(const time_t *tp, struct tm *tm) {
    time_t t = *tp;
    tm->tm_sec  = (int)(t % 60); t /= 60;
    tm->tm_min  = (int)(t % 60); t /= 60;
    tm->tm_hour = (int)(t % 24); t /= 24;
    tm->tm_wday = (int)((t + 4) % 7);
    tm->tm_year = 70;
    while (1) {
        int y4 = tm->tm_year + 1900;
        int dy = 365 + (y4 % 4 == 0 && (y4 % 100 != 0 || y4 % 400 == 0) ? 1 : 0);
        if (t < (time_t)dy) break;
        t -= dy; tm->tm_year++;
    }
    tm->tm_yday = (int)t;
    static const int mdays[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
    tm->tm_mon = 0; tm->tm_mday = 1;
    for (int m = 0; m < 12; m++) {
        int y4 = tm->tm_year + 1900;
        int md = mdays[m] + (m == 1 && y4 % 4 == 0 ? 1 : 0);
        if (t < (time_t)md) { tm->tm_mon = m; tm->tm_mday = (int)t + 1; break; }
        t -= md;
    }
    tm->tm_isdst = 0;
    return tm;
}

struct tm *gmtime(const time_t *t)                { return gmtime_r(t, &_gmtime_buf); }
struct tm *localtime_r(const time_t *t, struct tm *tm) { return gmtime_r(t, tm); }
struct tm *localtime(const time_t *t)              { return gmtime(t); }

time_t mktime(struct tm *tm) {
    int year = tm->tm_year + 1900;
    time_t days = 0;
    for (int y = 1970; y < year; y++)
        days += 365 + (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) ? 1 : 0);
    static const int mdays[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
    for (int m = 0; m < tm->tm_mon; m++) {
        int md = mdays[m] + (m == 1 && year % 4 == 0 ? 1 : 0);
        days += md;
    }
    days += tm->tm_mday - 1;
    return days * 86400 + tm->tm_hour * 3600 + tm->tm_min * 60 + tm->tm_sec;
}

static char _asctime_buf[32];
char *asctime(const struct tm *tm) {
    static const char *days[] = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
    static const char *mons[] = {"Jan","Feb","Mar","Apr","May","Jun",
                                  "Jul","Aug","Sep","Oct","Nov","Dec"};
    snprintf(_asctime_buf, sizeof(_asctime_buf), "%s %s %2d %02d:%02d:%02d %04d\n",
             days[tm->tm_wday], mons[tm->tm_mon], tm->tm_mday,
             tm->tm_hour, tm->tm_min, tm->tm_sec, tm->tm_year + 1900);
    return _asctime_buf;
}

char *ctime(const time_t *t) { return asctime(localtime(t)); }

size_t strftime(char *s, size_t max, const char *fmt, const struct tm *tm) {
    (void)fmt; (void)tm;
    if (max > 0) s[0] = '\0';
    return 0;
}

void tzset(void) { /* no timezone in bare metal */ }
