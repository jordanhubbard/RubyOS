/* unistd.h — bare-metal POSIX I/O stubs for PythonOS. */
#pragma once
#include <stddef.h>
#include <sys/types.h>

#define STDIN_FILENO  0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

#define F_OK 0
#define R_OK 4
#define W_OK 2
#define X_OK 1

long   read(int fd, void *buf, size_t n);
long   write(int fd, const void *buf, size_t n);
int    close(int fd);
off_t  lseek(int fd, off_t offset, int whence);
int    isatty(int fd);
int    getpid(void);
int    getpagesize(void);
long   sysconf(int name);
#define _SC_PAGESIZE 30
#define _SC_PAGE_SIZE _SC_PAGESIZE
#define _SC_THREAD_STACK_MIN 75
int    access(const char *path, int mode);
char  *getcwd(char *buf, size_t size);
int    unlink(const char *path);
int    rmdir(const char *path);
int    chdir(const char *path);
int    dup(int fd);
int    dup2(int oldfd, int newfd);
int    pipe(int fds[2]);
int    fsync(int fd);
int    ftruncate(int fd, off_t length);
void   _exit(int status) __attribute__((noreturn));
int    getppid(void);
int    geteuid(void);
int    getegid(void);
int    getuid(void);
int    getgid(void);
unsigned int alarm(unsigned int seconds);
int pause(void);
int madvise(void *addr, size_t length, int advice);
