/*
 * libc.h — PythonOS minimal libc header.
 *
 * Provides just enough C standard library for CPython to compile and run
 * on bare metal. Included by all src/libc C files and included before any
 * CPython headers (pyconfig.h sets _POSIX_C_SOURCE etc. guards, so we
 * need to be careful about conflicts).
 *
 * Rule: declare only what we implement. No errno.h, no stdio.h includes
 * from the host — we define the types and functions here directly.
 */

#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdbool.h>

// ── errno ─────────────────────────────────────────────────────────────────────
extern int errno;
#define ENOENT    2
#define EINTR     4
#define ENOMEM   12
#define EACCES   13
#define EAGAIN   11
#define EBUSY    16
#define EEXIST   17
#define ENOTDIR  20
#define EISDIR   21
#define EINVAL   22
#define ENOSPC   28
#define EPERM    1
#define ENOSYS   38
#define ENOTSUP  95
#define ETIMEDOUT 110
#define EOVERFLOW 75

// ── Memory ────────────────────────────────────────────────────────────────────
void *malloc(size_t size);
void  free(void *ptr);
void *calloc(size_t n, size_t size);
void *realloc(void *ptr, size_t size);
void *aligned_alloc(size_t alignment, size_t size);
size_t malloc_free_bytes(void);

// ── String / memory ───────────────────────────────────────────────────────────
void  *memset(void *dst, int c, size_t n);
void  *memcpy(void *dst, const void *src, size_t n);
void  *memmove(void *dst, const void *src, size_t n);
int    memcmp(const void *a, const void *b, size_t n);
void  *memchr(const void *s, int c, size_t n);

size_t strlen(const char *s);
size_t strnlen(const char *s, size_t maxlen);
int    strcmp(const char *a, const char *b);
int    strncmp(const char *a, const char *b, size_t n);
char  *strcpy(char *dst, const char *src);
char  *strncpy(char *dst, const char *src, size_t n);
char  *strcat(char *dst, const char *src);
char  *strncat(char *dst, const char *src, size_t n);
char  *strchr(const char *s, int c);
char  *strrchr(const char *s, int c);
char  *strstr(const char *hay, const char *needle);
char  *strdup(const char *s);
char  *strndup(const char *s, size_t n);
int    strcasecmp(const char *a, const char *b);
int    strncasecmp(const char *a, const char *b, size_t n);

// ── Character classification ──────────────────────────────────────────────────
int isalpha(int c);
int isdigit(int c);
int isalnum(int c);
int isspace(int c);
int isupper(int c);
int islower(int c);
int isprint(int c);
int ispunct(int c);
int isxdigit(int c);
int iscntrl(int c);
int isblank(int c);
int toupper(int c);
int tolower(int c);

// ── Number conversion ─────────────────────────────────────────────────────────
long           strtol(const char *s, char **end, int base);
unsigned long  strtoul(const char *s, char **end, int base);
long long      strtoll(const char *s, char **end, int base);
unsigned long long strtoull(const char *s, char **end, int base);
double         strtod(const char *s, char **end);
int            atoi(const char *s);
long           atol(const char *s);

// ── Sorting ───────────────────────────────────────────────────────────────────
void  qsort(void *base, size_t n, size_t size,
            int (*cmp)(const void *, const void *));
void *bsearch(const void *key, const void *base, size_t n, size_t size,
              int (*cmp)(const void *, const void *));

// ── I/O (redirected to COM1 serial) ──────────────────────────────────────────
typedef struct _FILE FILE;
extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

int printf(const char *fmt, ...);
int fprintf(FILE *f, const char *fmt, ...);
int sprintf(char *buf, const char *fmt, ...);
int sscanf(const char *buf, const char *fmt, ...);
int snprintf(char *buf, size_t n, const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);
int vfprintf(FILE *f, const char *fmt, va_list ap);
int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap);
int fputs(const char *s, FILE *f);
int fputc(int c, FILE *f);
int puts(const char *s);
int fflush(FILE *f);
size_t fwrite(const void *ptr, size_t size, size_t n, FILE *f);
int fileno(FILE *f);
FILE *fdopen(int fd, const char *mode);
FILE *fopen(const char *path, const char *mode);
int fclose(FILE *f);
size_t fread(void *ptr, size_t size, size_t n, FILE *f);
int fseek(FILE *f, long offset, int whence);
long ftell(FILE *f);
int feof(FILE *f);
int ferror(FILE *f);

// ── POSIX types ───────────────────────────────────────────────────────────────
#include <sys/types.h>
#include "dirent.h"
#include "utime.h"
#include "sys/times.h"
#include "pwd.h"

// ── Time ──────────────────────────────────────────────────────────────────────
#include <time.h>

// ── POSIX stubs ───────────────────────────────────────────────────────────────
void   abort(void) __attribute__((noreturn));
void   exit(int code) __attribute__((noreturn));
void   _exit(int code) __attribute__((noreturn));
int    atexit(void (*fn)(void));
char  *getenv(const char *name);
int    setenv(const char *name, const char *val, int overwrite);
int    unsetenv(const char *name);
int    getpid(void);
int    getpagesize(void);
long   sysconf(int name);
int    dup2(int oldfd, int newfd);
int    unlink(const char *path);
int    rename(const char *old, const char *new);
int    chdir(const char *path);
int    rmdir(const char *path);
int    mkdir(const char *path, unsigned int mode);
char  *realpath(const char *path, char *resolved_path);
extern char **environ;

// ── Math (thin wrappers — uses libgcc where possible) ─────────────────────────
double fabs(double x);
double fmod(double x, double y);
double pow(double x, double y);
double sqrt(double x);
double floor(double x);
double ceil(double x);
double round(double x);
double log(double x);
double log2(double x);
double log10(double x);
double exp(double x);
double sin(double x);
double cos(double x);
double tan(double x);
double atan2(double y, double x);
double hypot(double x, double y);

#define INFINITY  __builtin_inff()
#define NAN       __builtin_nanf("")
#define HUGE_VAL  __builtin_huge_val()

static inline int isinf(double x)  { return __builtin_isinf(x); }
static inline int isnan(double x)  { return __builtin_isnan(x); }
static inline int isfinite(double x) { return __builtin_isfinite(x); }

// ── Limits ────────────────────────────────────────────────────────────────────
#define INT_MAX    0x7FFFFFFF
#define INT_MIN    (-INT_MAX - 1)
#define UINT_MAX   0xFFFFFFFFu
#define LONG_MAX   0x7FFFFFFFFFFFFFFFL
#define LONG_MIN   (-LONG_MAX - 1L)
#define ULONG_MAX  0xFFFFFFFFFFFFFFFFuL
#define LLONG_MAX  LONG_MAX
#define LLONG_MIN  LONG_MIN
#ifndef SIZE_MAX
#define SIZE_MAX   ULONG_MAX
#endif
#define CHAR_BIT   8
#define PATH_MAX   4096
#define NAME_MAX   255

#define _SC_PAGESIZE 30
#define _SC_PAGE_SIZE _SC_PAGESIZE
#define _SC_THREAD_STACK_MIN 75

// ── Signals (stubbed — no processes, no signals) ──────────────────────────────
#define SIG_DFL  ((void(*)(int))0)
#define SIG_IGN  ((void(*)(int))1)
#define SIG_ERR  ((void(*)(int))-1)
#define SIGINT    2
#define SIGTERM  15
#define SIGFPE    8
#define SIGSEGV  11
#define SIGPIPE  13
#define SIGHUP    1
#define SIGQUIT   3
#define SIGILL    4
#define SIGABRT   6
#define SIGALRM  14
#define SIGCHLD  17
#define SIGUSR1  10
#define SIGUSR2  12

typedef unsigned long sigset_t;

typedef struct {
    void (*sa_handler)(int);
    sigset_t sa_mask;
    int sa_flags;
} struct_sigaction;          /* named to avoid collision with the function */
#define sigaction_t struct_sigaction

/* Aliases CPython signalmodule.c expects */
#define SA_RESTART  0x10000000
#define SA_NOCLDSTOP 0x00000001

typedef void (*sighandler_t)(int);
sighandler_t signal(int sig, sighandler_t handler);
int raise(int sig);
int sigaction(int sig, const struct_sigaction *act, struct_sigaction *old);
int sigprocmask(int how, const sigset_t *set, sigset_t *old);
int sigemptyset(sigset_t *set);
int sigfillset(sigset_t *set);
int sigaddset(sigset_t *set, int sig);
int sigdelset(sigset_t *set, int sig);
int sigismember(const sigset_t *set, int sig);

#define SIG_BLOCK   0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2

// ── pthread ──────────────────────────────────────────────────────────────────
#include "pthread.h"

// ── Locale (stubbed — always "C") ─────────────────────────────────────────────
#define LC_ALL      0
#define LC_COLLATE  1
#define LC_CTYPE    2
#define LC_MONETARY 3
#define LC_NUMERIC  4
#define LC_TIME     5
char *setlocale(int category, const char *locale);
struct lconv { char *decimal_point; char *thousands_sep; };
struct lconv *localeconv(void);
