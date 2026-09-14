/* termios.h — bare-metal stub for PythonOS.
 *
 * Provides the type and macro layout that linenoise (src/linenoise/) and
 * any other terminal-aware C code needs to compile, plus stub
 * tcgetattr/tcsetattr that succeed without changing the wire (we control
 * the serial / TCP REPL framing elsewhere). */
#pragma once

#include <stdint.h>

typedef unsigned int tcflag_t;
typedef unsigned char cc_t;
typedef int speed_t;

#define NCCS 32

struct termios {
    tcflag_t c_iflag;
    tcflag_t c_oflag;
    tcflag_t c_cflag;
    tcflag_t c_lflag;
    cc_t     c_cc[NCCS];
};

/* c_iflag bits */
#define IGNBRK  0x0001
#define BRKINT  0x0002
#define PARMRK  0x0004
#define ISTRIP  0x0008
#define INLCR   0x0010
#define IGNCR   0x0020
#define ICRNL   0x0040
#define IXON    0x0080
#define INPCK   0x0100

/* c_oflag bits */
#define OPOST   0x0001

/* c_cflag bits */
#define CSIZE   0x0030
#define CS8     0x0030
#define PARENB  0x0040

/* c_lflag bits */
#define ECHO    0x0001
#define ECHONL  0x0002
#define ICANON  0x0004
#define ISIG    0x0008
#define IEXTEN  0x0010

/* c_cc indices */
#define VMIN    6
#define VTIME   5

/* tcsetattr action */
#define TCSANOW   0
#define TCSADRAIN 1
#define TCSAFLUSH 2

int tcgetattr(int fd, struct termios *t);
int tcsetattr(int fd, int act, const struct termios *t);
