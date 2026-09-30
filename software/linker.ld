ENTRY(_start)

MEMORY
{
    IMEM      (rx)  : ORIGIN = 0x00003000, LENGTH = 0x10000
    DMEM_DATA (rwx) : ORIGIN = 0x00000400, LENGTH = 0x1ec00
}

SECTIONS
{
    __dmem_start = 0x00000000;
    __dmem_end = 0x00020000;
    __result_start = 0x00000100;
    __result_end = 0x0000010c;
    __scratch_start = 0x00000200;
    __scratch_end = 0x00000300;
    __program_data_start = ORIGIN(DMEM_DATA);
    __program_data_end = ORIGIN(DMEM_DATA) + LENGTH(DMEM_DATA);
    __stack_limit = 0x0001f000;
    __stack_top = 0x0001fff0;
    __uart_tx_data = 0x10000000;
    __uart_status = 0x10000004;
    __uart_ctrl = 0x10000008;
    __uart_tx_level = 0x1000000c;
    __timer_counter = 0x10000100;
    __timer_compare = 0x10000104;
    __timer_status = 0x10000108;
    __mdio_base = 0x10001100;
    __mdio_addr = 0x10001100;
    __mdio_wdata = 0x10001104;
    __mdio_cmd = 0x10001108;
    __mdio_rdata = 0x1000110c;
    __mdio_status = 0x10001110;
    __phy_reset_ctrl = 0x10001114;
    __board_base = 0x10002000;
    __board_ledr = 0x10002000;
    __board_ledg = 0x10002004;
    __board_sw = 0x10002008;
    __board_key = 0x1000200c;
    __tse_base = 0x10003000;
    __tse_end = 0x10003100;
    __tse_tx_data = 0x10003050;
    __tse_rx_data = 0x10003070;

    .text : {
        . = ALIGN(4);
        KEEP(*(.text.start))
        *(.text*)
        . = ALIGN(4);
    } > IMEM

    .rodata : {
        . = ALIGN(4);
        __rodata_start = .;
        *(.rodata*)
        *(.srodata*)
        . = ALIGN(4);
        __rodata_end = .;
    } > DMEM_DATA

    .data : {
        . = ALIGN(4);
        __data_start = .;
        *(.sdata*)
        *(.data*)
        . = ALIGN(4);
        __data_end = .;
    } > DMEM_DATA

    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        *(.sbss*)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DMEM_DATA

    ASSERT(__rodata_start >= __program_data_start, "rodata starts before program data window")
    ASSERT(__bss_end <= __program_data_end, "rodata/data/bss exceed program data window")
    ASSERT(__program_data_end <= __stack_limit, "program data overlaps stack reserve")
    ASSERT(__result_end <= __program_data_start, "result area overlaps program data window")
    ASSERT(__scratch_end <= __program_data_start, "scratch area overlaps program data window")
    ASSERT(__stack_limit < __stack_top, "stack reserve is empty")
    ASSERT(__stack_top <= __dmem_end, "stack top is outside data RAM")
    ASSERT(__dmem_end <= __uart_tx_data, "high MMIO overlaps low data RAM")
}
