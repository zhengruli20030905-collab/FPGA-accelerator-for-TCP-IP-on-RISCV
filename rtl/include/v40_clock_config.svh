`ifndef V40_CLOCK_CONFIG_SVH
`define V40_CLOCK_CONFIG_SVH

// Formal v40 system-clock configuration.  These constants describe
// wall-clock requirements; pipeline depths and protocol state counts remain
// local to their owning modules.
`define V40_SOC_CLK_HZ          25_000_000
`define V40_UART_BAUD           115_200
`define V40_MDIO_MDC_HZ         1_000_000
`define V40_PHY_RESET_CYCLES    250_000
`define V40_DEBOUNCE_CYCLES     125_000

`endif
