# Advanced build targets

Start with `make help`. The normal interface is `build`, `build-gui`, `run`,
`run-gui`, `stop`, `start`, `restart`, `test`, `test-gui`, `package`, `clean`,
and `cleanall`. Bare `make` means `build`, not a hosted demonstration.
`restart` always starts the console; use `make stop run-gui` sequentially
(not `make -j`) to switch to the desktop.

The friendly targets select the host CPU by default. Set `TARGET_ARCH=arm64`
or `TARGET_ARCH=x86_64` to override it. Both support the console and persistent
native-TCP desktop. Docker builds a native-host Linux toolchain containing
both cross-compilers; no cross-architecture Docker emulation is required.
QEMU and the native SDL service run on the host. macOS's `build-macos` stays
a hosted-only gate and does not silently acquire a Docker requirement.

| Development task | Targets |
| --- | --- |
| Hosted Ruby/kernel | `ruby`, `smoke`, `test-host`, `provenance`, `embed-probe` |
| Language and services | `test-iseq`, `teaching-examples`, `test-ext2`, `test-network`, `test-bridge` |
| Freestanding runtime | `ruby-arm64`, `ruby-x86_64`, `baremetal-smoke` |
| Guest boot/console | `rubyos-{arm64,x86_64}-smoke`, `rubyos-{arm64,x86_64}-repl-smoke` |
| Desktop transports | `rubyos-arm64-gui-smoke` (serial), `rubyos-{arm64,x86_64}-tcp-gui-smoke` |
| Persistence/network/web | `rubyos-{arm64,x86_64}-{storage,network,web}-smoke` |
| Native devices | `rubyos-{arm64,x86_64}-{input,audio,smp}-smoke` (expand braces in your shell) |
| Debugger | `debug-smoke`, `debug-session` |
| Public command lifecycle | `test-user-commands` (console evaluation, persistent GUI, duplicate launch and scoped stop) |
| Full validation | `parity`, `build-linux`, `build-macos`, `validate-release` |
| Local release bundles | `package`, `release`, `release-linux`, `release-macos` |

`test-chipset` aliases the hosted kernel tests. `disk-image` aliases `disk`.
The full parity gate is intentionally separate from a quick everyday test.
Publishing remains an explicitly authorized `scripts/release.sh` operation.

The regular desktop uses its own `rubyos-<architecture>-desktop` image, without injected
test events, synthetic gameplay or automatic shutdown. Smoke-test images keep
their existing deterministic assertions. The runtime launcher is written in
Ruby and uses only this repository's private, source-built Ruby interpreter.
