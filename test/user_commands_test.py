#!/usr/bin/env python3
"""Exercise the public interface and checkout-scoped process lifecycle."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
RUBY = str(ROOT / "build/host-ruby/bin/ruby")
ARCH = os.environ.get("RUBYOS_TARGET_ARCH", "arm64")


def make(*targets):
    return subprocess.check_output(["make", f"TARGET_ARCH={ARCH}", *targets], text=True, stderr=subprocess.STDOUT)


def wait_for(process, path, marker):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        text = path.read_text(errors="replace") if path.exists() else ""
        if marker in text:
            return
        if process.poll() is not None:
            raise AssertionError(f"launcher exited early: {text}")
        time.sleep(0.05)
    raise AssertionError(f"missing {marker}: {text}")


assert not (ROOT / "build/run/control.sock").exists(), "stop the existing session before testing"
help_text = make("help")
for target in ("install", "build", "build-gui", "run", "run-gui", "stop", "restart", "test", "package", "cleanall"):
    assert target in help_text, target
extension = "elf" if ARCH == "arm64" else "iso"
assert f"build: {ROOT}/build/baremetal/rubyos-{ARCH}-repl/rubyos.{extension}" in make("-np", "build")
assert "docker " not in make("-n", "build-macos"), "hosted macOS gate gained a Docker dependency"
assert "rm -rf build/ruby-build" not in make("-n", "clean")
assert "rm -rf build/ruby-build" in make("-n", "cleanall")

environment = dict(os.environ, RUBYOS_TARGET_ARCH=ARCH, REMOTEOS_SDL_MODE="headless", SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
unrelated = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)"])
try:
    with tempfile.TemporaryDirectory(prefix="rubyos-user-commands-") as temporary:
        for mode in ("console", "gui"):
            log = Path(temporary) / f"{mode}.log"
            if mode == "gui":
                (ROOT / "build/run/serial.log").unlink(missing_ok=True)
            with log.open("w") as output:
                process = subprocess.Popen([RUBY, "tools/run.rb", mode], stdin=subprocess.PIPE,
                                           stdout=output, stderr=output, env=environment)
                try:
                    if mode == "console":
                        wait_for(process, log, "rubyos>")
                        process.stdin.write(b"1 + 2\n")
                        process.stdin.flush()
                        wait_for(process, log, "=> 3")
                    else:
                        wait_for(process, ROOT / "build/run/serial.log", "interactive desktop: READY")
                        time.sleep(2)
                        assert process.poll() is None, "desktop ran a smoke scene and exited"
                        guest_log = (ROOT / "build/run/serial.log").read_text(errors="replace")
                        assert not any(marker in guest_log for marker in ("FATAL", "EXCEPTION", "[BUG]")), guest_log
                    duplicate = subprocess.run([RUBY, "tools/run.rb", mode], capture_output=True, text=True)
                    assert duplicate.returncode != 0 and "already running" in duplicate.stderr
                    assert "stopped" in make("stop")
                    assert process.wait(timeout=5) == 0
                    assert unrelated.poll() is None, "stop killed an unrelated process"
                    assert not (ROOT / "build/run/control.sock").exists()
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)
        assert "not running" in make("stop")
finally:
    unrelated.terminate()
    unrelated.wait(timeout=5)

with tempfile.TemporaryDirectory(prefix="rubyos-fatal-launcher-") as temporary:
    temporary = Path(temporary)
    fake_qemu = temporary / "qemu"
    fake_service = temporary / "remoteos-sdl"
    fake_qemu.write_text("""#!/usr/bin/env python3
import pathlib
import sys
import time

serial = sys.argv[sys.argv.index("-serial") + 1].removeprefix("file:")
pathlib.Path(serial).write_text("[RubyOS/test] FA" + "TAL: injected failure\\n")
time.sleep(120)
""")
    fake_service.write_text("""#!/usr/bin/env python3
import time
time.sleep(120)
""")
    fake_qemu.chmod(0o755)
    fake_service.chmod(0o755)
    fatal_environment = dict(environment, RUBYOS_QEMU_BIN=str(fake_qemu),
                             REMOTEOS_SDL_BIN=str(fake_service), RUBYOS_REMOTEOS_PORT="17013")
    fatal = subprocess.run([RUBY, "tools/run.rb", "gui"], capture_output=True, text=True,
                           env=fatal_environment, timeout=5)
    assert fatal.returncode != 0, fatal.stdout + fatal.stderr
    assert "guest reported a fatal error" in fatal.stderr, fatal.stderr
    assert not (ROOT / "build/run/control.sock").exists()
print(f"RubyOS public commands and lifecycle ({ARCH}): PASS")
