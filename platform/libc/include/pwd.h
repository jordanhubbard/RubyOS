/*
 * pwd.h — bare-metal stub for PythonOS.
 * Provides struct passwd so pwdmodule.c compiles; all lookups return NULL.
 */
#pragma once

#include <stdint.h>

struct passwd {
    char  *pw_name;
    char  *pw_passwd;
    unsigned int pw_uid;
    unsigned int pw_gid;
    char  *pw_gecos;
    char  *pw_dir;
    char  *pw_shell;
};

struct passwd *getpwuid(unsigned int uid);
struct passwd *getpwnam(const char *name);
int getpwuid_r(unsigned int uid, struct passwd *pwd, char *buf, size_t buflen, struct passwd **result);
int getpwnam_r(const char *name, struct passwd *pwd, char *buf, size_t buflen, struct passwd **result);
struct passwd *getpwent(void);
void setpwent(void);
void endpwent(void);
