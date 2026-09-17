# Small public interface; the top-level Makefile retains the specialist probes.
TARGET_ARCH ?= $(if $(filter aarch64 arm64,$(shell uname -m)),arm64,x86_64)
ifeq ($(filter $(TARGET_ARCH),arm64 x86_64),)
$(error TARGET_ARCH must be arm64 or x86_64)
endif
GUEST_EXTENSION = $(if $(filter arm64,$(TARGET_ARCH)),elf,iso)
PUBLIC_REPL = $(CURDIR)/build/baremetal/rubyos-$(TARGET_ARCH)-repl/rubyos.$(GUEST_EXTENSION)
PUBLIC_DESKTOP = $(CURDIR)/build/baremetal/rubyos-$(TARGET_ARCH)-desktop/rubyos.$(GUEST_EXTENSION)

.PHONY: help install build build-gui run run-gui start stop restart test-host test-chipset test-gui package cleanall ensure-builder disk-image
install:
	./tools/install-host.sh
	@if test "$${RUBYOS_SKIP_DOCKER:-0}" != 1; then $(MAKE) ensure-builder; fi
build: $(PUBLIC_REPL)
build-gui: $(PUBLIC_DESKTOP) bridge
run: build
	RUBYOS_TARGET_ARCH=$(TARGET_ARCH) $(HOST_RUBY) tools/run.rb console
run-gui: build-gui
	RUBYOS_TARGET_ARCH=$(TARGET_ARCH) $(HOST_RUBY) tools/run.rb gui
start: run
stop:
	@if test -x "$(HOST_RUBY)"; then $(HOST_RUBY) tools/run.rb stop; else echo "RubyOS is not running"; fi
restart: stop
	$(MAKE) run
test: test-install test-host rubyos-$(TARGET_ARCH)-repl-smoke
test-chipset: test-host
test-gui: rubyos-$(TARGET_ARCH)-tcp-gui-smoke
package: release
cleanall: distclean
disk-image: disk

.PHONY: test-user-commands
test-user-commands: build build-gui
	RUBYOS_TARGET_ARCH=$(TARGET_ARCH) python3 test/user_commands_test.py

help:
	@echo "RubyOS — everyday commands (guest: $(TARGET_ARCH); override TARGET_ARCH=arm64|x86_64)"
	@echo "  make install        Install host dependencies, submodules, and builder"
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
	@echo "  make docker-build   Rebuild the native-host cross-toolchain container"
	@echo "Advanced architecture/probe targets: docs/build-targets.md."

ensure-builder:
	@$(CONTAINER_ENGINE) image inspect $(BUILDER_IMAGE) >/dev/null 2>&1 || $(MAKE) docker-build

$(ARM64_ELF) $(ARM64_RUBY_STAMP) $(X86_64_RUBY_STAMP): | ensure-builder

$(CURDIR)/build/baremetal/rubyos-arm64-desktop/rubyos.elf: $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh tools/embed-kernel.rb $(shell find kernel baremetal/arm64 platform -type f)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_INTERACTIVE_DESKTOP=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-desktop ./tools/build-rubyos-arm64.sh

# Private variants share one build rule; keep the public interface small.
X86_FEATURE_repl = RUBYOS_EMBED_REPL=1
X86_FEATURE_storage = RUBYOS_EMBED_REPL=1 RUBYOS_EMBED_STORAGE=1
X86_FEATURE_network = RUBYOS_EMBED_NETWORK=1
X86_FEATURE_web = RUBYOS_EMBED_WEB=1
X86_FEATURE_tcp-gui = RUBYOS_EMBED_DESKTOP_TCP=1
X86_FEATURE_desktop = RUBYOS_EMBED_INTERACTIVE_DESKTOP=1
define x86_variant
$(CURDIR)/build/baremetal/rubyos-x86_64-$(1)/rubyos.iso: $(X86_64_RUBY_STAMP) tools/build-rubyos-x86_64.sh tools/embed-kernel.rb $(shell find kernel baremetal/x86_64 platform -type f)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$$$(id -u):$$$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env $(X86_FEATURE_$(1)) RUBYOS_X86_VARIANT=rubyos-x86_64-$(1) ./tools/build-rubyos-x86_64.sh
.PHONY: rubyos-x86_64-$(1) rubyos-x86_64-$(1)-smoke
rubyos-x86_64-$(1): $(CURDIR)/build/baremetal/rubyos-x86_64-$(1)/rubyos.iso
rubyos-x86_64-$(1)-smoke: rubyos-x86_64-$(1) $(if $(filter storage,$(1)),$(DISK_IMAGE)) $(if $(filter tcp-gui,$(1)),bridge)
	RUBYOS_TEST_ARCH=x86_64 ./test/rubyos_arm64_$(subst -,_,$(1))_smoke.sh
endef
$(foreach variant,repl storage network web tcp-gui,$(eval $(call x86_variant,$(variant))))
$(eval $(call x86_variant,desktop))
