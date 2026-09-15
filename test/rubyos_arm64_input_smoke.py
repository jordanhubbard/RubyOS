#!/usr/bin/env python3
import json
import pathlib
import socket
import subprocess
import tempfile
import time


root = pathlib.Path(__file__).resolve().parent.parent
kernel = root / "build/baremetal/rubyos-arm64-input/rubyos.elf"

with tempfile.TemporaryDirectory(prefix="rubyos-arm-input-") as temporary:
    qmp_path = pathlib.Path(temporary) / "qmp.sock"
    serial_path = pathlib.Path(temporary) / "serial.log"
    process = subprocess.Popen([
        "qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a72", "-m", "512M",
        "-display", "none", "-monitor", "none", "-serial", f"file:{serial_path}",
        "-no-reboot", "-kernel", str(kernel), "-device", "virtio-keyboard-device",
        "-device", "virtio-mouse-device",
        "-qmp", f"unix:{qmp_path},server=on,wait=off",
    ])
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if serial_path.exists() and "[RubyOS] native VirtIO input: READY" in serial_path.read_text(errors="replace"):
                break
            time.sleep(0.05)
        else:
            raise RuntimeError("RubyOS did not reach the VirtIO input probe")

        qmp = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        qmp.settimeout(5)
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
        marker = "[RubyOS] native VirtIO input: PASS"
        while time.monotonic() < deadline:
            log = serial_path.read_text(errors="replace")
            if marker in log:
                print(log, end="")
                print("RubyOS native ARM64 VirtIO input smoke: PASS")
                break
            time.sleep(0.05)
        else:
            print(log, end="")
            raise RuntimeError("injected VirtIO key did not reach Ruby input")
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
