/*
 * syscalls.c — POSIX stubs.
 *
 * CPython calls these. Most are no-ops or return sensible defaults.
 * Real implementations come later as kernel subsystems mature.
 */

#include "include/libc.h"
#include "include/spinlock.h"
#include "include/sys/syscall.h"
#ifndef ARCH_ARM64
#include "../boot/io.h"
#endif
#ifdef ARCH_ARM64
#include "../boot/io_arm64.h"
#endif
#include <stdint.h>
#include <sys/resource.h>

// ── Process ───────────────────────────────────────────────────────────────────

void abort(void) {
    // Disable interrupts and halt — this is a kernel panic path
#ifdef ARCH_ARM64
    for (;;) __asm__ volatile ("wfe");
#else
    __asm__ volatile ("cli");
    for (;;) __asm__ volatile ("hlt");
#endif
}

void exit(int code) {
    (void)code;
    abort();
}

void _exit(int code) { exit(code); }

int atexit(void (*fn)(void)) {
    (void)fn;
    return 0;
}

int getpid(void) { return 1; }    // kernel is PID 1

int getpagesize(void) { return 4096; }

long sysconf(int name) {
    if (name == _SC_PAGESIZE || name == _SC_PAGE_SIZE) {
        return getpagesize();
    }
    if (name == _SC_THREAD_STACK_MIN) {
        return 16384;
    }
    errno = EINVAL;
    return -1;
}

// ── Environment ───────────────────────────────────────────────────────────────

char *getenv(const char *name) { (void)name; return NULL; }

int setenv(const char *name, const char *val, int overwrite) {
    (void)name; (void)val; (void)overwrite;
    return -1;
}

int unsetenv(const char *name) { (void)name; return 0; }

// ── Signals ───────────────────────────────────────────────────────────────────

static sighandler_t _signal_handlers[32] = {0};

sighandler_t signal(int sig, sighandler_t handler) {
    if (sig < 0 || sig >= 32) return SIG_ERR;
    sighandler_t old = _signal_handlers[sig];
    _signal_handlers[sig] = handler;
    return old;
}

int raise(int sig) {
    if (sig >= 0 && sig < 32 && _signal_handlers[sig] &&
        _signal_handlers[sig] != SIG_IGN)
        _signal_handlers[sig](sig);
    return 0;
}

int sigaction(int sig, const struct_sigaction *act, struct_sigaction *old) {
    if (old) {
        old->sa_handler = (sig >= 0 && sig < 32) ? _signal_handlers[sig] : SIG_DFL;
        old->sa_mask    = 0;
        old->sa_flags   = 0;
    }
    if (act && sig >= 0 && sig < 32)
        _signal_handlers[sig] = act->sa_handler;
    return 0;
}

int sigprocmask(int how, const sigset_t *set, sigset_t *old) {
    (void)how; (void)set;
    if (old) *old = 0;
    return 0;
}

int sigemptyset(sigset_t *set)           { if (set) *set = 0; return 0; }
int sigfillset(sigset_t *set)            { if (set) *set = ~(sigset_t)0; return 0; }
int sigaddset(sigset_t *set, int sig)    { if (set) *set |= (sigset_t)1 << sig; return 0; }
int sigdelset(sigset_t *set, int sig)    { if (set) *set &= ~((sigset_t)1 << sig); return 0; }
int sigismember(const sigset_t *set, int sig) {
    return (set && (*set >> sig) & 1) ? 1 : 0;
}

// ── File system (CPython open/read/write — redirected to frozen modules) ──────

// CPython uses these for loading .py files. With frozen modules we never
// hit the filesystem during import. These stubs exist for completeness
// and to allow CPython to open /dev/urandom etc.

int open(const char *path, int flags, ...) {
    (void)path; (void)flags;
    errno = ENOSYS;
    return -1;
}

static volatile unsigned _rubyos_pipe_pending;

int pipe(int descriptors[2]) {
    descriptors[0] = 10;
    descriptors[1] = 11;
    return 0;
}

int close(int fd) { (void)fd; return 0; }

/* read(0, ...) routes through a kernel-installed callback so terminal
 * line editors (linenoise) can pull bytes from whichever input the
 * kernel has wired up — serial console, PL011, or the TCP REPL byte
 * stream. The callback returns -1 on EOF, otherwise the next byte.
 * If no callback is installed, read(0, ...) returns ENOSYS. */
static int (*_stdin_read_byte)(void) = 0;

void libc_set_stdin_byte_reader(int (*fn)(void)) {
    _stdin_read_byte = fn;
}

int libc_stdin_byte_reader_active(void) {
    return _stdin_read_byte != 0;
}

/* write(1, ...) and write(2, ...) route through a kernel-installed
 * write hook when set; this lets the kernel REPL (or any other byte
 * sink) intercept stdout/stderr writes from linenoise so the editor
 * can drive a TCP-attached client instead of the serial console. The
 * hook receives the destination fd plus a (buf, len) pair and returns
 * 1 if it consumed the write, 0 to fall back to the serial path. */
static int (*_stdout_write_hook)(int fd, const char *buf, size_t n) = 0;

void libc_set_stdout_write_hook(int (*fn)(int, const char *, size_t)) {
    _stdout_write_hook = fn;
}

int libc_stdout_hook_active(void) { return _stdout_write_hook != 0; }
int libc_invoke_stdout_hook(int fd, const char *buf, size_t n) {
    return _stdout_write_hook ? _stdout_write_hook(fd, buf, n) : 0;
}

long read(int fd, void *buf, size_t n) {
    if (fd == 10 && buf && n && _rubyos_pipe_pending) {
        *(unsigned char *)buf = 0;
        _rubyos_pipe_pending--;
        return 1;
    }
    if (fd != 0 || !buf || n == 0) {
        if (fd == 0 && !_stdin_read_byte) {
            errno = ENOSYS;
        } else {
            errno = ENOSYS;
        }
        return -1;
    }
    if (!_stdin_read_byte) {
        errno = ENOSYS;
        return -1;
    }
    char *out = (char *)buf;
    size_t got = 0;
    while (got < n) {
        int c = _stdin_read_byte();
        if (c < 0) {
            break;
        }
        out[got++] = (char)c;
        if (got >= 1) {
            /* Single-byte read semantics (linenoise reads one byte at
             * a time anyway). Stop after the first byte so blocking is
             * minimized and the caller can decide whether to keep
             * reading. */
            break;
        }
    }
    return (long)got;
}

long write(int fd, const void *buf, size_t n) {
    if (fd == 11) {
        _rubyos_pipe_pending += (unsigned)n;
        return (long)n;
    }
    // fd 1 = stdout, fd 2 = stderr — both go to serial unless a kernel
    // hook has claimed them (e.g. the TCP REPL routing linenoise output
    // back to the connected client).
    if ((fd == 1 || fd == 2) && libc_stdout_hook_active()) {
        if (libc_invoke_stdout_hook(fd, buf, n)) {
            return (long)n;
        }
    }
    if (fd == 1 || fd == 2) {
        const char *p = buf;
        for (size_t i = 0; i < n; i++) {
#ifdef ARCH_ARM64
            pl011_putc(p[i]);
#else
            while ((inb(0x3F8 + 5) & 0x20) == 0) {}
            if (p[i] == '\n') { while ((inb(0x3F8 + 5) & 0x20) == 0) {} outb(0x3F8, '\r'); }
            outb(0x3F8, p[i]);
#endif
        }
        return (long)n;
    }
    errno = ENOSYS;
    return -1;
}

long lseek(int fd, long offset, int whence) {
    (void)fd; (void)offset; (void)whence;
    errno = ENOSYS;
    return -1;
}

int stat(const char *path, void *buf) {
    (void)path; (void)buf;
    errno = ENOENT;
    return -1;
}

int fstat(int fd, void *buf) { (void)fd; (void)buf; errno = ENOSYS; return -1; }
int lstat(const char *path, void *buf) { (void)path; (void)buf; errno = ENOENT; return -1; }
int access(const char *path, int mode) { (void)path; (void)mode; errno = ENOENT; return -1; }

int fcntl(int fd, int cmd, ...) { (void)fd; (void)cmd; return 0; }
int fchmod(int fd, mode_t mode) { (void)fd; (void)mode; return 0; }
mode_t umask(mode_t mask) { (void)mask; return 0; }

/* Minimal ioctl: serves TIOCGWINSZ for terminal-aware code (linenoise)
 * by reporting a fixed 80x24 viewport. Other requests fail with ENOSYS. */
#include <sys/ioctl.h>
#include <stdarg.h>
int ioctl(int fd, unsigned long req, ...) {
    (void)fd;
    if (req == TIOCGWINSZ) {
        va_list ap;
        va_start(ap, req);
        struct winsize *ws = va_arg(ap, struct winsize *);
        va_end(ap);
        if (ws) {
            ws->ws_row = 24;
            ws->ws_col = 80;
            ws->ws_xpixel = 0;
            ws->ws_ypixel = 0;
        }
        return 0;
    }
    errno = ENOSYS;
    return -1;
}

/* termios stubs: linenoise expects to flip the terminal into raw mode
 * via tcsetattr(TCSAFLUSH, ...). On bare metal the wire is already in
 * a minimal state (no kernel line discipline), so these are no-ops
 * that succeed; linenoise's editing logic does the right thing on top. */
#include <termios.h>
int tcgetattr(int fd, struct termios *t) {
    (void)fd;
    if (!t) { errno = EINVAL; return -1; }
    /* Pretend we're in cooked mode so linenoise has something sensible
     * to restore via tcsetattr later. */
    t->c_iflag = ICRNL | IXON;
    t->c_oflag = OPOST;
    t->c_cflag = CS8;
    t->c_lflag = ECHO | ICANON | ISIG | IEXTEN;
    for (int i = 0; i < NCCS; i++) t->c_cc[i] = 0;
    return 0;
}
int tcsetattr(int fd, int act, const struct termios *t) {
    (void)fd; (void)act; (void)t;
    return 0;
}

// ── Memory mapping ────────────────────────────────────────────────────────────

#define PROT_READ  1
#define PROT_WRITE 2
#define MAP_PRIVATE 2
#define MAP_FIXED   0x10
#define MAP_ANON    0x20
#define MAP_FAILED  ((void *)-1)

/* One slot per live mapping. CRuby's GC takes a mapping per heap page, so
 * this bounds how much object heap the guest can hold -- at 128 slots it ran
 * out after a few megabytes of pages and mmap started returning MAP_FAILED
 * with memory still plentiful, which CRuby reports as "failed to allocate
 * memory" and dies on. 16384 slots covers a gigabyte of 64 KiB pages and
 * costs 512 KiB of BSS. */
#define MMAP_MAX_RECORDS 16384
#define MMAP_PAGE_SIZE 4096UL

typedef struct {
    int used;
    void *addr;
    void *raw;
    size_t length;
} mmap_record_t;

static mmap_record_t mmap_records[MMAP_MAX_RECORDS];
static spinlock_t mmap_lock = SPINLOCK_INITIALIZER;

static int mmap_range_end(uintptr_t start, size_t length, uintptr_t *end) {
    uintptr_t value = start + length;
    if (value < start) {
        return 0;
    }
    *end = value;
    return 1;
}

static size_t mmap_page_align(size_t length) {
    return (length + MMAP_PAGE_SIZE - 1) & ~(MMAP_PAGE_SIZE - 1);
}

static int mmap_record_contains(const mmap_record_t *record,
                                uintptr_t start, uintptr_t end) {
    uintptr_t record_start = (uintptr_t)record->addr;
    uintptr_t record_end = record_start + record->length;
    return record->used && start >= record_start && end <= record_end;
}

static int mmap_range_is_mapped(uintptr_t start, size_t length) {
    uintptr_t end;
    if (!mmap_range_end(start, length, &end)) {
        return 0;
    }
    for (unsigned i = 0; i < MMAP_MAX_RECORDS; i++) {
        if (mmap_record_contains(&mmap_records[i], start, end)) {
            return 1;
        }
    }
    return 0;
}

static int mmap_alloc_record(void *addr, void *raw, size_t length) {
    for (unsigned i = 0; i < MMAP_MAX_RECORDS; i++) {
        if (!mmap_records[i].used) {
            mmap_records[i].used = 1;
            mmap_records[i].addr = addr;
            mmap_records[i].raw = raw;
            mmap_records[i].length = length;
            return 1;
        }
    }
    return 0;
}

static int mmap_raw_still_mapped(void *raw) {
    for (unsigned i = 0; i < MMAP_MAX_RECORDS; i++) {
        if (mmap_records[i].used && mmap_records[i].raw == raw) {
            return 1;
        }
    }
    return 0;
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset) {
    (void)prot; (void)fd; (void)offset;
    if (length == 0) {
        errno = EINVAL;
        return MAP_FAILED;
    }
    size_t map_length = mmap_page_align(length);
    if (map_length < length) {
        errno = EINVAL;
        return MAP_FAILED;
    }

    if ((flags & MAP_FIXED) && addr) {
        spin_lock(&mmap_lock);
        int mapped = mmap_range_is_mapped((uintptr_t)addr, map_length);
        spin_unlock(&mmap_lock);
        if (!mapped) {
            errno = EINVAL;
            return MAP_FAILED;
        }
        memset(addr, 0, map_length);
        return addr;
    }

    if ((flags & MAP_FIXED) && !addr) {
        errno = EINVAL;
        return MAP_FAILED;
    }

    size_t total = map_length + MMAP_PAGE_SIZE + sizeof(void *);
    if (total < map_length) {
        errno = EINVAL;
        return MAP_FAILED;
    }
    void *raw = calloc(1, total);
    if (!raw) {
        return MAP_FAILED;
    }

    uintptr_t aligned = ((uintptr_t)raw + sizeof(void *) + MMAP_PAGE_SIZE - 1) &
                        ~(uintptr_t)(MMAP_PAGE_SIZE - 1);
    ((void **)aligned)[-1] = raw;

    spin_lock(&mmap_lock);
    if (mmap_alloc_record((void *)aligned, raw, map_length)) {
        spin_unlock(&mmap_lock);
        return (void *)aligned;
    }
    spin_unlock(&mmap_lock);

    errno = ENOMEM;
    free(raw);
    return MAP_FAILED;
}

int munmap(void *addr, size_t length) {
    if (!addr || length == 0) {
        errno = EINVAL;
        return -1;
    }
    size_t unmap_length = mmap_page_align(length);
    if (unmap_length < length) {
        errno = EINVAL;
        return -1;
    }

    uintptr_t target = (uintptr_t)addr;
    uintptr_t unmap_end;
    if (!mmap_range_end(target, unmap_length, &unmap_end)) {
        errno = EINVAL;
        return -1;
    }

    spin_lock(&mmap_lock);
    for (unsigned i = 0; i < MMAP_MAX_RECORDS; i++) {
        if (!mmap_records[i].used) {
            continue;
        }
        uintptr_t start = (uintptr_t)mmap_records[i].addr;
        uintptr_t end = start + mmap_records[i].length;
        if (target < start || unmap_end > end) {
            continue;
        }

        if (target == start && unmap_end == end) {
            void *raw = mmap_records[i].raw;
            mmap_records[i].used = 0;
            int still_mapped = mmap_raw_still_mapped(raw);
            spin_unlock(&mmap_lock);
            if (!still_mapped) {
                free(raw);
            }
            return 0;
        }

        if (target == start) {
            mmap_records[i].addr = (void *)unmap_end;
            mmap_records[i].length = end - unmap_end;
            spin_unlock(&mmap_lock);
            return 0;
        }

        if (unmap_end == end) {
            mmap_records[i].length = target - start;
            spin_unlock(&mmap_lock);
            return 0;
        }

        void *raw = mmap_records[i].raw;
        size_t right_length = end - unmap_end;
        if (!mmap_alloc_record((void *)unmap_end, raw, right_length)) {
            spin_unlock(&mmap_lock);
            errno = ENOMEM;
            return -1;
        }
        mmap_records[i].length = target - start;
        spin_unlock(&mmap_lock);
        return 0;
    }
    spin_unlock(&mmap_lock);
    errno = EINVAL;
    return -1;
}

/* glibc internal: returns pointer to the thread-local errno variable.
 * Single-threaded bare metal: errno is a plain global in stdio.c. */
extern int errno;
int *__errno_location(void) { return &errno; }

int mprotect(void *addr, size_t len, int prot) {
    (void)addr; (void)len; (void)prot;
    return 0;
}

int madvise(void *addr, size_t length, int advice) {
    (void)addr;
    (void)length;
    (void)advice;
    return 0;
}

// ── Random ────────────────────────────────────────────────────────────────────

// CPython uses /dev/urandom; we provide a simple LFSR-based PRNG instead
static uint64_t _rng_state = 0xDEADBEEFCAFEBABEull;

static uint64_t _rand64(void) {
    _rng_state ^= _rng_state << 13;
    _rng_state ^= _rng_state >> 7;
    _rng_state ^= _rng_state << 17;
    return _rng_state;
}

int getrandom(void *buf, size_t n, unsigned int flags) {
    (void)flags;
    size_t total = n;
    uint8_t *b = buf;
    while (n >= 8) { uint64_t r = _rand64(); __builtin_memcpy(b, &r, 8); b += 8; n -= 8; }
    if (n) { uint64_t r = _rand64(); __builtin_memcpy(b, &r, n); }
    return (int)total;  // return bytes generated, not 0 — CPython loops until satisfied
}

// ── Locale ────────────────────────────────────────────────────────────────────

static struct lconv _lconv = { ".", "" };

char *setlocale(int category, const char *locale) {
    (void)category; (void)locale;
    return "C";
}

struct lconv *localeconv(void) { return &_lconv; }

// ── Misc ──────────────────────────────────────────────────────────────────────

extern void rubyos_sleep_ns(uint64_t nanoseconds);

unsigned int sleep(unsigned int seconds) {
    rubyos_sleep_ns((uint64_t)seconds * 1000000000ULL);
    return 0;
}
int usleep(unsigned int us) {
    rubyos_sleep_ns((uint64_t)us * 1000ULL);
    return 0;
}
int nanosleep(const struct timespec *req, struct timespec *rem) {
    if (rem) { rem->tv_sec = 0; rem->tv_nsec = 0; }
    if (!req || req->tv_sec < 0 || req->tv_nsec < 0 || req->tv_nsec >= 1000000000L) {
        errno = EINVAL;
        return -1;
    }
    rubyos_sleep_ns((uint64_t)req->tv_sec * 1000000000ULL +
                    (uint64_t)req->tv_nsec);
    return 0;
}

int pause(void) { errno = EINTR; return -1; }

/* isatty: stdout/stderr are always treated as terminals (they go to
 * serial / TCP REPL via stdio.c). stdin is a terminal only when a
 * kernel callback is installed (see libc_set_stdin_byte_reader); this
 * is the toggle that makes linenoise's enableRawMode succeed when an
 * async edit is in progress, while preserving the no-tty fallback
 * (returns None / "" immediately) when no callback is wired. */
int isatty(int fd) {
    if (fd == 1 || fd == 2) return 1;
    if (fd == 0) return libc_stdin_byte_reader_active();
    return 0;
}

int getrusage(int who, struct rusage *usage) {
    (void)who;
    if (usage) {
        memset(usage, 0, sizeof(*usage));
    }
    return 0;
}

static long _native_tid(void) {
#ifdef ARCH_ARM64
    return 1;
#else
    uint32_t eax, ebx, ecx, edx;
    __asm__ volatile("cpuid"
                     : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
                     : "a"(1), "c"(0));
    return (long)(((ebx >> 24) & 0xffU) + 1);
#endif
}

long syscall(long number, ...) {
    if (number == SYS_gettid) {
        return _native_tid();
    }
    return 1;
}

void *dlopen(const char *file, int mode) { (void)file; (void)mode; return NULL; }
void *dlsym(void *handle, const char *sym) { (void)handle; (void)sym; return NULL; }
int   dlclose(void *handle) { (void)handle; return 0; }
char *dlerror(void) { return "dynamic loading not supported"; }

// ── langinfo ──────────────────────────────────────────────────────────────────

#include <langinfo.h>
char *nl_langinfo(nl_item item) {
    (void)item;
    return "";  /* bare-metal: everything is "C" locale */
}

// ── User/password database (bare-metal stubs) ────────────────────────────────

#include <pwd.h>

struct passwd *getpwuid(unsigned int uid)          { (void)uid;  return NULL; }
struct passwd *getpwnam(const char *name)          { (void)name; return NULL; }
int getpwuid_r(unsigned int uid, struct passwd *pw, char *buf, size_t n, struct passwd **res) {
    (void)uid; (void)pw; (void)buf; (void)n; if(res)*res=NULL; return ENOENT;
}
int getpwnam_r(const char *nm, struct passwd *pw, char *buf, size_t n, struct passwd **res) {
    (void)nm; (void)pw; (void)buf; (void)n; if(res)*res=NULL; return ENOENT;
}
struct passwd *getpwent(void) { return NULL; }
void setpwent(void) {}
void endpwent(void) {}

// ── Directory operations (bare-metal stubs) ───────────────────────────────────

#include <dirent.h>
#include <utime.h>
#include <sys/times.h>

DIR *opendir(const char *name)          { (void)name; errno = ENOSYS; return NULL; }
DIR *fdopendir(int fd)                  { (void)fd;   errno = ENOSYS; return NULL; }
struct dirent *readdir(DIR *d)          { (void)d;    return NULL; }
int   closedir(DIR *d)                  { (void)d;    return 0; }
void  rewinddir(DIR *d)                 { (void)d; }

int utime(const char *path, const struct utimbuf *times) {
    (void)path; (void)times; errno = ENOSYS; return -1;
}

clock_t times(struct tms *buf) {
    if (buf) { buf->tms_utime = buf->tms_stime = buf->tms_cutime = buf->tms_cstime = 0; }
    return (clock_t)-1;
}

// ── mkstemp ───────────────────────────────────────────────────────────────────

int mkstemp(char *tmpl) { (void)tmpl; return -1; }

// ── stdio stubs (glibc provides these via libc.so; we stub them) ──────────────
// FILE* ABI is pointer-compatible with glibc's struct _IO_FILE*.

void clearerr(FILE *f) { (void)f; }
void setbuf(FILE *f, char *buf) { (void)f; (void)buf; }

char *strerror(int errnum) { (void)errnum; return "Error"; }

// ── Missing unistd stubs ──────────────────────────────────────────────────────

char *getcwd(char *buf, size_t size) {
    if (buf && size > 0) { buf[0] = '/'; buf[1] = '\0'; }
    return buf;
}

char *realpath(const char *path, char *resolved_path) {
    if (!path) {
        errno = EINVAL;
        return NULL;
    }
    if (!resolved_path) {
        return strdup(path);
    }
    strncpy(resolved_path, path, PATH_MAX - 1);
    resolved_path[PATH_MAX - 1] = '\0';
    return resolved_path;
}

// environ: empty environment (bare metal has no env vars)
char *_environ_empty = NULL;
char **environ = &_environ_empty;

int dup2(int oldfd, int newfd) { (void)oldfd; (void)newfd; errno = ENOSYS; return -1; }
int unlink(const char *path) { (void)path; errno = ENOSYS; return -1; }
int rename(const char *old, const char *new) { (void)old; (void)new; errno = ENOSYS; return -1; }
int chdir(const char *path) { (void)path; errno = ENOSYS; return -1; }
int rmdir(const char *path) { (void)path; errno = ENOSYS; return -1; }
int mkdir(const char *path, unsigned int mode) { (void)path; (void)mode; errno = ENOSYS; return -1; }

// ── stdio stubs not inlined by glibc in freestanding mode ────────────────────

int putc(int c, FILE *f) { return fputc(c, f); }
int getc(FILE *f) { (void)f; return -1; }
void rewind(FILE *f) { fseek(f, 0, 0 /* SEEK_SET */); }

// ── glibc internals referenced by CPython ────────────────────────────────────
// glibc's signal.h renames calls to signal() to __sysv_signal at the call
// site. Our signal() is compiled without glibc's signal.h so it keeps the
// plain "signal" symbol. Provide __sysv_signal as a global alias.
__asm__(".globl __sysv_signal\n\t.set __sysv_signal, signal");

// glibc ctype tables: code compiled against glibc headers calls __ctype_b_loc()
// instead of isalnum() etc. We provide static ASCII-only tables.
// Flag bit layout: little-endian x86-64 (bits 8+ shift left 8, bits 0-7 stay)
// _ISblank=0x0001 _IScntrl=0x0002 _ISpunct=0x0004 _ISalnum=0x0008
// _ISupper=0x0100 _ISlower=0x0200 _ISalpha=0x0400 _ISdigit=0x0800
// _ISxdigit=0x1000 _ISspace=0x2000 _ISprint=0x4000 _ISgraph=0x8000

static const unsigned short _ctype_b_data[384] = {
    // entries 0-127: for chars -128..-1 (signed), all zero
    // entries 128-383: for chars 0..255
    [128+0  ... 128+8]   = 0x0002u,  // NUL-BS: cntrl
    [128+9]              = 0x2003u,  // TAB: cntrl|space|blank
    [128+10 ... 128+13]  = 0x2002u,  // LF,VT,FF,CR: cntrl|space
    [128+14 ... 128+31]  = 0x0002u,  // SO-US: cntrl
    [128+32]             = 0x6001u,  // SP: print|space|blank
    [128+33 ... 128+47]  = 0xC004u,  // !-/ : print|graph|punct
    [128+48 ... 128+57]  = 0xD808u,  // 0-9: print|graph|digit|xdigit|alnum
    [128+58 ... 128+64]  = 0xC004u,  // :-@ : print|graph|punct
    [128+65 ... 128+70]  = 0xD508u,  // A-F: print|graph|upper|alpha|xdigit|alnum
    [128+71 ... 128+90]  = 0xC508u,  // G-Z: print|graph|upper|alpha|alnum
    [128+91 ... 128+96]  = 0xC004u,  // [-` : print|graph|punct
    [128+97 ... 128+102] = 0xD608u,  // a-f: print|graph|lower|alpha|xdigit|alnum
    [128+103 ... 128+122]= 0xC608u,  // g-z: print|graph|lower|alpha|alnum
    [128+123 ... 128+126]= 0xC004u,  // {-~: print|graph|punct
    [128+127]            = 0x0002u,  // DEL: cntrl
    // 128-255: 0 (non-ASCII — unclassified in ASCII-only locale)
};

static const unsigned short *_ctype_b_ptr = &_ctype_b_data[128];

// toupper/tolower tables: (*ptr)[c] = converted character
static int32_t _ctype_toupper_tbl[384];
static int32_t _ctype_tolower_tbl[384];

static void _init_case_tables(void) {
    for (int i = 0; i < 384; i++) {
        int c = i - 128;
        _ctype_toupper_tbl[i] = (c >= 'a' && c <= 'z') ? c - 32 : c;
        _ctype_tolower_tbl[i] = (c >= 'A' && c <= 'Z') ? c + 32 : c;
    }
}

static int _case_tables_ready = 0;
static void _ensure_case_tables(void) {
    if (!_case_tables_ready) { _init_case_tables(); _case_tables_ready = 1; }
}

const unsigned short int **__ctype_b_loc(void) {
    return (const unsigned short int **)&_ctype_b_ptr;
}

int32_t **__ctype_toupper_loc(void) {
    _ensure_case_tables();
    static int32_t *p = NULL;
    p = &_ctype_toupper_tbl[128];
    return &p;
}

int32_t **__ctype_tolower_loc(void) {
    _ensure_case_tables();
    static int32_t *p = NULL;
    p = &_ctype_tolower_tbl[128];
    return &p;
}

// Real-time signal bounds: SIGRTMIN=34, SIGRTMAX=64 on Linux x86-64
int __libc_current_sigrtmin(void) { return 34; }
int __libc_current_sigrtmax(void) { return 64; }

#ifdef ARCH_ARM64
/* __getauxval — Linux auxiliary vector query. Used by libgcc lse-init.o to
 * check if ARM Large System Extensions are available. On bare metal there's
 * no kernel AUX vector; return 0 (feature absent). */
unsigned long __getauxval(unsigned long type) { (void)type; return 0; }
#endif
