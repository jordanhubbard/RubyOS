#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
for lesson in storage network graphics audio internals; do
    output="$($root/build/host-ruby/bin/ruby -I "$root/kernel" "$root/examples/$lesson.rb")"
    printf '%s\n' "$output"
    grep -q "$lesson lesson: PASS" <<<"$output"
done
echo 'RubyOS teaching examples: PASS'
