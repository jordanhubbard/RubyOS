/* sys/ioctl.h — bare-metal stub for PythonOS. */
#pragma once
#include <stddef.h>

#define TIOCGWINSZ  0x5413
#define FIONREAD    0x541B
#define FIONBIO     0x5421

struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };

int ioctl(int fd, unsigned long req, ...);
