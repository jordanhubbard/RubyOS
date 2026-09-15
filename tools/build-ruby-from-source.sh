#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
make_config="$project_root/config/ruby.mk"

read_make_value() {
    sed -n "s/^$1 := //p" "$make_config"
}

ruby_version="$(read_make_value RUBY_VERSION)"
ruby_series="$(read_make_value RUBY_SERIES)"
ruby_sha256="$(read_make_value RUBY_SHA256)"
ruby_archive="ruby-${ruby_version}.tar.xz"
ruby_url="https://cache.ruby-lang.org/pub/ruby/${ruby_series}/${ruby_archive}"
archive_path="$project_root/deps/$ruby_archive"
source_dir="$project_root/build/ruby-build/ruby-${ruby_version}"
prefix="$project_root/build/host-ruby"

mkdir -p "$project_root/deps" "$project_root/build/ruby-build"

if [[ ! -f "$archive_path" ]]; then
    echo "==> Downloading Ruby ${ruby_version} source"
    curl --fail --location --retry 3 "$ruby_url" --output "$archive_path"
fi

if command -v sha256sum >/dev/null 2>&1; then
    echo "${ruby_sha256}  ${archive_path}" | sha256sum --check --status
else
    actual_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
    [[ "$actual_sha256" == "$ruby_sha256" ]]
fi || {
  echo "Ruby source checksum mismatch: $archive_path" >&2
  exit 1
}

if [[ ! -f "$source_dir/configure" ]]; then
    rm -rf "$source_dir"
    tar -xf "$archive_path" -C "$project_root/build/ruby-build"
fi

mkdir -p "$source_dir/rubyos-build"
cd "$source_dir/rubyos-build"

if [[ ! -f Makefile ]]; then
    ../configure \
        --prefix="$prefix" \
        --disable-install-doc \
        --disable-shared \
        --enable-load-relative \
        --disable-yjit \
        --disable-zjit \
        --without-gmp
fi

jobs="${RUBYOS_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
make -j"$jobs"
make install

RUBYOS_EXPECTED_VERSION="$ruby_version" "$prefix/bin/ruby" --disable=gems -e \
    'abort "wrong Ruby version" unless RUBY_VERSION == ENV.fetch("RUBYOS_EXPECTED_VERSION"); puts "source-built #{RUBY_DESCRIPTION}"'
touch "$prefix/.rubyos-built"
