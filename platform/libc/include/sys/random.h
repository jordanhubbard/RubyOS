/* sys/random.h — bare-metal stub for PythonOS. */
#pragma once
#include <stddef.h>

#define GRND_NONBLOCK 1
#define GRND_RANDOM   2

int getrandom(void *buf, size_t n, unsigned int flags);
