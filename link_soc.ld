OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    DMEM (rw)  : ORIGIN = 0x00002000, LENGTH = 64K
}

SECTIONS {
    . = 0x00000000;
    .text : {
        *(.text.start)   /* _start must be first — reset vector at 0x0 */
        *(.text)
        *(.text.*)
    } > IMEM

    . = 0x00002000;
    .rodata : {
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
    } > DMEM

    .data : {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    } > DMEM

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        __bss_end = .;
    } > DMEM

    PROVIDE(__stack_top = 0x00012000);  /* top of 64KB DMEM */

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.riscv.attributes)
        *(.note.*)
        *(.debug*)
    }
}
