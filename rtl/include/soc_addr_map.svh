// Shared board-prep / Version15 SoC address map.
//
// Kept as simple preprocessor constants for broad ModelSim compatibility.
// Each RTL module converts the needed values into localparams in its own scope.
`ifndef SOC_ADDR_MAP_SVH
`define SOC_ADDR_MAP_SVH

`define SOC_DATA_RAM_START_ADDR      32'h00000000
`define SOC_DATA_RAM_END_ADDR        32'h00020000
`define SOC_DATA_RAM_WORD_COUNT      32768

`define SOC_UART_TX_DATA_ADDR        32'h10000000
`define SOC_UART_STATUS_ADDR         32'h10000004
`define SOC_UART_CTRL_ADDR           32'h10000008
`define SOC_UART_TX_LEVEL_ADDR       32'h1000000c
`define SOC_UART_END_ADDR            32'h10000010
`define SOC_UART_STATUS_VALUE        32'h00000001

`define SOC_TIMER_COUNTER_ADDR       32'h10000100
`define SOC_TIMER_COMPARE_ADDR       32'h10000104
`define SOC_TIMER_STATUS_ADDR        32'h10000108

`define SOC_MDIO_BASE_ADDR           32'h10001100
`define SOC_MDIO_ADDR_ADDR           32'h10001100
`define SOC_MDIO_WDATA_ADDR          32'h10001104
`define SOC_MDIO_CMD_ADDR            32'h10001108
`define SOC_MDIO_RDATA_ADDR          32'h1000110c
`define SOC_MDIO_STATUS_ADDR         32'h10001110
`define SOC_PHY_RESET_CTRL_ADDR      32'h10001114
`define SOC_MDIO_END_ADDR            32'h10001118

`define SOC_BOARD_BASE_ADDR          32'h10002000
`define SOC_BOARD_LEDR_ADDR          32'h10002000
`define SOC_BOARD_LEDG_ADDR          32'h10002004
`define SOC_BOARD_SW_ADDR            32'h10002008
`define SOC_BOARD_KEY_ADDR           32'h1000200c
`define SOC_BOARD_END_ADDR           32'h10002010

// TSE wrapper CPU-facing control and TX/RX MMIO window.
`define SOC_TSE_BASE_ADDR            32'h10003000
`define SOC_TSE_END_ADDR             32'h10003100

`endif
