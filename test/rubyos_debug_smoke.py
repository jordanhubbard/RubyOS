#!/usr/bin/env python3
"""Prove RubyOS serial, QMP, native-debug, capture, and metrics planes together."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import time


ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
SERIAL = BUILD / "rubyos-debug-serial.log"
BRIDGE_LOG = BUILD / "rubyos-debug-bridge.log"
MANIFEST = BUILD / "rubyos-debug.json"
QMP = BUILD / "rubyos-debug-qmp.sock"
CAPTURE = Path("/tmp/rubyos-baremetal-desktop.bmp")


def free_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def wait_for(path: Path, text: str, timeout: float = 35) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists() and text in path.read_text(errors="replace"):
            return
        time.sleep(0.05)
    raise TimeoutError(f"timed out waiting for {text!r} in {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hold", action="store_true",
                        help="keep the verified VM alive for rubyos_debug.py")
    args = parser.parse_args()
    bridge_port, gdb_port = free_port(), free_port()
    for path in (SERIAL, BRIDGE_LOG, MANIFEST, QMP, CAPTURE):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    environment = dict(os.environ, RUBYOS_DESKTOP_MODE="headless",
                       SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    with BRIDGE_LOG.open("wb") as bridge_output:
        bridge = subprocess.Popen(
            [str(ROOT / "bridge/rubyos_bridge"), "--listen-tcp",
             f"127.0.0.1:{bridge_port}"], env=environment,
            stdout=bridge_output, stderr=subprocess.STDOUT)
    qemu = None
    try:
        wait_for(BRIDGE_LOG, "listening on tcp", 5)
        qemu = subprocess.Popen([
            "qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a72",
            "-m", "512M", "-display", "none", "-monitor", "none",
            "-serial", f"file:{SERIAL}", "-no-reboot",
            "-qmp", f"unix:{QMP},server=on,wait=off",
            "-gdb", f"tcp:127.0.0.1:{gdb_port}",
            "-device", "virtio-serial-device",
            "-chardev", f"socket,id=rubyos_bridge,host=127.0.0.1,port={bridge_port}",
            "-device", "virtconsole,chardev=rubyos_bridge",
            "-kernel", str(BUILD / "baremetal/rubyos-arm64-gui/rubyos.elf")
        ], stdin=subprocess.DEVNULL)
        manifest = {
            "architecture": "arm64",
            "capture": str(CAPTURE),
            "desktop_co_process": {"log": str(BRIDGE_LOG), "pid": bridge.pid},
            "native_remote": f"127.0.0.1:{gdb_port}",
            "qemu_pid": qemu.pid,
            "qmp": str(QMP),
            "serial_log": str(SERIAL),
            "symbols": str(BUILD / "baremetal/rubyos-arm64-gui/rubyos.elf")
        }
        MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        wait_for(SERIAL, "guest/host performance metrics: PASS")
        serial = SERIAL.read_text(errors="replace")
        if any(marker in serial for marker in ("FATAL", "EXCEPTION", "ASSERT", "[BUG]")):
            raise RuntimeError("fatal marker in RubyOS debug serial log")
        if not CAPTURE.exists() or CAPTURE.stat().st_size == 0:
            raise RuntimeError("RubyOS debug capture is empty")

        tool = [str(ROOT / "tools/rubyos_debug.py"), "--session", str(MANIFEST)]
        status = subprocess.check_output(tool + ["qmp", "status"], text=True)
        if "running" not in status:
            raise RuntimeError("QMP did not report a running RubyOS VM")
        probe = subprocess.check_output(tool + ["native"], text=True)
        if "$" not in probe:
            raise RuntimeError("native debugger probe failed")
        capture = subprocess.check_output(tool + ["capture"], text=True).strip()
        if capture != str(CAPTURE):
            raise RuntimeError("debug capture path changed")
        print("RubyOS unified native debug and automation smoke: PASS")
        if args.hold:
            print(f"RubyOS debug session is live: {MANIFEST}", flush=True)
            while qemu.poll() is None:
                time.sleep(0.5)
        return 0
    finally:
        if qemu is not None and qemu.poll() is None:
            qemu.terminate()
            try:
                qemu.wait(timeout=3)
            except subprocess.TimeoutExpired:
                qemu.kill()
                qemu.wait()
        if bridge.poll() is None:
            bridge.terminate()
        try:
            bridge.wait(timeout=3)
        except subprocess.TimeoutExpired:
            bridge.kill()
            bridge.wait()


if __name__ == "__main__":
    raise SystemExit(main())
