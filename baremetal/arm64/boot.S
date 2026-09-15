.section .text.boot, "ax"
.global _start
.type _start, %function

_start:
    mov x19, x0

    mrs x0, CurrentEL
    lsr x0, x0, #2
    cmp x0, #2
    b.ne 1f

    mov x0, #(1 << 31)
    msr hcr_el2, x0
    adr x0, 1f
    msr elr_el2, x0
    mov x0, #0x3c5
    msr spsr_el2, x0
    msr sctlr_el1, xzr
    isb
    eret

1:
    mrs x0, cpacr_el1
    orr x0, x0, #(3 << 20)
    msr cpacr_el1, x0
    isb

    ldr x0, =exception_vectors
    msr vbar_el1, x0
    isb

    ldr x0, =stack_top
    mov sp, x0

    ldr x1, =bss_start
    ldr x2, =bss_end
2:
    cmp x1, x2
    b.hs 3f
    str xzr, [x1], #8
    b 2b
3:
    /* Install the initial thread pointer before any C or Ruby code uses TLS. */
    ldr x0, =tls_tcb_start
    str x0, [x0]
    str xzr, [x0, #8]
    msr tpidr_el0, x0
    msr tpidrro_el0, x0
    isb

    ldr x1, =tls_bss_start
    ldr x2, =tls_bss_end
5:
    cmp x1, x2
    b.hs 6f
    str xzr, [x1], #8
    b 5b
6:
    /* Resolve any static IRELATIVE entries without relying on a CRT loader. */
    ldr x20, =rela_dyn_start
    ldr x21, =rela_dyn_end
7:
    cmp x20, x21
    b.hs 8f
    ldr x0, [x20, #16]
    blr x0
    ldr x1, [x20]
    str x0, [x1]
    add x20, x20, #24
    b 7b
8:
    /* Run compiler/runtime constructors (currently libgcc CPU feature setup). */
    ldr x20, =init_array_start
    ldr x21, =init_array_end
9:
    cmp x20, x21
    b.hs 10f
    ldr x0, [x20], #8
    blr x0
    b 9b
10:
    mov x0, x19
    bl rubyos_kernel_main

4:
    wfe
    b 4b

.size _start, . - _start

.global rubyos_ap_entry
rubyos_ap_entry:
    mov x19, x0
    mrs x0, CurrentEL
    lsr x0, x0, #2
    cmp x0, #2
    b.ne 11f
    mov x0, #(1 << 31)
    msr hcr_el2, x0
    adr x0, 11f
    msr elr_el2, x0
    mov x0, #0x3c5
    msr spsr_el2, x0
    msr sctlr_el1, xzr
    isb
    eret
11:
    mrs x0, cpacr_el1
    orr x0, x0, #(3 << 20)
    msr cpacr_el1, x0
    isb
    adrp x0, rubyos_ap_stack_top
    add x0, x0, :lo12:rubyos_ap_stack_top
    ldr x0, [x0, x19, lsl #3]
    mov sp, x0
    mov x0, x19
    bl rubyos_ap_main
12:
    wfe
    b 12b

.balign 2048
.global exception_vectors
exception_vectors:
    b rubyos_sync_exception
    .balign 128
    b rubyos_irq_entry
    .balign 128
    b rubyos_unhandled_exception
    .balign 128
    b rubyos_unhandled_exception
    .balign 128
    b rubyos_sync_exception
    .balign 128
    b rubyos_irq_entry
    .balign 128
    b rubyos_unhandled_exception
    .balign 128
    b rubyos_unhandled_exception
    .balign 128
    b rubyos_sync_exception
    .balign 128
    b rubyos_unhandled_exception
    .balign 128
    b rubyos_unhandled_exception
    .balign 128
    b rubyos_unhandled_exception
    .balign 128
    b rubyos_sync_exception
    .balign 128
    b rubyos_unhandled_exception
    .balign 128
    b rubyos_unhandled_exception
    .balign 128
    b rubyos_unhandled_exception

rubyos_sync_exception:
    mrs x0, esr_el1
    mrs x1, elr_el1
    mrs x2, far_el1
    b rubyos_exception_report

rubyos_unhandled_exception:
    mov x0, xzr
    mrs x1, elr_el1
    mrs x2, far_el1
    b rubyos_exception_report

rubyos_irq_entry:
    sub sp, sp, #176
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp x8, x9, [sp, #64]
    stp x10, x11, [sp, #80]
    stp x12, x13, [sp, #96]
    stp x14, x15, [sp, #112]
    stp x16, x17, [sp, #128]
    stp x18, x30, [sp, #144]
    str x29, [sp, #160]
    bl rubyos_irq_handler
    ldp x0, x1, [sp, #0]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldp x8, x9, [sp, #64]
    ldp x10, x11, [sp, #80]
    ldp x12, x13, [sp, #96]
    ldp x14, x15, [sp, #112]
    ldp x16, x17, [sp, #128]
    ldp x18, x30, [sp, #144]
    ldr x29, [sp, #160]
    add sp, sp, #176
    eret
