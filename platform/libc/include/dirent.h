/*
 * dirent.h — bare-metal stub for PythonOS.
 * Provides just enough for posixmodule.c to compile; all calls return ENOSYS.
 */
#pragma once

#include <stdint.h>
#include <stddef.h>

/* Opaque directory handle */
typedef struct _DIR DIR;

/* Minimal dirent — d_name and d_ino required by posixmodule.c */
struct dirent {
    unsigned long d_ino;
    char          d_name[256];
};

DIR            *opendir(const char *name);
DIR            *fdopendir(int fd);
struct dirent  *readdir(DIR *d);
int             closedir(DIR *d);
void            rewinddir(DIR *d);
