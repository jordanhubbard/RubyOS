/*
 * math.c — Math functions for PythonOS.
 *
 * x86-64: uses x87 FPU hardware for transcendentals (sin, cos, log, exp, etc.)
 * AArch64: pure-C software implementations (no x87 on arm64).
 */

#include "include/libc.h"
#include <stdint.h>

/* ── Basic ops — hardware builtins on both arches ────────────────────────── */

double fabs(double x)  { return __builtin_fabs(x); }
double sqrt(double x)  { return __builtin_sqrt(x); }
double floor(double x) { return __builtin_floor(x); }
double ceil(double x)  { return __builtin_ceil(x); }
double round(double x) { return __builtin_round(x); }
double trunc(double x) { return __builtin_trunc(x); }
double fma(double x, double y, double z) { return __builtin_fma(x, y, z); }

/* ── fmod ─────────────────────────────────────────────────────────────────── */

double fmod(double x, double y) {
#ifdef ARCH_ARM64
    if (y == 0.0) return __builtin_nan("");
    double q = trunc(x / y);
    return x - q * y;
#else
    double r;
    __asm__ volatile (
        "1: fprem\n\t"
        "fnstsw %%ax\n\t"
        "testb $4, %%ah\n\t"
        "jnz 1b\n\t"
        "fstp %%st(1)"
        : "=t"(r) : "0"(x), "u"(y) : "ax"
    );
    return r;
#endif
}

/* ── ldexp / frexp — bit-manipulation on both arches ─────────────────────── */

double ldexp(double x, int n) {
#ifdef ARCH_ARM64
    if (x == 0.0 || n == 0) return x;
    union { double d; uint64_t u; } u = { x };
    int e = (int)((u.u >> 52) & 0x7FF);
    e += n;
    if (e >= 0x7FF) return x > 0 ? __builtin_huge_val() : -__builtin_huge_val();
    if (e <= 0)     return 0.0;
    u.u = (u.u & ~(0x7FFULL << 52)) | ((uint64_t)e << 52);
    return u.d;
#else
    double r;
    double e = (double)n;
    __asm__ ("fscale; fstp %%st(1)" : "=t"(r) : "0"(x), "u"(e));
    return r;
#endif
}

double frexp(double x, int *exp) {
    if (x == 0.0) { *exp = 0; return 0.0; }
    union { double d; uint64_t u; } u = { x };
    int e = (int)((u.u >> 52) & 0x7FF) - 1022;
    *exp = e;
    /* set exponent to 1022 → mantissa in [0.5, 1) */
    u.u = (u.u & ~(0x7FFULL << 52)) | (1022ULL << 52);
    return u.d;
}

double modf(double x, double *ipart) {
    *ipart = x >= 0 ? floor(x) : ceil(x);
    return x - *ipart;
}

double copysign(double x, double y) {
    return (y < 0) ? -fabs(x) : fabs(x);
}

double nextafter(double x, double y) {
    if (x == y) return y;
    union { double d; uint64_t u; } u = {x};
    if (x == 0.0) { u.u = 1; return (y > 0) ? u.d : -u.d; }
    if ((x < y) == (x > 0)) u.u++; else u.u--;
    return u.d;
}

/* ── Transcendentals ─────────────────────────────────────────────────────── */

#ifdef ARCH_ARM64

/* log: log(x) = e*ln2 + log(m), m in [1,2) via atanh series */
double log(double x) {
    if (x <= 0.0) return x == 0.0 ? -__builtin_huge_val() : __builtin_nan("");
    union { double d; uint64_t u; } u = { x };
    int e = (int)((u.u >> 52) & 0x7FF) - 1023;
    u.u = (u.u & ~(0x7FFULL << 52)) | (1023ULL << 52);
    double m = u.d;  /* m in [1, 2) */
    double y = (m - 1.0) / (m + 1.0);
    double y2 = y * y;
    /* atanh(y) = y*(1 + y²/3 + y⁴/5 + y⁶/7 + y⁸/9 + y¹⁰/11) */
    double s = y * (1.0 + y2 * (1.0/3.0 + y2 * (1.0/5.0 + y2 *
               (1.0/7.0 + y2 * (1.0/9.0 + y2 * (1.0/11.0))))));
    return 2.0 * s + e * 0.6931471805599453094; /* e * ln(2) */
}

double log2(double x)  { return log(x) / 0.6931471805599453094; }
double log10(double x) { return log(x) / 2.302585092994045684; }

/* exp: exp(x) = 2^k * exp(r), k = round(x/ln2), r = x - k*ln2 */
double exp(double x) {
    if (x > 709.0)  return __builtin_huge_val();
    if (x < -745.0) return 0.0;
    static const double LN2 = 0.6931471805599453094;
    int k = (int)(x / LN2 + (x >= 0 ? 0.5 : -0.5));
    double r = x - k * LN2;
    /* Taylor series for exp(r), r small: 1 + r + r²/2! + r³/3! + ... */
    double r2 = r * r;
    double p = 1.0 + r + r2 * (0.5 + r * (1.0/6.0 + r * (1.0/24.0 + r *
               (1.0/120.0 + r * (1.0/720.0 + r * (1.0/5040.0 +
                r * (1.0/40320.0 + r / 362880.0)))))));
    return ldexp(p, k);
}

double exp2(double x) { return exp(x * 0.6931471805599453094); }

/* sin/cos via range reduction + Taylor series */
static double _sin_reduced(double x) {
    /* x in [-π/4, π/4] */
    double x2 = x * x;
    return x * (1.0 + x2 * (-1.0/6.0 + x2 * (1.0/120.0 + x2 *
           (-1.0/5040.0 + x2 * (1.0/362880.0 - x2/39916800.0)))));
}
static double _cos_reduced(double x) {
    double x2 = x * x;
    return 1.0 + x2 * (-0.5 + x2 * (1.0/24.0 + x2 *
           (-1.0/720.0 + x2 * (1.0/40320.0 - x2/3628800.0))));
}

static const double PI   = 3.14159265358979323846;
static const double PI_2 = 1.57079632679489661923;
static const double PI_4 = 0.78539816339744830962;

double sin(double x) {
    /* Range-reduce to [-π, π] */
    x = x - (long long)(x / PI + (x >= 0 ? 0.5 : -0.5)) * 2.0 * PI;
    /* Now x in (-π, π]; reduce to [-π/2, π/2] */
    int flip = 0;
    if (x > PI_2)  { x = PI - x;   }
    else if (x < -PI_2) { x = -PI - x; flip = 1; }
    /* Further reduce to [-π/4, π/4] using sin(x) = cos(π/2 - x) */
    double r;
    if (x > PI_4)       r = _cos_reduced(PI_2 - x);
    else if (x < -PI_4) r = -_cos_reduced(PI_2 + x);
    else                 r = _sin_reduced(x);
    return flip ? -r : r;
}

double cos(double x) {
    x = x - (long long)(x / PI + (x >= 0 ? 0.5 : -0.5)) * 2.0 * PI;
    int flip = 0;
    if (x > PI_2)  { x = PI - x;  flip = 1; }
    else if (x < -PI_2) { x = -PI - x; flip = 1; }
    double r;
    if (x > PI_4)       r = _sin_reduced(PI_2 - x);
    else if (x < -PI_4) r = _sin_reduced(PI_2 + x);
    else                 r = _cos_reduced(x);
    return flip ? -r : r;
}

double tan(double x) {
    double c = cos(x);
    if (c == 0.0) return __builtin_huge_val();
    return sin(x) / c;
}

/* atan via minimax polynomial on [0,1], then range reduction */
double atan(double x) {
    int neg = (x < 0); if (neg) x = -x;
    int recip = (x > 1.0);
    if (recip) x = 1.0 / x;
    double x2 = x * x;
    double r = x * (1.0 + x2 * (-1.0/3.0 + x2 * (1.0/5.0 + x2 *
               (-1.0/7.0 + x2 * (1.0/9.0 + x2 * (-1.0/11.0 +
                x2 * (1.0/13.0 + x2 * (-1.0/15.0 + x2/17.0))))))));
    if (recip) r = PI_2 - r;
    return neg ? -r : r;
}

double atan2(double y, double x) {
    if (x > 0)  return atan(y / x);
    if (x < 0)  return atan(y / x) + (y >= 0 ? PI : -PI);
    if (y > 0)  return PI_2;
    if (y < 0)  return -PI_2;
    return 0.0;
}

#else /* x86-64: use x87 hardware */

double sin(double x) {
    double r;
    __asm__ ("fsin" : "=t"(r) : "0"(x));
    return r;
}

double cos(double x) {
    double r;
    __asm__ ("fcos" : "=t"(r) : "0"(x));
    return r;
}

double tan(double x) {
    double r, one;
    __asm__ ("fptan" : "=t"(one), "=u"(r) : "0"(x));
    (void)one;
    return r;
}

double atan(double x) {
    double r;
    __asm__ ("fld1; fpatan" : "=t"(r) : "0"(x));
    return r;
}

double atan2(double y, double x) {
    double r;
    __asm__ ("fpatan" : "=t"(r) : "0"(x), "u"(y));
    return r;
}

double log2(double x) {
    double r;
    __asm__ ("fld1; fxch; fyl2x" : "=t"(r) : "0"(x));
    return r;
}

double log(double x) {
    double r;
    __asm__ ("fldln2; fxch; fyl2x" : "=t"(r) : "0"(x));
    return r;
}

double log10(double x) {
    double r;
    __asm__ ("fldlg2; fxch; fyl2x" : "=t"(r) : "0"(x));
    return r;
}

double exp(double x) {
    double r, i, f;
    __asm__ ("fldl2e; fmulp" : "=t"(r) : "0"(x));
    i = floor(r);
    f = r - i;
    __asm__ ("f2xm1" : "=t"(f) : "0"(f));
    f += 1.0;
    __asm__ ("fscale; fstp %%st(1)" : "=t"(r) : "0"(f), "u"(i));
    return r;
}

double exp2(double x) {
    double i = floor(x), f = x - i;
    double r;
    __asm__ ("f2xm1" : "=t"(f) : "0"(f));
    f += 1.0;
    __asm__ ("fscale; fstp %%st(1)" : "=t"(r) : "0"(f), "u"(i));
    return r;
}

#endif /* ARCH_ARM64 */

/* ── Higher-level functions (arch-independent) ───────────────────────────── */

double pow(double x, double y) {
    if (y == 0.0)  return 1.0;
    if (x == 0.0)  return 0.0;
    if (x < 0.0 && y != (long long)y) return __builtin_nan("");
    int neg = 0;
    if (x < 0.0) { x = -x; neg = (long long)y & 1; }
    double r = exp(y * log(x));
    return neg ? -r : r;
}

double hypot(double x, double y) { return sqrt(x * x + y * y); }

double expm1(double x) {
    if (fabs(x) < 1e-5)
        return x + x*x/2.0 + x*x*x/6.0 + x*x*x*x/24.0;
    return exp(x) - 1.0;
}

double log1p(double x) {
    if (fabs(x) < 1e-5)
        return x - x*x/2.0 + x*x*x/3.0 - x*x*x*x/4.0;
    return log(1.0 + x);
}

double cbrt(double x) {
    if (x == 0.0) return 0.0;
    double r = pow(fabs(x), 1.0 / 3.0);
    return x < 0.0 ? -r : r;
}

double acosh(double x) { return log(x + sqrt(x*x - 1.0)); }
double asinh(double x) { return log(x + sqrt(x*x + 1.0)); }
double atanh(double x) { return 0.5 * log((1.0 + x) / (1.0 - x)); }

double asin(double x) { return atan2(x, sqrt(1 - x * x)); }
double acos(double x) { return atan2(sqrt(1 - x * x), x); }
double sinh(double x) { return (exp(x) - exp(-x)) / 2; }
double cosh(double x) { return (exp(x) + exp(-x)) / 2; }
double tanh(double x) { double e = exp(2 * x); return (e - 1) / (e + 1); }

double tgamma(double x) {
    static const double c[] = {
        0.99999999999980993, 676.5203681218851, -1259.1392167224028,
        771.32342877765313, -176.61502916214059, 12.507343278686905,
        -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7
    };
    if (x < 0.5) return 3.14159265358979323846 / (sin(3.14159265358979323846 * x) * tgamma(1 - x));
    x -= 1;
    double a = c[0];
    double t = x + 7.5;
    for (int i = 1; i < 9; i++) a += c[i] / (x + i);
    return sqrt(2 * 3.14159265358979323846) * pow(t, x + 0.5) * exp(-t) * a;
}

double lgamma(double x) { return log(fabs(tgamma(x))); }

double erf(double x) {
    double t = 1.0 / (1.0 + 0.3275911 * fabs(x));
    double y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t
                        - 0.284496736) * t + 0.254829592) * t * exp(-x * x);
    return (x >= 0) ? y : -y;
}

double erfc(double x) { return 1.0 - erf(x); }

/* ── strtod ────────────────────────────────────────────────────────────────── */

double strtod(const char *s, char **end) {
    while (isspace(*s)) s++;

    int neg = 0;
    if (*s == '-') { neg = 1; s++; }
    else if (*s == '+') s++;

    if (strncasecmp(s, "inf", 3) == 0) {
        if (end) *end = (char *)s + 3;
        if (strncasecmp(s + 3, "inity", 5) == 0 && end) *end = (char *)s + 8;
        return neg ? -__builtin_huge_val() : __builtin_huge_val();
    }
    if (strncasecmp(s, "nan", 3) == 0) {
        if (end) *end = (char *)s + 3;
        return __builtin_nan("");
    }

    int is_hex = 0;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        is_hex = 1;
        s += 2;
    }

    double val = 0.0, frac = 0.0, scale = 1.0;
    int has_digits = 0;
    int base = is_hex ? 16 : 10;

    while (*s) {
        int d;
        if (*s >= '0' && *s <= '9')      d = *s - '0';
        else if (is_hex && *s >= 'a' && *s <= 'f') d = *s - 'a' + 10;
        else if (is_hex && *s >= 'A' && *s <= 'F') d = *s - 'A' + 10;
        else break;
        val = val * base + d;
        has_digits = 1;
        s++;
    }

    if (*s == '.') {
        s++;
        while (*s) {
            int d;
            if (*s >= '0' && *s <= '9')      d = *s - '0';
            else if (is_hex && *s >= 'a' && *s <= 'f') d = *s - 'a' + 10;
            else if (is_hex && *s >= 'A' && *s <= 'F') d = *s - 'A' + 10;
            else break;
            scale /= base;
            frac += d * scale;
            has_digits = 1;
            s++;
        }
    }

    val += frac;
    if (!has_digits) { if (end) *end = (char *)s; return 0.0; }

    if ((!is_hex && (*s == 'e' || *s == 'E')) ||
        ( is_hex && (*s == 'p' || *s == 'P'))) {
        s++;
        int eneg = 0;
        if (*s == '-') { eneg = 1; s++; }
        else if (*s == '+') s++;
        long exp_val = 0;
        while (*s >= '0' && *s <= '9') exp_val = exp_val * 10 + (*s++ - '0');
        double mult = is_hex ? exp((double)exp_val * 0.693147180559945)
                             : pow(10.0, (double)exp_val);
        val = eneg ? val / mult : val * mult;
    }

    if (end) *end = (char *)s;
    return neg ? -val : val;
}

float strtof(const char *s, char **end) {
    return (float)strtod(s, end);
}
