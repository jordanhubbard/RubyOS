/* inttypes.h — bare-metal stub. Just pulls in stdint.h. */
#pragma once
#include <stdint.h>

/* printf format macros for uintptr_t / int64_t etc. */
#define PRId64  "ld"
#define PRIi64  "ld"
#define PRIu64  "lu"
#define PRIx64  "lx"
#define PRIX64  "lX"
#define PRId32  "d"
#define PRIi32  "d"
#define PRIu32  "u"
#define PRIx32  "x"
#define PRIX32  "X"
#define PRIuPTR "lu"
#define PRIdPTR "ld"
#define PRIiPTR "ld"
#define PRIxPTR "lx"
