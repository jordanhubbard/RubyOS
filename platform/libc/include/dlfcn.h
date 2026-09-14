/* dlfcn.h — bare-metal stub for PythonOS. No dynamic loading. */
#pragma once

#define RTLD_LAZY   1
#define RTLD_NOW    2
#define RTLD_GLOBAL 0x100
#define RTLD_LOCAL  0

void *dlopen(const char *file, int mode);
void *dlsym(void *handle, const char *sym);
int   dlclose(void *handle);
char *dlerror(void);
