`include "tse_addr_map.svh"

// CPU-facing TSE MMIO wrapper.
//
// This layer partitions the control/CSR registers from the packet-stream MMIO
// window and combines their readback. BOARD_DE2115 builds connect its CSR and
// stream ports to the generated Intel TSE only through tse_mii_board_if.
// The legacy phy_* probe outputs below remain idle; this module never drives
// board MII traffic. It is not a MAC, SGDMA, TCP/IP stack, or CPU component.
module tse_mac_wrapper #(parameter integer DMA_ENABLE = 0)(
    // CPU-facing MMIO/probe clock. PHY and MAC datapath clocks remain
    // separate from this control clock.
    input clk,
    input rst_n,

    // CPU-facing MMIO request selected by simple_bus.
    input cpu_mem_write,
    input cpu_mem_read,
    input [31:0] cpu_addr,
    input [31:0] cpu_wdata,
    output [31:0] cpu_rdata,

    // Avalon-MM-like TSE CSR command/response path.
    output [9:0] tse_csr_address,
    output tse_csr_read,
    output tse_csr_write,
    output [31:0] tse_csr_writedata,
    input [31:0] tse_csr_readdata,
    input tse_csr_waitrequest,
    input tse_csr_readdatavalid,

    // Avalon-ST TX path from the MMIO packet buffer toward TSE.
    output [31:0] tse_tx_data,
    output [1:0] tse_tx_empty,
    output tse_tx_valid,
    output tse_tx_startofpacket,
    output tse_tx_endofpacket,
    input tse_tx_ready,

    // Avalon-ST RX path from TSE into the MMIO packet buffer.
    input [31:0] tse_rx_data,
    input [1:0] tse_rx_empty,
    input tse_rx_valid,
    input tse_rx_startofpacket,
    input tse_rx_endofpacket,
    output tse_rx_ready,

    // CPU-visible MII monitor window.  The monitor itself lives at the
    // board-side MII boundary (tse_mii_board_if), not on these legacy probes.
    output mii_debug_mem_write,
    output mii_debug_mem_read,
    input [31:0] mii_debug_rdata,

    // External PHY MII-style pins for the first 10/100 bring-up target.
    input phy_tx_clk,
    input phy_rx_clk,
    input [3:0] phy_rxd,
    input phy_rx_dv,
    input phy_rx_er,
    output [3:0] phy_txd,
    output phy_tx_en,
    output phy_tx_er,
    output phy_mdc,
    input phy_mdio_in,
    output phy_mdio_out,
    output phy_mdio_oe,
    output phy_reset_n,
    input dma_lock, input dma_direction,
    input dma_commit, input dma_cancel, input dma_rx_pop,
    input dma_tx_autorun, input dma_mode_active,
    input [31:0] dma_length,
    input dma_req, input dma_write, input [10:0] dma_addr,
    input [31:0] dma_wdata, input [3:0] dma_byteena,
    output dma_ready, output dma_rvalid, output [31:0] dma_rdata,
    output dma_rx_available, output [15:0] dma_rx_length,
    output dma_tx_available, output dma_conflict
);

    wire probe_enable;
    wire soft_reset_req;
    wire tx_fifo_empty;
    wire tx_fifo_full;
    wire rx_fifo_empty;
    wire rx_fifo_full;
    wire [31:0] regs_rdata;
    wire [31:0] stream_rdata;
    wire stream_mmio_sel;
    wire mii_debug_mmio_sel;

    // Address macros define the ownership boundary: control/CSR below this
    // window, packet movement inside it, and any later-defined windows above.
    assign stream_mmio_sel = (cpu_addr >= `TSE_MMIO_STREAM_CTRL_ADDR) &&
                             (cpu_addr < `TSE_MMIO_MII_DEBUG_CONTROL_ADDR);
    assign mii_debug_mmio_sel = (cpu_addr >= `TSE_MMIO_MII_DEBUG_CONTROL_ADDR) &&
                                (cpu_addr <= `TSE_MMIO_MII_DEBUG_STATUS_ADDR);
    assign mii_debug_mem_write = cpu_mem_write && mii_debug_mmio_sel;
    assign mii_debug_mem_read = cpu_mem_read && mii_debug_mmio_sel;
    assign cpu_rdata = mii_debug_mmio_sel ? mii_debug_rdata :
                       (stream_mmio_sel ? stream_rdata : regs_rdata);

    tse_mmio_regs u_tse_mmio_regs (
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(cpu_mem_write),
        .mem_read(cpu_mem_read),
        .addr(cpu_addr),
        .din(cpu_wdata),
        .dout(regs_rdata),
        .probe_enable(probe_enable),
        .soft_reset_req(soft_reset_req),
        .csr_address(tse_csr_address),
        .csr_writedata(tse_csr_writedata),
        .csr_read(tse_csr_read),
        .csr_write(tse_csr_write),
        .csr_readdata(tse_csr_readdata),
        .csr_waitrequest(tse_csr_waitrequest),
        .csr_readdatavalid(tse_csr_readdatavalid),
        .tx_fifo_empty(tx_fifo_empty),
        .tx_fifo_full(tx_fifo_full),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_full(rx_fifo_full)
    );

    tse_stream_fifo_stub #(.DMA_ENABLE(DMA_ENABLE)) u_tse_stream_fifo_stub (
        .dma_lock(dma_lock), .dma_direction(dma_direction),
        .dma_commit(dma_commit), .dma_cancel(dma_cancel),
        .dma_rx_pop(dma_rx_pop), .dma_tx_autorun(dma_tx_autorun),
        .dma_mode_active(dma_mode_active), .dma_length(dma_length),
        .dma_req(dma_req), .dma_write(dma_write), .dma_addr(dma_addr),
        .dma_wdata(dma_wdata), .dma_byteena(dma_byteena),
        .dma_ready(dma_ready), .dma_rvalid(dma_rvalid), .dma_rdata(dma_rdata),
        .dma_rx_available(dma_rx_available), .dma_rx_length(dma_rx_length),
        .dma_tx_available(dma_tx_available), .dma_conflict(dma_conflict),
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(cpu_mem_write && stream_mmio_sel),
        .mem_read(cpu_mem_read && stream_mmio_sel),
        .addr(cpu_addr),
        .din(cpu_wdata),
        .dout(stream_rdata),
        .tx_fifo_empty(tx_fifo_empty),
        .tx_fifo_full(tx_fifo_full),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_full(rx_fifo_full),
        .tx_st_data(tse_tx_data),
        .tx_st_empty(tse_tx_empty),
        .tx_st_valid(tse_tx_valid),
        .tx_st_startofpacket(tse_tx_startofpacket),
        .tx_st_endofpacket(tse_tx_endofpacket),
        .tx_st_ready(tse_tx_ready),
        .rx_st_data(tse_rx_data),
        .rx_st_empty(tse_rx_empty),
        .rx_st_valid(tse_rx_valid),
        .rx_st_startofpacket(tse_rx_startofpacket),
        .rx_st_endofpacket(tse_rx_endofpacket),
        .rx_st_ready(tse_rx_ready)
    );

    assign phy_txd = 4'b0;
    assign phy_tx_en = 1'b0;
    assign phy_tx_er = 1'b0;
    assign phy_mdc = 1'b0;
    assign phy_mdio_out = 1'b0;
    assign phy_mdio_oe = 1'b0;
    assign phy_reset_n = rst_n && probe_enable && !soft_reset_req;

    wire unused_phy_inputs;
    assign unused_phy_inputs = phy_tx_clk ^ phy_rx_clk ^ phy_rx_dv ^
                               phy_rx_er ^ phy_rxd[0] ^ phy_rxd[1] ^
                               phy_rxd[2] ^ phy_rxd[3] ^ phy_mdio_in;

endmodule
