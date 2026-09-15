#!/usr/bin/env python3
"""Inspect the native control plane of a RubyOS QEMU session."""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time


def load_session(path: str) -> dict:
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def qmp(path: str, command: str) -> dict:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(4)
    client.connect(path)
    pending = b""

    def receive() -> dict:
        nonlocal pending
        while b"\n" not in pending:
            chunk = client.recv(4096)
            if not chunk:
                raise ConnectionError("QMP closed the control socket")
            pending += chunk
        line, pending = pending.split(b"\n", 1)
        return json.loads(line)

    receive()
    client.sendall(b'{"execute":"qmp_capabilities"}\n')
    receive()
    client.sendall(json.dumps({"execute": command}).encode() + b"\n")
    try:
        while True:
            response = receive()
            if "return" in response or "error" in response:
                return response
    finally:
        client.close()


def native_probe(endpoint: str) -> str:
    host, port = endpoint.rsplit(":", 1)
    with socket.create_connection((host, int(port)), timeout=4) as client:
        client.settimeout(4)
        client.sendall(b"$?#3f")
        response = bytearray()
        deadline = time.monotonic() + 4
        while b"$" not in response and time.monotonic() < deadline:
            response.extend(client.recv(4096))
    if b"$" not in response:
        raise ConnectionError("native debug endpoint did not speak the GDB remote protocol")
    return response.decode("ascii", errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", default="build/rubyos-debug.json")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("session", help="print all recorded debug endpoints")
    serial = commands.add_parser("serial", help="print recent guest serial output")
    serial.add_argument("--lines", type=int, default=120)
    control = commands.add_parser("qmp", help="query or control QEMU")
    control.add_argument("action", choices=("status", "stop", "cont", "reset"))
    native = commands.add_parser("native", help="probe or attach to QEMU's native debugger")
    native.add_argument("commands", nargs=argparse.REMAINDER)
    commands.add_parser("capture", help="print the desktop capture path")
    args = parser.parse_args()

    try:
        session = load_session(args.session)
        if args.command == "session":
            print(json.dumps(session, indent=2, sort_keys=True))
        elif args.command == "serial":
            with open(session["serial_log"], encoding="utf-8", errors="replace") as stream:
                print("".join(stream.readlines()[-args.lines:]), end="")
        elif args.command == "qmp":
            operation = {"status": "query-status", "stop": "stop",
                         "cont": "cont", "reset": "system_reset"}[args.action]
            print(json.dumps(qmp(session["qmp"], operation), indent=2, sort_keys=True))
        elif args.command == "capture":
            capture = session["capture"]
            if not os.path.exists(capture):
                raise FileNotFoundError(capture)
            print(capture)
        elif args.commands:
            debugger = os.environ.get("RUBYOS_GDB", "gdb")
            command = [debugger, "-q", session["symbols"], "-ex", "set pagination off",
                       "-ex", "target remote " + session["native_remote"]]
            for statement in args.commands:
                if statement != "--":
                    command += ["-ex", statement]
            return subprocess.call(command)
        else:
            print(native_probe(session["native_remote"]))
        return 0
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as error:
        print(f"rubyos-debug: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
