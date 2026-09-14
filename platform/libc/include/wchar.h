/* wchar.h — bare-metal stub. wchar_t comes from stddef.h (freestanding). */
#pragma once
#include <stddef.h>
typedef int wint_t;
#ifndef WCHAR_MIN
#define WCHAR_MIN (-2147483647 - 1)
#endif
#ifndef WCHAR_MAX
#define WCHAR_MAX  2147483647
#endif
#define WEOF       ((wint_t)-1)

typedef struct { unsigned int __state; } mbstate_t;

/* Wide string functions — implementations in string.c or deferred stubs */
size_t  wcslen(const wchar_t *s);
wchar_t *wcscpy(wchar_t *dst, const wchar_t *src);
wchar_t *wcsncpy(wchar_t *dst, const wchar_t *src, size_t n);
int     wcscmp(const wchar_t *a, const wchar_t *b);
int     wcsncmp(const wchar_t *a, const wchar_t *b, size_t n);
wchar_t *wcschr(const wchar_t *s, wchar_t c);
wchar_t *wcsrchr(const wchar_t *s, wchar_t c);
wchar_t *wcscat(wchar_t *dst, const wchar_t *src);
wchar_t *wcsncat(wchar_t *dst, const wchar_t *src, size_t n);
wchar_t *wcsdup(const wchar_t *s);
wint_t  btowc(int c);
int     wcswidth(const wchar_t *s, size_t n);
wchar_t *wmemchr(const wchar_t *s, wchar_t c, size_t n);
wchar_t *wmemcpy(wchar_t *dst, const wchar_t *src, size_t n);
wchar_t *wmemset(wchar_t *s, wchar_t c, size_t n);
int     wmemcmp(const wchar_t *a, const wchar_t *b, size_t n);
wchar_t *wcstok(wchar_t *str, const wchar_t *delim, wchar_t **saveptr);

long    wcstol(const wchar_t *s, wchar_t **end, int base);
unsigned long wcstoul(const wchar_t *s, wchar_t **end, int base);
double  wcstod(const wchar_t *s, wchar_t **end);

int     swprintf(wchar_t *buf, size_t n, const wchar_t *fmt, ...);
int     vswprintf(wchar_t *buf, size_t n, const wchar_t *fmt, ...);
