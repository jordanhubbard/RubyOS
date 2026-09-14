/*
 * stdio.c — Minimal stdio for CPython bare metal.
 *
 * stdout/stderr both route to COM1 serial (port 0x3F8).
 * stdin is unimplemented (returns EOF) — keyboard input goes through
 * the Python keyboard driver, not through C stdio.
 *
 * printf-family: supports %d %i %u %x %X %o %p %s %c %% %l %ll %z
 * Floating point (%f %g %e) uses __builtin_* where possible.
 */

#include "include/libc.h"
#ifndef ARCH_ARM64
#include "../boot/io.h"
#endif
#ifdef ARCH_ARM64
#include "../boot/io_arm64.h"
#endif

// ── errno ─────────────────────────────────────────────────────────────────────
int errno = 0;

// ── FILE structure (opaque — users never allocate these) ──────────────────────
typedef struct _FILE {
    int fd;   // 1 = stdout, 2 = stderr (we only ever have these two)
} _FILE_t;

static _FILE_t _stdout_obj = {1};
static _FILE_t _stderr_obj = {2};
static _FILE_t _stdin_obj = {0};

FILE *stdout = (FILE *)&_stdout_obj;
FILE *stderr = (FILE *)&_stderr_obj;
FILE *stdin  = (FILE *)&_stdin_obj;

// ── Serial output ─────────────────────────────────────────────────────────────
#ifndef ARCH_ARM64
#define COM1_DATA 0x3F8
#define COM1_LSR  (0x3F8 + 5)
#endif

static void serial_putc(char c) {
#ifdef ARCH_ARM64
    pl011_putc(c);
#else
    while ((inb(COM1_LSR) & 0x20) == 0) {}
    if (c == '\n') { while ((inb(COM1_LSR) & 0x20) == 0) {} outb(COM1_DATA, '\r'); }
    outb(COM1_DATA, c);
#endif
}

static void serial_write(const char *s, size_t n) {
    for (size_t i = 0; i < n; i++) serial_putc(s[i]);
}

// ── vsnprintf core ────────────────────────────────────────────────────────────

static void _emit(char **buf, size_t *rem, char c) {
    if (*rem > 1) { **buf = c; (*buf)++; (*rem)--; }
}

static void _emit_str(char **buf, size_t *rem, const char *s, int width, int left) {
    int len = (int)strlen(s);
    int pad = width > len ? width - len : 0;
    if (!left) while (pad-- > 0) _emit(buf, rem, ' ');
    while (*s) _emit(buf, rem, *s++);
    if (left)  while (pad-- > 0) _emit(buf, rem, ' ');
}

static void _emit_uint(char **buf, size_t *rem,
                        unsigned long long v, int base, int upper,
                        int width, int zero_pad, int left) {
    char tmp[64];
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    int i = 0;
    if (v == 0) { tmp[i++] = '0'; }
    else { while (v) { tmp[i++] = digits[v % base]; v /= base; } }
    // tmp is reversed
    int pad = width > i ? width - i : 0;
    if (!left && !zero_pad) while (pad-- > 0) _emit(buf, rem, ' ');
    if (!left &&  zero_pad) while (pad-- > 0) _emit(buf, rem, '0');
    while (i > 0) _emit(buf, rem, tmp[--i]);
    if (left) while (pad-- > 0) _emit(buf, rem, ' ');
}

static void _emit_int(char **buf, size_t *rem,
                       long long v, int width, int zero_pad, int left) {
    if (v < 0) { _emit(buf, rem, '-'); v = -v; if (width > 0) width--; }
    _emit_uint(buf, rem, (unsigned long long)v, 10, 0, width, zero_pad, left);
}

int vsnprintf(char *buf, size_t n, const char *fmt, va_list ap) {
    char *p  = buf;
    size_t rem = n;

    while (*fmt) {
        if (*fmt != '%') { _emit(&p, &rem, *fmt++); continue; }
        fmt++;

        int left = 0, zero_pad = 0, width = 0;
        if (*fmt == '-') { left = 1; fmt++; }
        if (*fmt == '0') { zero_pad = 1; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');

        // length modifier
        int is_long = 0, is_longlong = 0, is_size = 0;
        if (*fmt == 'l') {
            fmt++;
            if (*fmt == 'l') { is_longlong = 1; fmt++; }
            else is_long = 1;
        } else if (*fmt == 'z') { is_size = 1; fmt++; }

        switch (*fmt++) {
        case 'd': case 'i': {
            long long v = is_longlong ? va_arg(ap, long long) :
                          (is_long || is_size) ? va_arg(ap, long) :
                          va_arg(ap, int);
            _emit_int(&p, &rem, v, width, zero_pad, left);
            break;
        }
        case 'u': {
            unsigned long long v = is_longlong ? va_arg(ap, unsigned long long) :
                                   (is_long || is_size) ? va_arg(ap, unsigned long) :
                                   va_arg(ap, unsigned int);
            _emit_uint(&p, &rem, v, 10, 0, width, zero_pad, left);
            break;
        }
        case 'x': {
            unsigned long long v = is_longlong ? va_arg(ap, unsigned long long) :
                                   (is_long || is_size) ? va_arg(ap, unsigned long) :
                                   va_arg(ap, unsigned int);
            _emit_uint(&p, &rem, v, 16, 0, width, zero_pad, left);
            break;
        }
        case 'X': {
            unsigned long long v = is_longlong ? va_arg(ap, unsigned long long) :
                                   (is_long || is_size) ? va_arg(ap, unsigned long) :
                                   va_arg(ap, unsigned int);
            _emit_uint(&p, &rem, v, 16, 1, width, zero_pad, left);
            break;
        }
        case 'o': {
            unsigned long long v = is_longlong ? va_arg(ap, unsigned long long) :
                                   (is_long || is_size) ? va_arg(ap, unsigned long) :
                                   va_arg(ap, unsigned int);
            _emit_uint(&p, &rem, v, 8, 0, width, zero_pad, left);
            break;
        }
        case 'p': {
            unsigned long long v = (unsigned long long)(uintptr_t)va_arg(ap, void *);
            _emit(&p, &rem, '0'); _emit(&p, &rem, 'x');
            _emit_uint(&p, &rem, v, 16, 0, 16, 1, 0);
            break;
        }
        case 's': {
            const char *s = va_arg(ap, const char *);
            _emit_str(&p, &rem, s ? s : "(null)", width, left);
            break;
        }
        case 'c':
            _emit(&p, &rem, (char)va_arg(ap, int));
            break;
        case 'f': case 'g': case 'e': {
            // Minimal float: just print as integer + fractional approximation
            double v = va_arg(ap, double);
            if (v < 0) { _emit(&p, &rem, '-'); v = -v; }
            long long intpart = (long long)v;
            double frac = v - intpart;
            _emit_int(&p, &rem, intpart, 0, 0, 0);
            _emit(&p, &rem, '.');
            for (int i = 0; i < 6; i++) {
                frac *= 10;
                _emit(&p, &rem, '0' + (int)frac);
                frac -= (int)frac;
            }
            break;
        }
        case '%':
            _emit(&p, &rem, '%');
            break;
        default:
            _emit(&p, &rem, '?');
            break;
        }
    }
    if (n > 0) *p = '\0';
    return (int)(p - buf);
}

int vprintf(const char *fmt, va_list ap) {
    char tmp[4096];
    int n = vsnprintf(tmp, sizeof(tmp), fmt, ap);
    serial_write(tmp, n);
    return n;
}

int vfprintf(FILE *f, const char *fmt, va_list ap) {
    (void)f;  // stdout and stderr both go to serial
    return vprintf(fmt, ap);
}

int printf(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt); int r = vprintf(fmt, ap); va_end(ap); return r;
}

int fprintf(FILE *f, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt); int r = vfprintf(f, fmt, ap); va_end(ap); return r;
}

int sprintf(char *buf, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    int r = vsnprintf(buf, (size_t)-1, fmt, ap);
    va_end(ap); return r;
}

int snprintf(char *buf, size_t n, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    int r = vsnprintf(buf, n, fmt, ap);
    va_end(ap); return r;
}

static const char *_scan_spaces(const char *s) {
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r' ||
           *s == '\v' || *s == '\f') {
        s++;
    }
    return s;
}

static int _scan_signed_ll(const char **input, long long *out) {
    const char *s = _scan_spaces(*input);
    int neg = 0;
    if (*s == '+' || *s == '-') {
        neg = *s == '-';
        s++;
    }
    if (*s < '0' || *s > '9') {
        return 0;
    }
    long long value = 0;
    while (*s >= '0' && *s <= '9') {
        value = value * 10 + (*s - '0');
        s++;
    }
    *out = neg ? -value : value;
    *input = s;
    return 1;
}

int vsscanf(const char *buf, const char *fmt, va_list ap) {
    const char *s = buf;
    int assigned = 0;

    while (*fmt) {
        if (*fmt == ' ' || *fmt == '\t' || *fmt == '\n' || *fmt == '\r' ||
            *fmt == '\v' || *fmt == '\f') {
            fmt = _scan_spaces(fmt);
            s = _scan_spaces(s);
            continue;
        }
        if (*fmt != '%') {
            if (*s != *fmt) {
                break;
            }
            s++;
            fmt++;
            continue;
        }

        fmt++;
        int long_count = 0;
        while (*fmt == 'l' && long_count < 2) {
            long_count++;
            fmt++;
        }

        switch (*fmt++) {
        case 'd':
        case 'i': {
            long long value;
            if (!_scan_signed_ll(&s, &value)) {
                return assigned ? assigned : 0;
            }
            if (long_count >= 2) {
                *va_arg(ap, long long *) = value;
            } else if (long_count == 1) {
                *va_arg(ap, long *) = (long)value;
            } else {
                *va_arg(ap, int *) = (int)value;
            }
            assigned++;
            break;
        }
        default:
            return assigned;
        }
    }

    return assigned;
}

int sscanf(const char *buf, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vsscanf(buf, fmt, ap);
    va_end(ap);
    return r;
}

int __isoc99_sscanf(const char *buf, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vsscanf(buf, fmt, ap);
    va_end(ap);
    return r;
}

int puts(const char *s) {
    serial_write(s, strlen(s));
    serial_putc('\n');
    return 0;
}

int fputs(const char *s, FILE *f) {
    (void)f;
    serial_write(s, strlen(s));
    return 0;
}

int fputc(int c, FILE *f) {
    (void)f;
    serial_putc((char)c);
    return c;
}

int fflush(FILE *f) { (void)f; return 0; }

size_t fwrite(const void *ptr, size_t size, size_t n, FILE *f) {
    (void)f;
    serial_write(ptr, size * n);
    return n;
}

int fileno(FILE *f) {
    if (!f) return -1;
    return ((_FILE_t *)f)->fd;
}

FILE *fdopen(int fd, const char *mode) {
    (void)mode;
    if (fd == 1) return stdout;
    if (fd == 2) return stderr;
    return NULL;
}

FILE *fopen(const char *path, const char *mode) {
    (void)path; (void)mode;
    errno = ENOENT;
    return NULL;
}

int fclose(FILE *f) { (void)f; return 0; }

/* fgetc is referenced by linenoise's linenoiseNoTTY() fallback, taken
 * when stdin is not a tty. Returning EOF immediately is the right
 * answer for our bare-metal build — the caller terminates input
 * gracefully and falls back to an empty line. */
int fgetc(FILE *f) { (void)f; return -1; }

size_t fread(void *ptr, size_t size, size_t n, FILE *f) {
    (void)ptr; (void)size; (void)n; (void)f;
    return 0;
}

int fseek(FILE *f, long offset, int whence) {
    (void)f; (void)offset; (void)whence;
    errno = ENOSYS;
    return -1;
}

long ftell(FILE *f) { (void)f; errno = ENOSYS; return -1; }
int feof(FILE *f)   { (void)f; return 1; }
int ferror(FILE *f) { (void)f; return 0; }

// ungetc: bare-metal stub — we have no real buffered file I/O
int ungetc(int c, FILE *f) { (void)c; (void)f; return -1; }

// fgets: reads from stdin (returns NULL — no stdin on bare metal)
char *fgets(char *buf, int n, FILE *f) { (void)buf; (void)n; (void)f; return NULL; }
