ENTRY(_start)
 
SECTIONS {
    . = 2M;
    _ZKERNEL_KERNEL_BEGIN = .;
    .text : ALIGN(4K) {
        KEEP(*(.multiboot))
        *(.text)
    }

    .rodata : ALIGN(4K) {
        *(.rodata)
    }
 
    .data : ALIGN(4K) {
        *(.data)
    }
 
    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss)
    }
    _ZKERNEL_KERNEL_END = .;
}