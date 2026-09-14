/* sys/time.h — bare-metal stub for PythonOS.
 * Intercepts system #include <sys/time.h> so that glibc's bits/types/struct_timeval.h
 * is never pulled in (it would conflict with our struct timeval in <time.h>).
 */
#pragma once
#ifndef _SYS_TIME_H
#define _SYS_TIME_H 1
#include <time.h>
/* Set glibc guards so bits/types/struct_timeval.h is skipped if reached via other paths */
#define __timeval_defined 1
#define __struct_timeval_defined 1
#endif
