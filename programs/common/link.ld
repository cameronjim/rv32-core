/* link.ld: memory layout for rv32-core programs.
   .text lands in imem at 0x0, every data section lands in dmem at 0x1000.
   There is no load-time copy of .data: the CPU has no load path from imem, so
   the dmem image is preloaded from its own hex file. */

OUTPUT_FORMAT("elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

__imem_start = 0x00000000;
__imem_end   = 0x00001000;
__dmem_start = 0x00001000;
__dmem_end   = 0x00002000;

/* the stack grows down from here; 0x1FF0..0x1FFF holds the done word at 0x1FFC */
PROVIDE(__stack_top = 0x00001FF0);
PROVIDE(__done_addr = 0x00001FFC);

/* leave at least 0x100 bytes of stack between the end of bss and __stack_top */
__data_limit = 0x00001F00;

SECTIONS
{
  . = __imem_start;

  .text : ALIGN(4)
  {
    __text_start = .;
    KEEP(*(.text.init))
    *(.text.unlikely .text.unlikely.*)
    *(.text.startup .text.startup.*)
    *(.text .text.*)
    . = ALIGN(4);
    __text_end = .;
  }

  . = __dmem_start;
  __data_start = .;

  .rodata : ALIGN(4)
  {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  }

  .data : ALIGN(4)
  {
    *(.data .data.*)
  }

  /* gp sits 2 KB into the small-data area so 12-bit signed offsets reach both
     .sdata and .sbss; --no-relax means nothing actually uses it, but crt0 still
     loads it so the convention holds if relaxation is ever turned back on */
  . = ALIGN(4);
  PROVIDE(__global_pointer$ = . + 0x800);

  .sdata : ALIGN(4)
  {
    *(.sdata .sdata.*)
  }

  . = ALIGN(4);
  __data_end = .;

  /* bss symbols live outside the sections so they resolve even when both
     sections are empty and the linker drops them */
  __bss_start = .;

  .sbss (NOLOAD) : ALIGN(4)
  {
    *(.sbss .sbss.*)
    *(.scommon)
  }

  .bss (NOLOAD) : ALIGN(4)
  {
    *(.bss .bss.*)
    *(COMMON)
  }

  . = ALIGN(4);
  __bss_end = .;

  /DISCARD/ :
  {
    *(.comment)
    *(.note .note.*)
    *(.eh_frame .eh_frame_hdr)
  }
}

/* word counts, exported so the build can sanity check image sizes */
__text_words = (__text_end - __text_start) >> 2;
__data_words = (__data_end - __data_start) >> 2;
__bss_words  = (__bss_end - __bss_start) >> 2;

ASSERT(__text_end <= __imem_end,
       "link.ld: .text overflows the 4 KB imem region")
ASSERT(__bss_end <= __data_limit,
       "link.ld: data plus bss leaves no room for the stack below __stack_top")
