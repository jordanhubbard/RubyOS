/* ctype.h — bare-metal wrapper for PythonOS.
 * Wraps system ctype.h and adds POSIX/GNU extensions.
 * We override toupper/tolower with ASCII-only implementations to avoid
 * glibc's locale-table inlines (__ctype_toupper_loc / __ctype_tolower_loc)
 * which call glibc internals not available in our freestanding environment.
 */
#pragma once

#include_next <ctype.h>

/* Replace ALL glibc locale-table ctype macros with ASCII-only versions.
 * glibc's is*() and to*() functions call __ctype_b_loc()/__ctype_toupper_loc()
 * which are glibc internals not available in our freestanding environment. */
#undef toupper
#undef tolower
#undef isalnum
#undef isalpha
#undef isdigit
#undef isspace
#undef isupper
#undef islower
#undef isprint
#undef iscntrl
#undef ispunct
#undef isxdigit
#undef isgraph
#undef isblank

#define toupper(c)  (((c) >= 'a' && (c) <= 'z') ? (c) - 32 : (c))
#define tolower(c)  (((c) >= 'A' && (c) <= 'Z') ? (c) + 32 : (c))
#define isalnum(c)  (((c) >= 'A' && (c) <= 'Z') || ((c) >= 'a' && (c) <= 'z') || ((c) >= '0' && (c) <= '9'))
#define isalpha(c)  (((c) >= 'A' && (c) <= 'Z') || ((c) >= 'a' && (c) <= 'z'))
#define isdigit(c)  ((c) >= '0' && (c) <= '9')
#define isspace(c)  ((c) == ' ' || (c) == '\t' || (c) == '\n' || (c) == '\r' || (c) == '\f' || (c) == '\v')
#define isupper(c)  ((c) >= 'A' && (c) <= 'Z')
#define islower(c)  ((c) >= 'a' && (c) <= 'z')
#define isprint(c)  ((unsigned)(c) >= 0x20 && (unsigned)(c) < 0x7f)
#define iscntrl(c)  ((unsigned)(c) < 0x20 || (c) == 0x7f)
#define ispunct(c)  (isprint(c) && !isalnum(c) && (c) != ' ')
#define isxdigit(c) (((c) >= '0' && (c) <= '9') || ((c) >= 'a' && (c) <= 'f') || ((c) >= 'A' && (c) <= 'F'))
#define isgraph(c)  ((unsigned)(c) > ' ' && (unsigned)(c) < 0x7f)
#define isblank(c)  ((c) == ' ' || (c) == '\t')

/* isascii: POSIX extension, not always exposed by system ctype.h */
#ifndef isascii
static inline int isascii(int c) { return (unsigned int)c <= 127; }
#endif

/* toascii: maps c to ASCII range */
#ifndef toascii
static inline int toascii(int c) { return (c) & 0x7f; }
#endif
