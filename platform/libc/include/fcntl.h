/* fcntl.h — bare-metal stub for PythonOS. */
#pragma once
#include <sys/types.h>

#define O_RDONLY    0
#define O_WRONLY    1
#define O_RDWR      2
#define O_CREAT     0x40
#define O_EXCL      0x80
#define O_TRUNC     0x200
#define O_APPEND    0x400
#define O_NONBLOCK  0x800
#define O_NOFOLLOW  0x20000
#define O_CLOEXEC   0x80000

#define F_DUPFD     0
#define F_GETFD     1
#define F_SETFD     2
#define F_GETFL     3
#define F_SETFL     4

#define FD_CLOEXEC  1

int open(const char *path, int flags, ...);
int fcntl(int fd, int cmd, ...);
