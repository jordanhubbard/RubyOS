/* assert.h — bare-metal stub. NDEBUG is always set; asserts are no-ops. */
#pragma once
#ifndef assert
#  ifdef NDEBUG
#    define assert(expr) ((void)0)
#  else
#    define assert(expr) do { if (!(expr)) __asm__("ud2"); } while(0)
#  endif
#endif
