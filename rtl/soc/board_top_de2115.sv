`include "v40_clock_config.svh"

// V40 formal 25 MHz DE2-115 top for ENET0 MII mode.
//
// MDIO/MDC ownership remains with the existing mdio_master path. Packet TX is
// driven through the generated Intel TSE 10/100 MII MAC.
module board_top_de2115(
    input CLOCK_50,
    input [3:0] KEY,
    input [17:0] SW,
    output [17:0] LEDR,
    output [8:0] LEDG,
    output UART_TXD,
    input UART_RXD,
    output UART_RTS,
    input UART_CTS,
    output ENET0_RST_N,
    output ENET0_MDC,
    inout ENET0_MDIO,
    input ENET0_INT_N,
    input ENET0_LINK100,
    output ENET0_GTX_CLK,
    input ENET0_TX_CLK,
    output [3:0] ENET0_TX_DATA,
    output ENET0_TX_EN,
    output ENET0_TX_ER,
    input ENET0_RX_CLK,
    input [3:0] ENET0_RX_DATA,
    input ENET0_RX_DV,
    input ENET0_RX_ER,
    input ENET0_RX_CRS,
    input ENET0_RX_COL
);

    wire cpu_clk;
    // KEY[0] and PLL lock form the asynchronous reset source.  reset_sync
    // then produces cpu_rst_n with synchronous release in the CPU clock domain.
    wire pll_reset;
    wire cpu_rst_n;
    wire pll_locked;
    wire cpu_reset_async_n;
    wire halted;
    wire mdio_in;
    wire mdio_drive_low;
    wire [17:0] board_sw_sync;
    wire [2:0] key31_sync;
    wire [2:0] key31_debounced;
    wire [0:0] key0_sync;
    wire [3:0] board_key_cpu;
    wire [3:0] status_sync;
    wire uart_rxd_sync;
    wire uart_cts_sync;
    wire enet0_int_n_sync;
    wire enet0_link100_sync;

    // altpll uses active-high areset; make that polarity adapter explicit.
    assign pll_reset = !KEY[0];

    cpu_pll_25m u_cpu_pll_25m (
        .inclk0(CLOCK_50),
        .pll_reset(pll_reset),
        .clk_out(cpu_clk),
        .locked(pll_locked)
    );

    assign cpu_reset_async_n = KEY[0] && pll_locked;

    reset_sync u_cpu_reset_sync (
        .clk(cpu_clk),
        .async_rst_n(cpu_reset_async_n),
        .rst_n(cpu_rst_n)
    );

    sync_2ff #(
        .WIDTH(18),
        .RESET_VALUE(18'b0)
    ) u_sw_sync (
        .clk(cpu_clk),
        .rst_n(cpu_rst_n),
        .async_in(SW),
        .sync_out(board_sw_sync)
    );

    sync_2ff #(
        .WIDTH(3),
        .RESET_VALUE(3'b111)
    ) u_key31_sync (
        .clk(cpu_clk),
        .rst_n(cpu_rst_n),
        .async_in(KEY[3:1]),
        .sync_out(key31_sync)
    );

    debounce #(
        .WIDTH(3),
        .STABLE_CYCLES(`V40_DEBOUNCE_CYCLES),
        .RESET_VALUE(3'b111)
    ) u_key31_debounce (
        .clk(cpu_clk),
        .rst_n(cpu_rst_n),
        .noisy_in(key31_sync),
        .clean_out(key31_debounced)
    );

    sync_2ff #(
        .WIDTH(1),
        .RESET_VALUE(1'b1)
    ) u_key0_sync (
        .clk(cpu_clk),
        .rst_n(cpu_rst_n),
        .async_in(KEY[0]),
        .sync_out(key0_sync)
    );

    sync_2ff #(
        .WIDTH(4),
        .RESET_VALUE(4'b1110)
    ) u_status_sync (
        .clk(cpu_clk),
        .rst_n(cpu_rst_n),
        .async_in({UART_RXD, UART_CTS, ENET0_INT_N, ENET0_LINK100}),
        .sync_out(status_sync)
    );

    assign {uart_rxd_sync, uart_cts_sync, enet0_int_n_sync, enet0_link100_sync} = status_sync;
    assign board_key_cpu = {key31_debounced, key0_sync[0]};

    assign ENET0_MDIO = mdio_drive_low ? 1'b0 : 1'bz;
    assign mdio_in = ENET0_MDIO;
    assign UART_RTS = 1'b0;
    assign ENET0_GTX_CLK = 1'b0; // Not used by the generated MII 10/100 MAC.

    rv32i_cpu u_rv32i_cpu (
        .clk(cpu_clk),
        .rst_n(cpu_rst_n),
        .halted(halted),
        .board_sw(board_sw_sync),
        .board_key(board_key_cpu),
        .board_ledr(LEDR),
        .board_ledg(LEDG),
        .uart_txd(UART_TXD),
        .enet0_rst_n(ENET0_RST_N),
        .enet0_mdc(ENET0_MDC),
        .enet0_mdio_in(mdio_in),
        .enet0_mdio_drive_low(mdio_drive_low),
        .enet0_tx_clk(ENET0_TX_CLK),
        .enet0_tx_data(ENET0_TX_DATA),
        .enet0_tx_en(ENET0_TX_EN),
        .enet0_tx_er(ENET0_TX_ER),
        .enet0_rx_clk(ENET0_RX_CLK),
        .enet0_rx_data(ENET0_RX_DATA),
        .enet0_rx_dv(ENET0_RX_DV),
        .enet0_rx_er(ENET0_RX_ER),
        .enet0_rx_crs(ENET0_RX_CRS),
        .enet0_rx_col(ENET0_RX_COL),
        .enet0_link100(enet0_link100_sync)
    );

    wire unused_inputs;
    assign unused_inputs = uart_rxd_sync ^ uart_cts_sync ^ enet0_int_n_sync ^
                           halted;

endmodule
