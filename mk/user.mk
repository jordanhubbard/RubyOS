# Small public interface; the top-level Makefile retains the specialist probes.
TARGET_ARCH ?= arm64
ifneq ($(TARGET_ARCH),arm64)
$(error Friendly entry points currently use TARGET_ARCH=arm64; use explicit rubyos-x86_64 targets for x86 experiments)
endif

.PHONY: help build build-gui run run-gui start stop restart test-host test-chipset test-gui package cleanall ensure-builder disk-image
build: $(ARM64_REPL_ELF)
build-gui: build/baremetal/rubyos-arm64-desktop/rubyos.elf bridge
run: build
	$(HOST_RUBY) tools/run.rb console
run-gui: build-gui
	$(HOST_RUBY) tools/run.rb gui
start: run
stop:
	@if test -x "$(HOST_RUBY)"; then $(HOST_RUBY) tools/run.rb stop; else echo "RubyOS is not running"; fi
restart: stop
	$(MAKE) run
test: test-host rubyos-arm64-repl-smoke
test-chipset: test-host
test-gui: rubyos-arm64-tcp-gui-smoke
package: release
cleanall: distclean
disk-image: disk

.PHONY: test-user-commands
test-user-commands: build build-gui
	python3 test/user_commands_test.py

help:
	@echo "RubyOS — everyday commands (ARM64 guest on Linux/macOS hosts)"
	@echo "  make / make build   Build the bootable Ruby console"
	@echo "  make run            Boot the console in QEMU (Ctrl-C to stop)"
	@echo "  make build-gui      Build the desktop and shared SDL service"
	@echo "  make run-gui        Open a persistent native-TCP SDL desktop"
	@echo "  make stop           Stop only this checkout's supervised session"
	@echo "  make restart        Stop, then run the console; start aliases run"
	@echo "  make test           Hosted tests plus bare-metal console smoke"
	@echo "  make test-gui       Headless native-TCP desktop smoke"
	@echo "  make test-host      Fast hosted kernel tests (test-chipset alias)"
	@echo "  make package        Validate and package locally; never publish"
	@echo "  make clean          Remove guest artifacts; preserve source-built Ruby"
	@echo "  make cleanall       Also remove private Ruby builds and source archive"
	@echo "  make docker-build   Rebuild the ARM64 cross-toolchain container"
	@echo "Advanced architecture/probe targets: docs/build-targets.md."

ensure-builder:
	@docker image inspect $(BUILDER_IMAGE) >/dev/null 2>&1 || $(MAKE) docker-build

$(ARM64_ELF) $(ARM64_RUBY_STAMP) $(X86_64_RUBY_STAMP): | ensure-builder

build/baremetal/rubyos-arm64-desktop/rubyos.elf: $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh tools/embed-kernel.rb $(shell find kernel baremetal/arm64 platform -type f)
	docker run --rm --platform linux/arm64 --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_INTERACTIVE_DESKTOP=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-desktop ./tools/build-rubyos-arm64.sh
