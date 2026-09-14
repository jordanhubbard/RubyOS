/*
 * time.c — Time functions backed by the PIT tick counter.
 *
 * The PIT fires at 100 Hz (configured in pit.c). Each tick is 10 ms.
 * _pit_ticks is incremented by the timer interrupt handler via
 * pit_tick() declared here and called from kernel.scheduler.tick().
 */

#include "include/libc.h"
#include <stdint.h>

// Written by pit_tick(); read by time functions
volatile uint64_t _pit_ticks = 0;
#define TICK_HZ 100

#ifndef ARCH_ARM64
void pit_tick(void) { _pit_ticks++; }
#endif

// ── time_t / gettimeofday ─────────────────────────────────────────────────────

// We don't have a real-time clock yet — report time-since-boot
time_t time(time_t *t) {
    time_t sec = (time_t)(_pit_ticks / TICK_HZ);
    if (t) *t = sec;
    return sec;
}

int gettimeofday(struct timeval *tv, void *tz) {
    (void)tz;
    if (tv) {
        tv->tv_sec  = (time_t)(_pit_ticks / TICK_HZ);
        tv->tv_usec = (suseconds_t)((_pit_ticks % TICK_HZ) * (1000000 / TICK_HZ));
    }
    return 0;
}

int clock_gettime(clockid_t id, struct timespec *ts) {
    (void)id;
    if (ts) {
        ts->tv_sec  = (time_t)(_pit_ticks / TICK_HZ);
        ts->tv_nsec = (long)((_pit_ticks % TICK_HZ) * (1000000000LL / TICK_HZ));
    }
    return 0;
}

clock_t clock(void) {
    return (clock_t)_pit_ticks;
}

int clock_getres(clockid_t id, struct timespec *ts) {
    (void)id;
    if (ts) { ts->tv_sec = 0; ts->tv_nsec = 1000000000LL / TICK_HZ; }
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
