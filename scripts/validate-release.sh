#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
platform="${RUBYOS_VALIDATE_PLATFORM:-}"
if [[ -z "$platform" ]]; then
    case "$(uname -s)" in Darwin) platform=macos ;; Linux) platform=linux ;; *) exit 2 ;; esac
fi
case "$platform" in macos|linux) ;; *) echo "invalid platform: $platform" >&2; exit 2 ;; esac

printf '[validate] checking Ruby and Python syntax\n'
make ruby
build/host-ruby/bin/ruby -c kernel/rubyos.rb
python3 -m py_compile tools/rubyos_debug.py test/rubyos_debug_smoke.py
git diff --check

printf '[validate] running %s build and release targets\n' "$platform"
make "release-$platform"

version="$(sed -n 's/^  VERSION = "\([^"]*\)"/\1/p' kernel/rubyos.rb)"
archive="$(find dist -maxdepth 1 -name "rubyos-${version}-${platform}-*.tar.gz" -print -quit)"
[[ -n "$archive" && -s "$archive" ]] || { echo "release archive missing" >&2; exit 1; }
[[ -s "$archive.sha256" ]] || { echo "release checksum missing" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
    (cd dist && sha256sum -c "$(basename "$archive.sha256")")
else
    (cd dist && shasum -a 256 -c "$(basename "$archive.sha256")")
fi
manifest="$(mktemp "${TMPDIR:-/tmp}/rubyos-manifest.XXXXXX")"
extracted="$(mktemp -d "${TMPDIR:-/tmp}/rubyos-extracted.XXXXXX")"
trap 'rm -f "$manifest"; rm -rf "$extracted"' EXIT
tar -tzf "$archive" >"$manifest"
grep -q '/runtime/bin/ruby$' "$manifest"
grep -q '/bin/remoteos-sdl$' "$manifest"
if [[ "$platform" == linux ]]; then
    grep -q '/images/arm64/rubyos-arm64.elf$' "$manifest"
    grep -q '/images/arm64/rubyos-arm64-desktop.elf$' "$manifest"
    grep -q '/images/arm64/rubyos-arm64-tcp-gui.elf$' "$manifest"
    grep -q '/images/arm64/rubyos-arm64-web.elf$' "$manifest"
    grep -q '/images/x86_64/rubyos-x86_64.iso$' "$manifest"
fi
tar -xzf "$archive" -C "$extracted"
bundled_ruby="$(find "$extracted" -path '*/runtime/bin/ruby' -type f -print -quit)"
"$bundled_ruby" --disable=gems -rrbconfig -e '
  abort unless RUBY_ENGINE == "ruby"
  expected = File.realpath(File.expand_path("..", File.dirname(RbConfig.ruby)))
  abort "runtime is not relocatable" unless File.realpath(RbConfig::CONFIG.fetch("prefix")) == expected
'
printf '[validate] release validation passed (%s)\n' "$platform"
