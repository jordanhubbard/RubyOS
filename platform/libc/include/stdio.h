/* stdio.h — bare-metal wrapper for PythonOS.
 *
 * Python.h includes <stdio.h> unconditionally for FILE*.
 * The system stdio.h defines FILE as struct _IO_FILE on glibc systems.
 * We wrap it with #include_next and add the POSIX extensions (fileno,
 * fdopen) that glibc hides behind _POSIX_C_SOURCE.
 */
#pragma once

/* Pull in the real system stdio.h via GCC's include_next */
#include_next <stdio.h>

/* POSIX extensions — glibc requires _POSIX_C_SOURCE to expose these,
 * but we need them unconditionally on our bare-metal system. */
#ifndef fileno
int fileno(FILE *f);
#endif
#ifndef fdopen
FILE *fdopen(int fd, const char *mode);
#endif
#ifndef fopen
FILE *fopen(const char *path, const char *mode);
#endif
