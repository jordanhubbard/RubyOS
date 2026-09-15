#!/usr/bin/env python3
import json
import os
import pathlib
import socket
import subprocess
import tempfile
import time


root = pathlib.Path(__file__).resolve().parent.parent
image = root / "build/baremetal/rubyos-x86_64-input/rubyos.iso"

with tempfile.TemporaryDirectory(prefix="rubyos-input-") as temporary:
    qmp_path = pathlib.Path(temporary) / "qmp.sock"
    serial_path = pathlib.Path(temporary) / "serial.log"
    process = subprocess.Popen([
        "qemu-system-x86_64", "-m", "768M", "-cdrom", str(image),
        "-display", "none", "-serial", f"file:{serial_path}",
        "-qmp", f"unix:{qmp_path},server=on,wait=off", "-no-reboot", "-no-shutdown",
    ])
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if serial_path.exists() and "kernel: Ruby owns the machine" in serial_path.read_text(errors="replace"):
                break
            time.sleep(0.05)
        else:
            raise RuntimeError("RubyOS did not reach the native input probe")

        qmp = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        qmp.connect(str(qmp_path))
        stream = qmp.makefile("rwb", buffering=0)
        stream.readline()
        stream.write(json.dumps({"execute": "qmp_capabilities"}).encode() + b"\n")
        stream.readline()
        stream.write(json.dumps({"execute": "send-key", "arguments": {
            "keys": [{"type": "qcode", "data": "r"}], "hold-time": 50
        }}).encode() + b"\n")
        stream.readline()
        stream.write(json.dumps({"execute": "human-monitor-command", "arguments": {
            "command-line": "mouse_move 20 10"
        }}).encode() + b"\n")
        stream.readline()

        deadline = time.monotonic() + 8
        marker = "[RubyOS] native PS/2 input: PASS"
        while time.monotonic() < deadline:
            log = serial_path.read_text(errors="replace")
            if marker in log:
                print(log, end="")
                print("RubyOS native x86_64 PS/2 input smoke: PASS")
                break
            time.sleep(0.05)
        else:
            raise RuntimeError("injected PS/2 key did not reach Ruby input")
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
