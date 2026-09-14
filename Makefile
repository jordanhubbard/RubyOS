include config/ruby.mk

HOST_RUBY := $(CURDIR)/build/host-ruby/bin/ruby
HOST_RUBY_STAMP := $(CURDIR)/build/host-ruby/.rubyos-built
EMBED_PROBE := $(CURDIR)/build/embed-probe
ARM64_ELF := $(CURDIR)/build/baremetal/arm64/rubyos-arm64.elf
ARM64_RUBY_LIB := $(CURDIR)/build/baremetal/ruby-freestanding/libruby-static.a
ARM64_RUBY_STAMP := $(CURDIR)/build/baremetal/ruby-freestanding/.rubyos-built
ARM64_RUBYOS_ELF := $(CURDIR)/build/baremetal/rubyos-arm64/rubyos.elf
ARM64_GUI_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-gui/rubyos.elf
ARM64_REPL_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-repl/rubyos.elf
ARM64_STORAGE_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-storage/rubyos.elf
ARM64_NETWORK_ELF := $(CURDIR)/build/baremetal/rubyos-arm64-network/rubyos.elf
DISK_IMAGE := $(CURDIR)/build/disk.img
RUBY_PC := PKG_CONFIG_PATH=$(CURDIR)/build/host-ruby/lib/pkgconfig pkg-config
BUILDER_IMAGE := pythonos-builder

.PHONY: all ruby smoke test test-ext2 test-network bridge test-bridge embed-probe baremetal-arm64 baremetal-smoke ruby-arm64 rubyos-arm64 rubyos-arm64-smoke rubyos-arm64-gui rubyos-arm64-gui-smoke rubyos-arm64-repl rubyos-arm64-repl-smoke rubyos-arm64-storage rubyos-arm64-storage-smoke rubyos-arm64-network rubyos-arm64-network-smoke disk \
	clean distclean provenance

all: smoke

ruby: $(HOST_RUBY_STAMP)

$(HOST_RUBY_STAMP): tools/build-ruby-from-source.sh config/ruby.mk
	./tools/build-ruby-from-source.sh

smoke: $(HOST_RUBY_STAMP)
	$(HOST_RUBY) -I kernel kernel/boot.rb

test: $(HOST_RUBY_STAMP)
	$(HOST_RUBY) -I kernel test/kernel_test.rb

test-ext2: $(HOST_RUBY_STAMP)
	./test/ext2_smoke.sh

test-network: $(HOST_RUBY_STAMP)
	$(HOST_RUBY) -I kernel test/network_test.rb

bridge:
	$(MAKE) -C bridge

test-bridge: $(HOST_RUBY_STAMP) bridge
	mkdir -p build
	$(HOST_RUBY) -I kernel test/remote_desktop_smoke.rb

embed-probe: $(EMBED_PROBE)
	$(EMBED_PROBE)

baremetal-arm64: $(ARM64_ELF)

$(ARM64_ELF): baremetal/arm64/boot.S baremetal/arm64/kernel.c \
		baremetal/arm64/linker.ld tools/build-baremetal-arm64.sh
	docker run --rm --platform linux/arm64 --user $$(id -u):$$(id -g) \
		-v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		./tools/build-baremetal-arm64.sh

baremetal-smoke: $(ARM64_ELF)
	./test/baremetal_arm64_smoke.sh

ruby-arm64: $(ARM64_RUBY_STAMP)
$(ARM64_RUBY_STAMP): $(HOST_RUBY_STAMP) tools/build-ruby-arm64.sh config/ruby.mk
	docker run --rm --platform linux/arm64 --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) ./tools/build-ruby-arm64.sh

rubyos-arm64: $(ARM64_RUBYOS_ELF)
$(ARM64_RUBYOS_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	docker run --rm --platform linux/arm64 --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) ./tools/build-rubyos-arm64.sh

rubyos-arm64-smoke: $(ARM64_RUBYOS_ELF)
	./test/rubyos_arm64_smoke.sh

rubyos-arm64-gui: $(ARM64_GUI_ELF)
$(ARM64_GUI_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	docker run --rm --platform linux/arm64 --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_DESKTOP=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-gui ./tools/build-rubyos-arm64.sh

rubyos-arm64-gui-smoke: $(ARM64_GUI_ELF) bridge
	./test/rubyos_arm64_gui_smoke.sh

rubyos-arm64-repl: $(ARM64_REPL_ELF)
$(ARM64_REPL_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	docker run --rm --platform linux/arm64 --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
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
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	docker run --rm --platform linux/arm64 --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_REPL=1 RUBYOS_EMBED_STORAGE=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-storage ./tools/build-rubyos-arm64.sh

rubyos-arm64-storage-smoke: $(ARM64_STORAGE_ELF) $(DISK_IMAGE)
	./test/rubyos_arm64_storage_smoke.sh

rubyos-arm64-network: $(ARM64_NETWORK_ELF)
$(ARM64_NETWORK_ELF): $(ARM64_RUBY_STAMP) tools/build-rubyos-arm64.sh \
		baremetal/arm64/boot.S baremetal/arm64/ruby_kernel.c \
		baremetal/arm64/platform_stubs.c baremetal/arm64/setjmp.S \
		baremetal/arm64/linker.ld tools/embed-kernel.rb $(shell find kernel -type f -name '*.rb') \
		$(wildcard platform/libc/*.c platform/libc/include/*.h platform/libc/include/sys/*.h platform/boot/*.h)
	docker run --rm --platform linux/arm64 --user $$(id -u):$$(id -g) -v $(CURDIR):/work -w /work $(BUILDER_IMAGE) \
		env RUBYOS_EMBED_NETWORK=1 RUBYOS_ARM64_VARIANT=rubyos-arm64-network ./tools/build-rubyos-arm64.sh

rubyos-arm64-network-smoke: $(ARM64_NETWORK_ELF)
	./test/rubyos_arm64_network_smoke.sh

$(EMBED_PROBE): tools/embed_probe.c Makefile $(HOST_RUBY_STAMP)
	cc -o $@ tools/embed_probe.c $$($(RUBY_PC) --cflags ruby-4.0) \
		-L$(CURDIR)/build/host-ruby/lib \
		-Wl,--whole-archive -lruby-static -Wl,--no-whole-archive \
		-lz -lrt -ldl -lcrypt -lm -lpthread

provenance: $(HOST_RUBY_STAMP)
	@$(HOST_RUBY) --version
	@$(HOST_RUBY) -e 'abort "unexpected executable" unless File.expand_path(RbConfig.ruby).start_with?(File.expand_path("build/host-ruby")); puts RbConfig.ruby'

clean:
	$(MAKE) -C bridge clean
	rm -rf build/ruby-build build/host-ruby build/embed-probe build/baremetal

distclean: clean
	rm -f deps/$(RUBY_ARCHIVE)
