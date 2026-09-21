include config/ruby.mk
.DEFAULT_GOAL := all

HOST_RUBY := $(CURDIR)/build/host-ruby/bin/ruby
REMOTEOS_SDL_DIR ?= services/remoteos-sdl
export REMOTEOS_SDL_BIN ?= $(abspath $(REMOTEOS_SDL_DIR)/remoteos-sdl)
HOST_RUBY_STAMP := $(CURDIR)/build/host-ruby/.rubyos-built
EMBED_PROBE := $(CURDIR)/build/embed-probe
ARM64_ELF := $(CURDIR)/build/baremetal/arm64/rubyos-arm64.elf
ARM64_RUBY_LIB := $(CURDIR)/build/baremetal/ruby-freestanding/libruby-static.a
ARM64_RUBY_STAMP := $(CURDIR)/build/baremetal/ruby-freestanding/.rubyos-built
X86_64_RUBY_STAMP := $(CURDIR)/build/baremetal/ruby-freestanding-x86_64/.rubyos-built
X86_64_RUBYOS_ISO := $(CURDIR)/build/baremetal/rubyos-x86_64/rubyos.iso
X86_64_INPUT_ISO := $(CURDIR)/build/baremetal/rubyos-x86_64-input/rubyos.iso
X86_64_AUDIO_ISO := $(CURDIR)/build/baremetal/rubyos-x86_64-audio/rubyos.iso
X86_64_SMP_ISO := $(CURDIR)/build/baremetal/rubyos-x86_64-smp/rubyos.iso
ARM64_RUBYOS_ELF := $(CURDIR)/build/baremetal/rubyos-arm64/rubyos.elf
ARM64_GUI_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-gui/rubyos.elf
ARM64_TCP_GUI_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-tcp-gui/rubyos.elf
ARM64_REPL_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-repl/rubyos.elf
ARM64_STORAGE_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-storage/rubyos.elf
ARM64_NETWORK_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-network/rubyos.elf
ARM64_WEB_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-web/rubyos.elf
ARM64_INPUT_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-input/rubyos.elf
ARM64_AUDIO_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-audio/rubyos.elf
ARM64_SMP_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-smp/rubyos.elf
DISK_IMAGE := $(CURDIR)/build/disk.img
RUBY_PC := PKG_CONFIG_PATH=$(CURDIR)/build/host-ruby/lib/pkgconfig pkg-config
BUILDER_PLATFORM ?= linux/$(if $(filter aarch64 arm64,$(shell uname -m)),arm64,amd64)
BUILDER_IMAGE := rubyos-builder-$(subst /,-,$(BUILDER_PLATFORM))
CONTAINER_ENGINE ?= ./tools/container-engine.sh

.PHONY: all ruby smoke test test-iseq teaching-examples test-ext2 test-network test-install bridge test-bridge debug-smoke debug-session parity build-linux build-macos release release-linux release-macos docker-build validate-release embed-probe baremetal-arm64 baremetal-smoke ruby-arm64 ruby-x86_64 rubyos-x86_64 rubyos-x86_64-smoke rubyos-x86_64-input-smoke rubyos-x86_64-audio-smoke rubyos-x86_64-smp-smoke rubyos-arm64 rubyos-arm64-smoke rubyos-arm64-gui rubyos-arm64-gui-smoke rubyos-arm64-tcp-gui rubyos-arm64-tcp-gui-smoke rubyos-arm64-input-smoke rubyos-arm64-audio-smoke rubyos-arm64-smp-smoke rubyos-arm64-repl rubyos-arm64-repl-smoke rubyos-arm64-storage rubyos-arm64-storage-smoke rubyos-arm64-network rubyos-arm64-network-smoke rubyos-arm64-web rubyos-arm64-web-smoke disk \
	clean distclean provenance

all: build

ruby: $(HOST_RUBY_STAMP)

$(HOST_RUBY_STAMP): tools/build-ruby-from-source.sh config/ruby.mk
	./tools/build-ruby-from-source.sh

smoke: $(HOST_RUBY_STAMP)
	$(HOST_RUBY) -I kernel kernel/boot.rb

test-host: $(HOST_RUBY_STAMP)
	$(HOST_RUBY) -I kernel test/kernel_test.rb
	$(HOST_RUBY) test/embed_manifest_test.rb
	$(HOST_RUBY) test/visual_golden_unit_test.rb
	$(HOST_RUBY) -I kernel test/gui_dock_test.rb
	$(HOST_RUBY) -I kernel test/virtio_transport_test.rb
	$(HOST_RUBY) -I kernel test/media_test.rb

test-iseq: $(HOST_RUBY_STAMP)
	$(HOST_RUBY) test/iseq_cache_test.rb

teaching-examples: $(HOST_RUBY_STAMP)
	./test/examples_smoke.sh

test-ext2: $(HOST_RUBY_STAMP)
	./test/ext2_smoke.sh

test-network: $(HOST_RUBY_STAMP)
	$(HOST_RUBY) -I kernel test/network_test.rb

test-install:
	./test/install_host_test.sh

bridge:
	@if ! test -f "$(REMOTEOS_SDL_DIR)/Makefile"; then \
		if test "$(REMOTEOS_SDL_DIR)" = "services/remoteos-sdl" && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
			echo "Initializing the display service submodule"; \
			git submodule update --init --recursive -- services/remoteos-sdl; \
		fi; \
	fi
	@test -f "$(REMOTEOS_SDL_DIR)/Makefile" || { echo "Display service not found at $(REMOTEOS_SDL_DIR)" >&2; exit 1; }
	$(MAKE) -C $(REMOTEOS_SDL_DIR)

.PHONY: test-media
test-media: $(HOST_RUBY_STAMP) bridge
	$(HOST_RUBY) -I kernel test/media_smoke.rb

test-bridge: $(HOST_RUBY_STAMP) bridge
	mkdir -p build
	$(HOST_RUBY) -I kernel test/remote_desktop_smoke.rb
	$(HOST_RUBY) -I kernel test/gui_text_test.rb

debug-smoke: $(ARM64_GUI_ELF) bridge
	./test/rubyos_debug_smoke.py

debug-session: $(ARM64_GUI_ELF) bridge
	./test/rubyos_debug_smoke.py --hold

parity:
	$(MAKE) test-install provenance smoke test-host test-iseq teaching-examples test-ext2 test-network test-bridge test-media
	$(MAKE) embed-probe baremetal-smoke
	$(MAKE) rubyos-arm64-smoke rubyos-x86_64-smoke
	$(MAKE) rubyos-arm64-gui-smoke rubyos-arm64-repl-smoke
	$(MAKE) rubyos-arm64-tcp-gui-smoke
	$(MAKE) rubyos-arm64-storage-smoke rubyos-arm64-network-smoke
	$(MAKE) rubyos-arm64-web-smoke
	$(MAKE) rubyos-arm64-input-smoke rubyos-x86_64-input-smoke
	$(MAKE) rubyos-arm64-audio-smoke rubyos-x86_64-audio-smoke
	$(MAKE) rubyos-arm64-smp-smoke rubyos-x86_64-smp-smoke debug-smoke
	$(MAKE) rubyos-x86_64-repl-smoke rubyos-x86_64-storage-smoke rubyos-x86_64-network-smoke rubyos-x86_64-web-smoke rubyos-x86_64-tcp-gui-smoke
	$(MAKE) test-user-commands TARGET_ARCH=arm64
	$(MAKE) test-user-commands TARGET_ARCH=x86_64

docker-build:
	$(CONTAINER_ENGINE) build --platform $(BUILDER_PLATFORM) -t $(BUILDER_IMAGE) -f tools/Dockerfile .

build-linux: parity

build-macos:
	$(MAKE) test-install provenance smoke test-host test-iseq teaching-examples test-network test-bridge test-media

release-linux: build-linux
	./scripts/package-release.sh linux

release-macos: build-macos
	./scripts/package-release.sh macos

release:
	@case "$$(uname -s)" in \
		Darwin) $(MAKE) release-macos ;; \
		Linux) $(MAKE) release-linux ;; \
		*) echo "unsupported release host: $$(uname -s)" >&2; exit 2 ;; \
	esac

validate-release:
	./scripts/validate-release.sh

embed-probe: $(EMBED_PROBE)
	$(EMBED_PROBE)

baremetal-arm64: $(ARM64_ELF)

$(ARM64_ELF): baremetal/arm64/boot.S baremetal/arm64/kernel.c \
		baremetal/arm64/linker.ld tools/build-baremetal-arm64.sh
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) \
		-v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		./tools/build-baremetal-arm64.sh

baremetal-smoke: $(ARM64_ELF)
	./test/baremetal_arm64_smoke.sh

ruby-arm64: $(ARM64_RUBY_STAMP)
$(ARM64_RUBY_STAMP): $(HOST_RUBY_STAMP) tools/build-ruby-arm64.sh config/ruby.mk
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) ./tools/build-ruby-arm64.sh

ruby-x86_64: $(X86_64_RUBY_STAMP)
$(X86_64_RUBY_STAMP): $(HOST_RUBY_STAMP) tools/build-ruby-x86_64.sh config/ruby.mk
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) ./tools/build-ruby-x86_64.sh

rubyos-x86_64: $(X86_64_RUBYOS_ISO)
$(X86_64_RUBYOS_ISO): $(X86_64_RUBY_STAMP) tools/build-rubyos-x86_64.sh $(shell find baremetal/x86_64 platform -type f) tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb')
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) ./tools/build-rubyos-x86_64.sh

rubyos-x86_64-smoke: $(X86_64_RUBYOS_ISO)
	./test/rubyos_x86_64_smoke.sh

$(X86_64_INPUT_ISO): $(X86_64_RUBY_STAMP) tools/build-rubyos-x86_64.sh $(shell find baremetal/x86_64 platform -type f) tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb')
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_INPUT=1 RUBYOS_X86_VARIANT=rubyos-x86_64-input ./tools/build-rubyos-x86_64.sh

rubyos-x86_64-input-smoke: $(X86_64_INPUT_ISO)
	./test/rubyos_x86_64_input_smoke.py

$(X86_64_AUDIO_ISO): $(X86_64_RUBY_STAMP) tools/build-rubyos-x86_64.sh $(shell find baremetal/x86_64 platform -type f) tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb')
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_AUDIO=1 RUBYOS_X86_VARIANT=rubyos-x86_64-audio ./tools/build-rubyos-x86_64.sh

rubyos-x86_64-audio-smoke: $(X86_64_AUDIO_ISO)
	./test/rubyos_x86_64_audio_smoke.sh

$(X86_64_SMP_ISO): $(X86_64_RUBY_STAMP) tools/build-rubyos-x86_64.sh $(shell find baremetal/x86_64 platform -type f) tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb')
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_SMP=1 RUBYOS_X86_VARIANT=rubyos-x86_64-smp ./tools/build-rubyos-x86_64.sh

rubyos-x86_64-smp-smoke: $(X86_64_SMP_ISO)
	./test/rubyos_x86_64_smp_smoke.sh

rubyos-arm64: $(ARM64_RUBYOS_ELF)
$(ARM64_RUBYOS_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) ./tools/build-rubyos-arm64.sh

rubyos-arm64-smoke: $(ARM64_RUBYOS_ELF)
	./test/rubyos_arm64_smoke.sh

rubyos-arm64-gui: $(ARM64_GUI_ELF)
$(ARM64_GUI_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_DESKTOP=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-gui ./tools/build-rubyos-arm64.sh

rubyos-arm64-gui-smoke: $(ARM64_GUI_ELF) bridge
	./test/rubyos_arm64_gui_smoke.sh

rubyos-arm64-tcp-gui: $(ARM64_TCP_GUI_ELF)
$(ARM64_TCP_GUI_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_DESKTOP_TCP=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-tcp-gui ./tools/build-rubyos-arm64.sh

rubyos-arm64-tcp-gui-smoke: $(ARM64_TCP_GUI_ELF) bridge
	./test/rubyos_arm64_tcp_gui_smoke.sh

$(ARM64_INPUT_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_INPUT=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-input ./tools/build-rubyos-arm64.sh

rubyos-arm64-input-smoke: $(ARM64_INPUT_ELF)
	./test/rubyos_arm64_input_smoke.py

$(ARM64_AUDIO_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_AUDIO=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-audio ./tools/build-rubyos-arm64.sh

rubyos-arm64-audio-smoke: $(ARM64_AUDIO_ELF)
	./test/rubyos_arm64_audio_smoke.sh

$(ARM64_SMP_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_SMP=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-smp ./tools/build-rubyos-arm64.sh

rubyos-arm64-smp-smoke: $(ARM64_SMP_ELF)
	./test/rubyos_arm64_smp_smoke.sh

rubyos-arm64-repl: $(ARM64_REPL_ELF)
$(ARM64_REPL_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_REPL=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-repl ./tools/build-rubyos-arm64.sh

rubyos-arm64-repl-smoke: $(ARM64_REPL_ELF)
	./test/rubyos_arm64_repl_smoke.sh

disk: $(DISK_IMAGE)
$(DISK_IMAGE): tools/build-disk.sh
	./tools/build-disk.sh $@

rubyos-arm64-storage: $(ARM64_STORAGE_ELF)
$(ARM64_STORAGE_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_REPL=1 RUBYOS_EMBED_STORAGE=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-storage ./tools/build-rubyos-arm64.sh

rubyos-arm64-storage-smoke: $(ARM64_STORAGE_ELF) $(DISK_IMAGE)
	./test/rubyos_arm64_storage_smoke.sh

rubyos-arm64-network: $(ARM64_NETWORK_ELF)
$(ARM64_NETWORK_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_NETWORK=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-network ./tools/build-rubyos-arm64.sh

rubyos-arm64-network-smoke: $(ARM64_NETWORK_ELF)
	./test/rubyos_arm64_network_smoke.sh

rubyos-arm64-web: $(ARM64_WEB_ELF)
$(ARM64_WEB_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/gic_timer.c baremetal/arm64/smp.c \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	$(CONTAINER_ENGINE) run --rm --platform $(BUILDER_PLATFORM) --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_WEB=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-web ./tools/build-rubyos-arm64.sh

rubyos-arm64-web-smoke: $(ARM64_WEB_ELF)
	./test/rubyos_arm64_web_smoke.sh

$(EMBED_PROBE): tools/embed_probe.c Makefile $(HOST_RUBY_STAMP)
	cc -o $@ tools/embed_probe.c $$($(RUBY_PC) --cflags ruby-4.0) \
		-L$(CURDIR)/build/host-ruby/lib \
		-Wl,--whole-archive -lruby-static -Wl,--no-whole-archive \
		-lz -lrt -ldl -lcrypt -lm -lpthread

provenance: $(HOST_RUBY_STAMP)
	@$(HOST_RUBY) --version
	@$(HOST_RUBY) -e 'abort "unexpected executable" unless File.expand_path(RbConfig.ruby).start_with?(File.expand_path("build/host-ruby")); puts RbConfig.ruby'

clean: stop
	$(MAKE) -C services/remoteos-sdl clean
	rm -f build/embed-probe
	@for dir in build/baremetal/arm64 build/baremetal/rubyos-*; do test ! -d "$$dir" || rm -rf "$$dir"; done

distclean: clean
	rm -rf build/ruby-build build/host-ruby build/baremetal
	rm -f deps/$(RUBY_ARCHIVE)

include mk/user.mk
