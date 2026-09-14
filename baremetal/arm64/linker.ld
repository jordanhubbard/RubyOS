ENTRY(_start)
OUTPUT_FORMAT(elf64-littleaarch64)

PHDRS
{
    text PT_LOAD FLAGS(5);
    rodata PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0x40100000;

    .text.boot : {
        KEEP(*(.text.boot))
    } :text

    .text ALIGN(4096) : {
        *(.text*)
    } :text

    .rodata ALIGN(4096) : {
        *(.rodata*)
    } :rodata

    .rela.dyn ALIGN(8) : {
        rela_dyn_start = .;
        *(.rela.dyn*)
    } :rodata
    rela_dyn_end = rela_dyn_start + SIZEOF(.rela.dyn);

    .data ALIGN(4096) : {
        *(.data*)
    } :data

    .init_array ALIGN(8) : {
        init_array_start = .;
        KEEP(*(.init_array*))
        init_array_end = .;
    } :data

    /* AArch64 uses TLS variant I: TPIDR_EL0 addresses a two-word TCB and
     * the compiler-generated local-exec offsets begin immediately after it. */
    .tls_tcb ALIGN(16) (NOLOAD) : {
        tls_tcb_start = .;
        . += 16;
    } :data

    .tdata ALIGN(8) : {
        tls_data_start = .;
        *(.tdata*)
        tls_data_end = .;
    } :data

    .tbss ALIGN(8) (NOLOAD) : {
        tls_bss_start = .;
        *(.tbss*)
        tls_bss_end = .;
    } :data

    .bss ALIGN(4096) : {
        bss_start = .;
        *(COMMON)
        *(.bss*)
        . = ALIGN(16);
        stack_bottom = .;
        . += 4194304;
        stack_top = .;
        bss_end = .;
    } :data

    heap_start = ALIGN(4096);
    _end = heap_start;
    heap_limit = 0x5f000000;

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.note*)
    }
}
