#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^RUBY_VERSION := //p' "$root/config/ruby.mk")"
source_dir="$root/build/ruby-build/ruby-$version"
host_build="$root/build/baremetal/host-ruby-build"
host_prefix="$root/build/baremetal/host-ruby"
target_build="$root/build/baremetal/ruby-freestanding"
jobs="${RUBYOS_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
test -x "$source_dir/configure" || { echo "Run 'make ruby' first." >&2; exit 1; }
if [[ ! -x "$host_prefix/bin/ruby" ]]; then
    mkdir -p "$host_build"; cd "$host_build"
    "$source_dir/configure" --prefix="$host_prefix" --disable-install-doc \
        --disable-shared --disable-yjit --disable-zjit --without-gmp
    make -j"$jobs"; make install
fi
mkdir -p "$target_build"; cd "$target_build"
if [[ ! -f Makefile ]]; then
    CFLAGS="-O2 -ffreestanding -fno-stack-protector -fno-pie -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0" \
    "$source_dir/configure" --build=aarch64-unknown-linux-gnu --host=aarch64-unknown-none \
        --with-baseruby="$host_prefix/bin/ruby" --disable-shared \
        --disable-install-doc --disable-rubygems --disable-yjit --disable-zjit \
        --without-gmp --with-coroutine=arm64 --with-out-ext=all \
        CC=aarch64-elf-gcc AR=aarch64-elf-ar RANLIB=aarch64-elf-ranlib \
        rb_cv_stack_end_address=no ac_cv_func_pthread_getattr_np=no \
        ac_cv_func_backtrace=no ac_cv_func_fork=no ac_cv_func_vfork=no \
        ac_cv_func_dlopen=no ac_cv_func_dladdr=no ac_cv_func_sigaltstack=no \
        ac_cv_func_getgrnam_r=no ac_cv_func_getpwnam_r=no \
        ac_cv_func_getpwuid_r=no ac_cv_func_initgroups=no \
        ac_cv_func_getgroups=no ac_cv_func_setgroups=no ac_cv_func_getlogin_r=no
fi
if [[ ! -f .rubyos-configured ]]; then
    config=.ext/include/aarch64-none/ruby/config.h
    disabled=(USE_ELF HAVE_SYS_PRCTL_H HAVE_SYS_EPOLL_H HAVE_SYS_EVENTFD_H
        HAVE_MALLOC_H HAVE_MALLOC_USABLE_SIZE HAVE_MALLOC_TRIM
        HAVE_PTHREAD_SETNAME_NP HAVE_PTHREAD_SIGMASK HAVE_PTHREAD_KILL
        HAVE_POSIX_FADVISE HAVE_PREAD HAVE_PWRITE HAVE_WRITEV HAVE_PIPE2
        HAVE_PPOLL HAVE_SELECT HAVE_FLOCK HAVE_FTRUNCATE HAVE_FDATASYNC
        HAVE_FSYNC HAVE_FCHOWN HAVE_MKFIFO HAVE_TRUNCATE HAVE_UTIMENSAT
        HAVE_UTIMES HAVE_LUTIMES HAVE_LCHOWN HAVE_LCHMOD HAVE_CHOWN
        HAVE_CHMOD HAVE_SYMLINK HAVE_LINK HAVE_EACCESS HAVE_READLINK
        HAVE_FSTATAT HAVE_OPENAT HAVE_DIRFD HAVE_SEEKDIR HAVE_TELLDIR
        HAVE_FCHDIR HAVE_CHROOT HAVE_DUP3 HAVE_SHUTDOWN HAVE_FREOPEN HAVE_SETVBUF)
    disabled+=(HAVE_SETGROUPS)
    for macro in "${disabled[@]}"; do
        sed -i "s/^#define $macro 1$/#undef $macro/" "$config"
    done
    sed -i -e 's@ ${LIBOBJDIR}addr2line.o@@' -e 's@ ${LIBOBJDIR}memcmp.o@@' Makefile
    touch .rubyos-configured
fi
config=.ext/include/aarch64-none/ruby/config.h
for macro in HAVE_COPY_FILE_RANGE HAVE_CRYPT_R HAVE_EVENTFD HAVE_EXECL HAVE_EXECLE \
    HAVE_EXECV HAVE_EXECVE HAVE_MREMAP HAVE_SENDFILE HAVE_SETGROUPS HAVE_SYSTEM \
    HAVE_WAITPID; do
    sed -i "s/^#define $macro 1$/#undef $macro/" "$config"
done
make -j"$jobs" hardenflags= optflags=-O2 \
    XCFLAGS='-fno-strict-overflow -fvisibility=hidden -fexcess-precision=standard -DRUBY_EXPORT -fno-pie $(INCFLAGS)' \
    libruby-static.a
test -s libruby-static.a
touch .rubyos-built
echo "freestanding ARM64 CRuby archive: $target_build/libruby-static.a"
