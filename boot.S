.section .text
    .globl _start

_start:
    /* Your Data RAM starts at 0x2000 and is 64KB (0x10000). */
    /* We set the Stack Pointer (sp) to the very top: 0x12000 */
    li sp, 0x12000
    /* Jump into your main_soc.c code */
    call main
    /* If main ever finishes, trap the CPU in a safe infinite loop */
trap_loop:
    j trap_loop
