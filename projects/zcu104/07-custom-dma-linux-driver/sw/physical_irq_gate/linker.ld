ENTRY(_start)

SECTIONS
{
    . = 0xFFFC0000;

    .text : ALIGN(16)
    {
        KEEP(*(.text.start))
        *(.text*)
        *(.rodata*)
    }

    .data : ALIGN(16)
    {
        *(.data*)
    }

    .bss (NOLOAD) : ALIGN(16)
    {
        *(.bss*)
        *(COMMON)
    }

    /DISCARD/ :
    {
        *(.comment*)
        *(.note*)
        *(.eh_frame*)
    }
}
