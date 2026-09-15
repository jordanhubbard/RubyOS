#!/usr/bin/env python3
"""Feed serial commands only after the guest shell, never to BIOS/GRUB."""
import os
import selectors
import subprocess
import sys
import time

commands = sys.stdin.buffer.read().splitlines(keepends=True)
process = subprocess.Popen(sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
pending = b""
deadline = time.monotonic() + 60
try:
    while time.monotonic() < deadline:
        for key, _ in selector.select(0.1):
            chunk = os.read(key.fileobj.fileno(), 65536)
            if not chunk:
                raise RuntimeError("guest exited before console test completed")
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            pending += chunk
            if b"rubyos> " in pending:
                pending = pending.split(b"rubyos> ")[-1]
                if not commands:
                    sys.exit(0)
                process.stdin.write(commands.pop(0))
                process.stdin.flush()
        if process.poll() is not None:
            raise RuntimeError("guest exited early")
    raise TimeoutError("console commands did not complete")
finally:
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    selector.close()
