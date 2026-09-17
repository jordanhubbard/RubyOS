#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
variant=repl
source "$root/test/guest-command.sh"
output_file="$(mktemp /tmp/rubyos-repl-output.XXXXXX)"
input_file="$(mktemp /tmp/rubyos-repl-input.XXXXXX)"
cleanup() {
    rm -f "$output_file" "$input_file"
}
trap cleanup EXIT
printf '1 + 2\nProcess.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) > 0\n[0.49,0.5,1.5,-0.49,-0.5,-1.5].map(&:round) == [0,1,2,0,-1,-2]\nRubyOS::Sound::Waveform.sine(220,duration_ms: 1).frames == 48\ndevices\ntasks\nuptime\nsleep 5\ntime 12:34:56\napps\nexamples\nexamples language\nexamples concurrency\nexample fiber_stream\nexample concurrency/fiber_mailbox\nls /examples\ncat /examples/start_here/README.txt\ncat /home/welcome.txt\nwrite /home/note hello-ruby\ncat /home/note\n' >"$input_file"

set +e
python3 "$root/test/console-session.py" "${guest[@]}" \
    <"$input_file" >"$output_file" 2>&1
status=$?
set -e
if [[ $status -ne 0 && $status -ne 124 ]]; then
    cat "$output_file"
    exit "$status"
fi

cat "$output_file"
grep -q 'RubyOS console -- Ruby is the kernel' "$output_file"
grep -q 'rubyos> 1 + 2' "$output_file"
grep -q '=> 3' "$output_file"
test "$(grep -c '=> true' "$output_file")" -eq 3
grep -q 'COM1: RubyOS::SerialDriver' "$output_file"
grep -q 'ruby-task-0: complete' "$output_file"
grep -Eq '[0-9]+ ms' "$output_file"
grep -q 'slept 5 ms' "$output_file"
grep -q '12:34:56' "$output_file"
grep -q 'demo  Enumerable Lab' "$output_file"
grep -q 'RubyOS learning tracks in /examples:' "$output_file"
grep -q 'enumerable_pipeline' "$output_file"
grep -q 'fiber_mailbox' "$output_file"
grep -q '=> \[1, 2, 4, 8, 16, 32\]' "$output_file"
grep -q '=> \["message-1", "message-2", "message-3"\]' "$output_file"
grep -q 'start_here  language  concurrency' "$output_file"
grep -q 'meet RubyOS and read a small Ruby algorithm' "$output_file"
grep -q 'Welcome to RubyOS. Ruby is the kernel.' "$output_file"
grep -q '10 bytes' "$output_file"
grep -q 'hello-ruby' "$output_file"
! grep -q 'FATAL\|EXCEPTION\|ASSERT\|\[BUG\]' "$output_file"
echo 'RubyOS bare-metal CRuby REPL smoke: PASS'
