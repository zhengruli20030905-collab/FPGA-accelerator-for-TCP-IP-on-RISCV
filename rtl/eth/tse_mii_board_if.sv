// Board-only Intel TSE MII integration wrapper.
//
// This is the only custom-RTL bridge between the CPU-facing CSR/stream channels
// and the generated Intel TSE 10/100 MII MAC. The generated IP owns the MII
// packet datapath; MDIO remains owned by mdio_master / phy_mdio_mmio.
//
// Clock-domain contract:
// - The generated TSE comments identify ff_tx_* as the transmit interface
//   clocked by ff_tx_clk.
// - ff_tx_clk is this module's clk, the CPU/MMIO/TX-adapter 25 MHz domain.
//   The custom TX path is therefore single-clock.
// - ENET0_TX_CLK is connected only to the generated TSE MII tx_clk port.
//   Do not drive ENET0_TX_CLK-domain logic directly from the CPU/MMIO TX
//   adapter unless a real async FIFO or dual-clock bridge is added.
module tse_mii_board_if(
    input clk,
    input rst_n,

    input [9:0] csr_address,
    input csr_read,
    input csr_write,
    input [31:0] csr_writedata,
    output [31:0] csr_readdata,
    output csr_waitrequest,
    output csr_readdatavalid,

    input [31:0] tx_data,
    input [1:0] tx_empty,
    input tx_valid,
    input tx_startofpacket,
    input tx_endofpacket,
    output tx_ready,

    output [31:0] rx_data,
    output [1:0] rx_empty,
    output rx_valid,
    output rx_startofpacket,
    output rx_endofpacket,
    input rx_ready,

    // This MMIO command/readback path belongs to the custom monitor below.
    // It is intentionally separate from the generated TSE register path.
    input mii_debug_mem_write,
    input mii_debug_mem_read,
    input [31:0] mii_debug_addr,
    input [31:0] mii_debug_wdata,
    output [31:0] mii_debug_rdata,

    input phy_reset_n,
    input enet0_tx_clk,
    input enet0_rx_clk,
    input [3:0] enet0_rx_data,
    input enet0_rx_dv,
    input enet0_rx_er,
    input enet0_rx_crs,
    input enet0_rx_col,
    input enet0_link100,

    output [3:0] enet0_tx_data,
    output enet0_tx_en,
    output enet0_tx_er,
    output eth_mode,
    output ena_10
);

    // pending means a command is held at the generated register port.
    // busy_seen records acceptance; completion is busy returning low.
    reg csr_pending;
    reg csr_pending_read;
    reg csr_pending_write;
    reg csr_busy_seen;
    reg [7:0] tse_reg_addr;
    reg [31:0] tse_reg_data_in;
    reg [31:0] csr_readdata_r;
    reg csr_readdatavalid_r;

    wire [31:0] tse_reg_data_out;
    wire tse_reg_busy;
    wire tse_reset_active_high;
    wire [5:0] rx_error;
    wire mii_debug_rst_n;
    wire [31:0] tse_ff_tx_data;
    wire [1:0] tse_ff_tx_empty;
    wire [31:0] tse_ff_rx_data;
    wire [1:0] tse_ff_rx_empty;

    // Reset polarity conversion is confined to the generated-IP boundary.
    assign tse_reset_active_high = !rst_n || !phy_reset_n;
    // rst_n is the existing active-low CPU reset naming convention.  The
    // monitor synchronizes release again in each MII source domain.
    assign mii_debug_rst_n = rst_n && phy_reset_n;

    // The CPU-facing staging register accepts one-cycle commands. This bridge
    // then holds the generated TSE register read/write until reg_busy has
    // asserted and deasserted, matching the generated example testbench.
    assign csr_waitrequest = csr_pending;
    assign csr_readdata = csr_readdata_r;
    assign csr_readdatavalid = csr_readdatavalid_r;

    // Internal packet RAM words place the earliest frame byte in [7:0].
    // Intel TSE consumes/produces the earliest byte in [31:24], so the
    // conversion belongs at this external-IP boundary in both directions.
    tse_stream_byte_order_adapter u_stream_byte_order_adapter (
        .internal_tx_data(tx_data),
        .internal_tx_empty(tx_empty),
        .mac_tx_data(tse_ff_tx_data),
        .mac_tx_empty(tse_ff_tx_empty),
        .mac_rx_data(tse_ff_rx_data),
        .mac_rx_empty(tse_ff_rx_empty),
        .internal_rx_data(rx_data),
        .internal_rx_empty(rx_empty)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_pending <= 1'b0;
            csr_pending_read <= 1'b0;
            csr_pending_write <= 1'b0;
            csr_busy_seen <= 1'b0;
            tse_reg_addr <= 8'd0;
            tse_reg_data_in <= 32'd0;
            csr_readdata_r <= 32'd0;
            csr_readdatavalid_r <= 1'b0;
        end else begin
            csr_readdatavalid_r <= 1'b0;

            if (!csr_pending && (csr_read || csr_write)) begin
                csr_pending <= 1'b1;
                csr_pending_read <= csr_read;
                csr_pending_write <= csr_write;
                csr_busy_seen <= 1'b0;
                tse_reg_addr <= csr_address[7:0];
                tse_reg_data_in <= csr_writedata;
            end else if (csr_pending) begin
                if (tse_reg_busy) begin
                    csr_busy_seen <= 1'b1;
                end else if (csr_busy_seen) begin
                    if (csr_pending_read) begin
                        csr_readdata_r <= tse_reg_data_out;
                        csr_readdatavalid_r <= 1'b1;
                    end
                    csr_pending <= 1'b0;
                    csr_pending_read <= 1'b0;
                    csr_pending_write <= 1'b0;
                    csr_busy_seen <= 1'b0;
                end
            end
        end
    end

    tse_mac_mii_10_100 u_tse_mac_mii_10_100 (
        .clk(clk),
        .reset(tse_reset_active_high),
        .reg_addr(tse_reg_addr),
        .reg_data_out(tse_reg_data_out),
        .reg_rd(csr_pending && csr_pending_read),
        .reg_data_in(tse_reg_data_in),
        .reg_wr(csr_pending && csr_pending_write),
        .reg_busy(tse_reg_busy),
        .tx_clk(enet0_tx_clk),
        .rx_clk(enet0_rx_clk),
        .set_10(1'b0),
        .set_1000(1'b0),
        .eth_mode(eth_mode),
        .ena_10(ena_10),
        .m_rx_d(enet0_rx_data),
        .m_rx_en(enet0_rx_dv),
        .m_rx_err(enet0_rx_er),
        .m_tx_d(enet0_tx_data),
        .m_tx_en(enet0_tx_en),
        .m_tx_err(enet0_tx_er),
        .m_rx_crs(enet0_rx_crs),
        .m_rx_col(enet0_rx_col),
        .ff_rx_clk(clk),
        .ff_tx_clk(clk),
        .ff_rx_data(tse_ff_rx_data),
        .ff_rx_eop(rx_endofpacket),
        .rx_err(rx_error),
        .ff_rx_mod(tse_ff_rx_empty),
        // Stream-side backpressure from the single-frame RX buffer. This is
        // deliberately not the CPU-visible "complete frame ready" status.
        .ff_rx_rdy(rx_ready),
        .ff_rx_sop(rx_startofpacket),
        .ff_rx_dval(rx_valid),
        // ff_tx_* is synchronous to ff_tx_clk. In v15 ff_tx_clk == clk, so
        // tx_data/tx_valid/tx_ready stay in the CPU/MMIO/TX-adapter domain.
        .ff_tx_data(tse_ff_tx_data),
        .ff_tx_eop(tx_endofpacket),
        .ff_tx_err(1'b0),
        .ff_tx_mod(tse_ff_tx_empty),
        .ff_tx_rdy(tx_ready),
        .ff_tx_sop(tx_startofpacket),
        .ff_tx_wren(tx_valid)
    );

    // Observe the actual generated-TSE MII-side signals at this boundary.
    // No generated Intel source is edited, and no MII data bus crosses into
    // the CPU clock domain.
    tse_mii_debug_monitor u_mii_debug_monitor (
        .cpu_clk(clk),
        .rst_n(mii_debug_rst_n),
        .cpu_mem_write(mii_debug_mem_write),
        .cpu_mem_read(mii_debug_mem_read),
        .cpu_addr(mii_debug_addr),
        .cpu_wdata(mii_debug_wdata),
        .cpu_rdata(mii_debug_rdata),
        .enet0_tx_clk(enet0_tx_clk),
        .enet0_tx_data(enet0_tx_data),
        .enet0_tx_en(enet0_tx_en),
        .enet0_tx_er(enet0_tx_er),
        .enet0_rx_clk(enet0_rx_clk),
        .enet0_rx_data(enet0_rx_data),
        .enet0_rx_dv(enet0_rx_dv),
        .enet0_rx_er(enet0_rx_er)
    );

    wire unused_inputs;
    assign unused_inputs = enet0_link100 ^ rx_error[0];

endmodule
