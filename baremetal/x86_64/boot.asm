MULTIBOOT2_MAGIC equ 0xE85250D6
MULTIBOOT2_ARCH equ 0
MULTIBOOT2_LENGTH equ mb2_end - mb2_start
MULTIBOOT2_CHECKSUM equ -(MULTIBOOT2_MAGIC + MULTIBOOT2_ARCH + MULTIBOOT2_LENGTH) & 0xffffffff

section .multiboot2
align 8
mb2_start:
    dd MULTIBOOT2_MAGIC, MULTIBOOT2_ARCH, MULTIBOOT2_LENGTH, MULTIBOOT2_CHECKSUM
    dw 0, 0
    dd 8
mb2_end:

section .bss
align 16
global stack_bottom, stack_top
stack_bottom: resb 4194304
stack_top:
align 4096
pml4: resb 4096
pdpt: resb 4096
pd0: resb 4096

section .data
mb_magic: dd 0
mb_info: dd 0

section .rodata
gdt:
    dq 0
    dq 0x00af9a000000ffff
    dq 0x00af92000000ffff
gdt_end:
gdt_ptr:
    dw gdt_end - gdt - 1
    dd gdt

section .text
bits 32
global _start
_start:
    mov esp, stack_top
    mov [mb_magic], eax
    mov [mb_info], ebx
    cmp eax, 0x36d76289
    jne halt32
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax
    mov eax, pdpt
    or eax, 3
    mov [pml4], eax
    mov eax, pd0
    or eax, 3
    mov [pdpt], eax
    xor ecx, ecx
    mov eax, 0x83
.map:
    mov [pd0 + ecx * 8], eax
    add eax, 0x200000
    inc ecx
    cmp ecx, 512
    jne .map
    mov eax, pml4
    mov cr3, eax
    lgdt [gdt_ptr]
    mov ecx, 0xc0000080
    rdmsr
    or eax, 1 << 8
    wrmsr
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax
    jmp 0x08:long_mode
halt32:
    cli
    hlt
    jmp halt32

bits 64
long_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, stack_top
    xor rbp, rbp
    mov rax, cr0
    and ax, 0xfffb
    or ax, 2
    mov cr0, rax
    mov rax, cr4
    or ax, 3 << 9
    mov cr4, rax
    xor rdi, rdi
    mov edi, [rel mb_magic]
    xor rsi, rsi
    mov esi, [rel mb_info]
    extern rubyos_x86_64_start
    call rubyos_x86_64_start
.halt:
    cli
    hlt
    jmp .halt

section .note.GNU-stack noalloc noexec nowrite progbits
