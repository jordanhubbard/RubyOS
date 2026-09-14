ENTRY(_start)
OUTPUT_FORMAT(elf64-x86-64)

PHDRS { text PT_LOAD FLAGS(5); rodata PT_LOAD FLAGS(4); data PT_LOAD FLAGS(6); }
SECTIONS {
    . = 0x100000;
    .multiboot2 : { KEEP(*(.multiboot2)) } :text
    .text ALIGN(4096) : { *(.text*) } :text
    .rodata ALIGN(4096) : { *(.rodata*) } :rodata
    .rela.dyn ALIGN(8) : { rela_dyn_start = .; *(.rela.dyn*) rela_dyn_end = .; } :rodata
    .data ALIGN(4096) : { *(.data*) } :data
    .init_array ALIGN(8) : { init_array_start = .; KEEP(*(.init_array*)) init_array_end = .; } :data
    .tdata ALIGN(16) : { __tls_start = .; __tdata_start = .; *(.tdata .tdata.*) __tdata_end = .; } :data
    .tbss ALIGN(16) : { *(.tbss .tbss.*) *(.tcommon) . = ALIGN(16); __tls_end = .; } :data
    .bss ALIGN(4096) : { bss_start = .; *(COMMON) *(.bss*) bss_end = .; } :data
    heap_start = ALIGN(4096);
    _end = heap_start;
    heap_limit = 0x30000000;
    /DISCARD/ : { *(.comment) *(.eh_frame) *(.note*) }
}
