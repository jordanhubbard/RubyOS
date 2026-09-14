/* sys/types.h — bare-metal POSIX type stubs for PythonOS.
 *
 * Sets the glibc __xxx_defined guards so system headers (sys/mman.h etc.)
 * don't try to redefine these types from their own typedef chains.
 */
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifndef __dev_t_defined
typedef unsigned long  dev_t;
# define __dev_t_defined
#endif

#ifndef __ino_t_defined
typedef unsigned long  ino_t;
# define __ino_t_defined
#endif

#ifndef __off_t_defined
typedef long           off_t;
# define __off_t_defined
#endif

#ifndef __mode_t_defined
typedef unsigned int   mode_t;
# define __mode_t_defined
#endif

#ifndef __uid_t_defined
typedef unsigned int   uid_t;
# define __uid_t_defined
#endif

#ifndef __gid_t_defined
typedef unsigned int   gid_t;
# define __gid_t_defined
#endif

#ifndef __pid_t_defined
typedef int            pid_t;
# define __pid_t_defined
#endif

#ifndef __nlink_t_defined
typedef unsigned long  nlink_t;
# define __nlink_t_defined
#endif

#ifndef __blksize_t_defined
typedef long           blksize_t;
# define __blksize_t_defined
#endif

#ifndef __blkcnt_t_defined
typedef long           blkcnt_t;
# define __blkcnt_t_defined
#endif

#ifndef __ssize_t_defined
typedef long           ssize_t;
# define __ssize_t_defined
#endif
