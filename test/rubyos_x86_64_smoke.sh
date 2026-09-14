#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
timeout 30 qemu-system-x86_64 -m 768M -cdrom "$root/build/baremetal/rubyos-x86_64/rubyos.iso" -display none -serial file:"$log" -no-reboot -no-shutdown || true
grep -Fq '[RubyOS/x86_64] boot: entering CRuby 4.0.6' "$log"
grep -Fq 'kernel: Ruby owns the machine' "$log"
echo 'RubyOS x86_64 CRuby smoke PASS'
