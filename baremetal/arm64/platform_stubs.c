#include <stddef.h>
#include <stdint.h>

extern int errno;
extern void *malloc(size_t);
extern void *aligned_alloc(size_t, size_t);
extern long sysconf(int);
extern char stack_bottom[];
extern char stack_top[];


#define ENOSYS 38
#define STUB(name) int name(void) { errno = ENOSYS; return -1; }

int __sysconf(int name) { return (int)sysconf(name); }
int abs(int value) { return value < 0 ? -value : value; }
int ffs(int value) { return value ? __builtin_ctz((unsigned)value) + 1 : 0; }

void explicit_bzero(void *pointer, size_t length)
{
    volatile unsigned char *bytes = pointer;
    while (length--) *bytes++ = 0;
}

char *stpcpy(char *destination, const char *source)
{
    while ((*destination = *source) != '\0') { ++destination; ++source; }
    return destination;
}

void *memrchr(const void *memory, int byte, size_t length)
{
    const unsigned char *cursor = (const unsigned char *)memory + length;
    while (length--) if (*--cursor == (unsigned char)byte) return (void *)cursor;
    return NULL;
}

void *memmem(const void *haystack, size_t haystack_length,
             const void *needle, size_t needle_length)
{
    const unsigned char *h = haystack, *n = needle;
    size_t i, j;
    if (needle_length == 0) return (void *)h;
    for (i = 0; i + needle_length <= haystack_length; ++i) {
        for (j = 0; j < needle_length && h[i + j] == n[j]; ++j) {}
        if (j == needle_length) return (void *)(h + i);
    }
    return NULL;
}

double nan(const char *tag)
{
    union { uint64_t bits; double value; } result = { UINT64_C(0x7ff8000000000000) };
    (void)tag;
    return result.value;
}

double lgamma_r(double value, int *sign)
{
    (void)value;
    *sign = 1;
    return 0.0;
}

void qsort_r(void *base, size_t count, size_t width,
             int (*compare)(const void *, const void *, void *), void *argument)
{
    unsigned char *bytes = base;
    size_t i, j, k;
    for (i = 1; i < count; ++i) {
        for (j = i; j > 0 && compare(bytes + (j - 1) * width,
                                     bytes + j * width, argument) > 0; --j) {
            for (k = 0; k < width; ++k) {
                unsigned char temporary = bytes[(j - 1) * width + k];
                bytes[(j - 1) * width + k] = bytes[j * width + k];
                bytes[j * width + k] = temporary;
            }
        }
    }
}

int posix_memalign(void **result, size_t alignment, size_t size)
{
    *result = aligned_alloc(alignment, size);
    return *result ? 0 : 12;
}

int getrlimit(int resource, void *limit)
{
    uint64_t *values = limit;
    (void)resource;
    values[0] = (uint64_t)(stack_top - stack_bottom);
    values[1] = values[0];
    return 0;
}

int getuid(void) { return 0; }
int geteuid(void) { return 0; }
int getgid(void) { return 0; }
int getegid(void) { return 0; }
int getppid(void) { return 0; }
int getpgrp(void) { return 1; }
int getpgid(int pid) { (void)pid; return 1; }
int getsid(int pid) { (void)pid; return 1; }
int getpriority(int which, int who) { (void)which; (void)who; return 0; }

int pthread_attr_setinheritsched(void *attribute, int inherit)
{ (void)attribute; (void)inherit; return 0; }
int pthread_kill(uintptr_t thread, int signal)
{ (void)thread; (void)signal; return 0; }
int pthread_setname_np(uintptr_t thread, const char *name)
{ (void)thread; (void)name; return 0; }
int pthread_sigmask(int how, const void *set, void *old_set)
{ (void)how; (void)set; (void)old_set; return 0; }

struct rubyos_pollfd { int fd; short events; short revents; };
int poll(void *opaque_fds, unsigned long count, int timeout)
{
    struct rubyos_pollfd *fds = opaque_fds;
    (void)timeout;
    if (count && fds[0].fd == 10) {
        fds[0].revents = 1;
        return 1;
    }
    return 0;
}
int select(int count, void *readfds, void *writefds, void *exceptfds, void *timeout)
{ (void)count; (void)readfds; (void)writefds; (void)exceptfds; (void)timeout; return 0; }

void perror(const char *message) { (void)message; }

int smp_submit_worker(void (*entry)(void *), void *argument, void **handle)
{ (void)entry; (void)argument; (void)handle; return 0; }
int smp_join_worker(void *handle, void **result)
{ (void)handle; (void)result; return 0; }

__attribute__((noreturn)) void __assert_fail(const char *expression,
    const char *file, unsigned line, const char *function)
{
    extern void rubyos_serial_puts(const char *text);
    (void)line;
#ifdef ARCH_ARM64
    rubyos_serial_puts("[RubyOS/arm64] ASSERT: ");
#else
    rubyos_serial_puts("[RubyOS/x86_64] ASSERT: ");
#endif
    rubyos_serial_puts(expression);
    rubyos_serial_puts(" in ");
    rubyos_serial_puts(function);
    rubyos_serial_puts(" (");
    rubyos_serial_puts(file);
    rubyos_serial_puts(")\n");
#ifdef ARCH_ARM64
    for (;;) __asm__ volatile("wfe");
#else
    __asm__ volatile("cli");
    for (;;) __asm__ volatile("hlt");
#endif
}

STUB(chmod) STUB(chown) STUB(crypt) STUB(dup) STUB(endgrent)
STUB(execl) STUB(execle) STUB(execv) STUB(execve) STUB(flock)
STUB(freopen) STUB(getgrnam) STUB(getlogin) STUB(kill) STUB(killpg)
STUB(mknod) STUB(pclose) STUB(popen) STUB(pread) STUB(pwrite)
STUB(setegid) STUB(seteuid) STUB(setgid) STUB(setpgid) STUB(setpriority)
STUB(setregid) STUB(setresgid) STUB(setresuid) STUB(setreuid)
STUB(setrlimit) STUB(setsid) STUB(setuid) STUB(setvbuf) STUB(statx)
STUB(system) STUB(waitpid)
