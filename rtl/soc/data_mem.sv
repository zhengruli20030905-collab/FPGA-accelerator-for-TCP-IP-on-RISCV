`include "soc_addr_map.svh"
`include "v40_clock_config.svh"

// REAL/SOC-STRUCTURE COMPATIBILITY WRAPPER
//
// data_mem is the integration point seen by Mem_stage. It instantiates RAM,
// UART, timer, GPIO, MDIO, and the CPU-facing TSE wrapper; simple_bus alone owns
// address decode and read-data selection. In BOARD_DE2115 builds it also joins
// the TSE CSR/stream boundary to tse_mii_board_if. It does not implement packet
// buffering or drive MII data itself.
module data_mem(
    input clk,
    input rst_n,
    input mem_write,
    input mem_read,
    input req_start,
    input [2:0] mem_funct3,
    input [31:0] addr,
    input [31:0] din,
    output logic [31:0] dout,
    output logic req_ready,
    output logic rsp_valid,
    output logic rsp_error
`ifdef BOARD_DE2115
    ,
    input [17:0] board_sw,
    input [3:0] board_key,
    output [17:0] board_ledr,
    output [8:0] board_ledg,
    output uart_txd,
    output enet0_rst_n,
    output enet0_mdc,
    input enet0_mdio_in,
    output enet0_mdio_drive_low,
    input enet0_tx_clk,
    output [3:0] enet0_tx_data,
    output enet0_tx_en,
    output enet0_tx_er,
    input enet0_rx_clk,
    input [3:0] enet0_rx_data,
    input enet0_rx_dv,
    input enet0_rx_er,
    input enet0_rx_crs,
    input enet0_rx_col,
    input enet0_link100
`endif
`ifdef TSE_NET_SIM
    ,
    input [31:0] sim_tse_rx_data,
    input [1:0] sim_tse_rx_empty,
    input sim_tse_rx_valid,
    input sim_tse_rx_startofpacket,
    input sim_tse_rx_endofpacket,
    output sim_tse_rx_ready,
    output [31:0] sim_tse_tx_data,
    output [1:0] sim_tse_tx_empty,
    output sim_tse_tx_valid,
    output sim_tse_tx_startofpacket,
    output sim_tse_tx_endofpacket,
    input sim_tse_tx_ready
`endif
);

    logic [31:0] bus_dout;
    logic ram_response_pending;
    wire request_is_ram = (addr >= `SOC_DATA_RAM_START_ADDR) &&
                          (addr < `SOC_DATA_RAM_END_ADDR);
    wire request_accept = req_start && req_ready;

`ifdef V40_RANDOM_DMEM_WAIT
    integer sim_wait_max;
    logic [7:0] sim_wait_count;
    logic sim_wait_active;
    logic [15:0] sim_wait_lfsr;

    initial begin
        sim_wait_max = 3;
        if (!$value$plusargs("DMEM_WAIT_MAX=%d", sim_wait_max))
            sim_wait_max = 3;
    end

    assign req_ready = sim_wait_active && (sim_wait_count == 0);

    // Simulation-only ready backpressure. The request address/control remain
    // stable in Mem_stage until request_accept. This logic is not present in
    // either Quartus board revision.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sim_wait_count <= 8'b0;
            sim_wait_active <= 1'b0;
            sim_wait_lfsr <= 16'h1ACE;
        end else begin
            sim_wait_lfsr <= {sim_wait_lfsr[14:0],
                              sim_wait_lfsr[15] ^ sim_wait_lfsr[13] ^
                              sim_wait_lfsr[12] ^ sim_wait_lfsr[10]};
            if (!sim_wait_active && req_start) begin
                sim_wait_active <= 1'b1;
                sim_wait_count <= sim_wait_lfsr[7:0] % (sim_wait_max + 1);
            end else if (sim_wait_active && (sim_wait_count != 0)) begin
                sim_wait_count <= sim_wait_count - 8'd1;
            end else if (request_accept) begin
                sim_wait_active <= 1'b0;
            end
        end
    end
`else
    assign req_ready = 1'b1;
`endif
    assign rsp_error = 1'b0;

    // MMIO data is sampled on the request edge, so side-effecting reads are
    // asserted exactly once. The synchronous M9K response is sampled one edge
    // later. Both cases then use the same explicit rsp_valid contract.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid <= 1'b0;
            dout <= 32'b0;
            ram_response_pending <= 1'b0;
        end else begin
            rsp_valid <= 1'b0;
            if (ram_response_pending) begin
                dout <= bus_dout;
                rsp_valid <= 1'b1;
                ram_response_pending <= 1'b0;
            end
            if (request_accept) begin
                if (mem_read && request_is_ram) begin
                    ram_response_pending <= 1'b1;
                end else begin
                    dout <= mem_read ? bus_dout : 32'b0;
                    rsp_valid <= 1'b1;
                end
            end
        end
    end

    // One qualified read/write pair per simple_bus endpoint.
    wire ram_mem_write;
    wire ram_mem_read;
    wire uart_mem_write;
    wire uart_mem_read;
    wire timer_mem_write;
    wire timer_mem_read;
    wire board_mem_write;
    wire board_mem_read;
    wire mdio_mem_write;
    wire mdio_mem_read;
    wire tse_mem_write;
    wire tse_mem_read;
    wire dma_mem_write, dma_mem_read;
    wire [31:0] dma_dout;
    wire dma_enabled, dma_busy, dma_dmem_access_active;
    wire dma_packet_lock, dma_direction, dma_commit, dma_cancel;
    wire dma_rx_pop, dma_tx_autorun;
    wire dma_descriptor_lock_valid, dma_payload_lock_valid;
    wire [31:0] dma_descriptor_lock_addr, dma_descriptor_lock_length;
    wire [31:0] dma_payload_lock_addr, dma_payload_lock_length;
    wire [31:0] dma_length;
    wire dma_dm_req, dma_dm_write, dma_dm_ready, dma_dm_rvalid;
    wire [31:0] dma_dm_addr, dma_dm_wdata, dma_dm_rdata;
    wire [3:0] dma_byteena;
    wire [3:0] dma_packet_byteena;
    wire dma_pkt_req, dma_pkt_write, dma_pkt_ready, dma_pkt_rvalid;
    wire [10:0] dma_pkt_addr;
    wire [31:0] dma_pkt_wdata, dma_pkt_rdata;
    wire dma_rx_available, dma_tx_available;
    wire dma_descriptor_conflict, dma_payload_conflict, dma_pkt_conflict;
    wire [15:0] dma_rx_length;

    packet_dma u_packet_dma (
        .clk(clk), .rst_n(rst_n),
        .mem_write(dma_mem_write), .mem_read(dma_mem_read), .addr(addr), .din(din), .dout(dma_dout),
        .rx_available(dma_rx_available), .rx_length(dma_rx_length), .tx_available(dma_tx_available),
        .descriptor_conflict(dma_descriptor_conflict),
        .payload_conflict(dma_payload_conflict),
        .packet_conflict(dma_pkt_conflict),
        .enabled(dma_enabled), .busy(dma_busy),
        .dmem_access_active(dma_dmem_access_active),
        .descriptor_lock_valid(dma_descriptor_lock_valid),
        .descriptor_lock_addr(dma_descriptor_lock_addr),
        .descriptor_lock_length(dma_descriptor_lock_length),
        .payload_lock_valid(dma_payload_lock_valid),
        .payload_lock_addr(dma_payload_lock_addr),
        .payload_lock_length(dma_payload_lock_length),
        .packet_lock(dma_packet_lock), .direction(dma_direction),
        .length(dma_length), .commit(dma_commit), .cancel(dma_cancel),
        .rx_pop(dma_rx_pop), .tx_autorun(dma_tx_autorun),
        .dm_req(dma_dm_req), .dm_write(dma_dm_write), .dm_addr(dma_dm_addr),
        .dm_wdata(dma_dm_wdata), .dm_byteena(dma_byteena),
        .dm_ready(dma_dm_ready), .dm_rvalid(dma_dm_rvalid), .dm_rdata(dma_dm_rdata),
        .pkt_req(dma_pkt_req), .pkt_write(dma_pkt_write), .pkt_addr(dma_pkt_addr), .pkt_wdata(dma_pkt_wdata),
        .pkt_byteena(dma_packet_byteena),
        .pkt_ready(dma_pkt_ready), .pkt_rvalid(dma_pkt_rvalid), .pkt_rdata(dma_pkt_rdata)
    );

    // Endpoint read data returned through the simple_bus mux.
    wire [31:0] ram_dout;
    wire [31:0] uart_dout;
    wire [31:0] timer_dout;
    wire [31:0] board_dout;
    wire [31:0] mdio_dout;
    wire [31:0] tse_dout;

    // Generated-TSE CSR command/response channel.
    wire [9:0] tse_csr_address;
    wire tse_csr_read;
    wire tse_csr_write;
    wire [31:0] tse_csr_writedata;
    logic [31:0] tse_csr_readdata;
    wire tse_csr_waitrequest;
    logic tse_csr_readdatavalid;
`ifndef BOARD_DE2115
    // Non-board firmware simulation models the two alignment CSRs that v24
    // programs. Their reset values match ENABLE_SHIFT16=1 in the generated IP.
    logic [31:0] sim_tse_tx_cmd_stat;
    logic [31:0] sim_tse_rx_cmd_stat;
`endif

    // Avalon-ST packet channels between the MMIO packet buffer and MAC side.
    wire [31:0] tse_tx_data;
    wire [1:0] tse_tx_empty;
    wire tse_tx_valid;
    wire tse_tx_startofpacket;
    wire tse_tx_endofpacket;
    wire tse_tx_ready;
    wire [31:0] tse_rx_data;
    wire [1:0] tse_rx_empty;
    wire tse_rx_valid;
    wire tse_rx_startofpacket;
    wire tse_rx_endofpacket;
    wire tse_rx_ready;
    wire mii_debug_mem_write;
    wire mii_debug_mem_read;
    wire [31:0] mii_debug_rdata;
    wire [3:0] tse_phy_txd;
    wire tse_phy_tx_en;
    wire tse_phy_tx_er;
    wire tse_phy_mdc;
    wire tse_phy_mdio_out;
    wire tse_phy_mdio_oe;
    wire tse_phy_reset_n;
    wire tse_eth_mode;
    wire tse_ena_10;

    wire uart_txd_i;
    wire [17:0] board_ledr_i;
    wire [8:0] board_ledg_i;
    wire phy_reset_n_i;
    wire mdio_mdc_i;
    wire mdio_drive_low_i;

`ifdef BOARD_DE2115
    localparam integer BOARD_CLK_HZ = `V40_SOC_CLK_HZ;
    localparam integer PHY_RESET_CYCLES = `V40_PHY_RESET_CYCLES;
    localparam integer SOC_CLK_HZ = BOARD_CLK_HZ;
    wire [17:0] board_sw_i = board_sw;
    wire [3:0] board_key_i = board_key;
    wire mdio_in_i = enet0_mdio_in;

    assign board_ledr = board_ledr_i;
    assign board_ledg = board_ledg_i;
    assign uart_txd = uart_txd_i;
    assign enet0_rst_n = phy_reset_n_i;
    assign enet0_mdc = mdio_mdc_i;
    assign enet0_mdio_drive_low = mdio_drive_low_i;

    localparam integer PHY_SIM_MODEL = 0;
`else
    localparam integer SOC_CLK_HZ = `V40_SOC_CLK_HZ;
    wire [17:0] board_sw_i = 18'b0;
    wire [3:0] board_key_i = 4'hf;
    wire mdio_in_i = 1'b1;

    localparam integer PHY_SIM_MODEL = 1;
    localparam integer PHY_RESET_CYCLES = 100;
`endif

    // CPU MEM-stage request decode and readback mux.
    simple_bus u_simple_bus (
        .dma_dout(dma_dout), .dma_mem_write(dma_mem_write), .dma_mem_read(dma_mem_read),
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(mem_write),
        .mem_read(mem_read),
        .addr(addr),
        .ram_dout(ram_dout),
        .uart_dout(uart_dout),
        .timer_dout(timer_dout),
        .board_dout(board_dout),
        .mdio_dout(mdio_dout),
        .tse_dout(tse_dout),
        .ram_mem_write(ram_mem_write),
        .ram_mem_read(ram_mem_read),
        .uart_mem_write(uart_mem_write),
        .uart_mem_read(uart_mem_read),
        .timer_mem_write(timer_mem_write),
        .timer_mem_read(timer_mem_read),
        .board_mem_write(board_mem_write),
        .board_mem_read(board_mem_read),
        .mdio_mem_write(mdio_mem_write),
        .mdio_mem_read(mdio_mem_read),
        .tse_mem_write(tse_mem_write),
        .tse_mem_read(tse_mem_read),
        .dout(bus_dout)
    );

    data_ram #(.DMA_ENABLE(1)) u_data_ram (
        .dma_access_active(dma_dmem_access_active),
        .descriptor_lock_valid(dma_descriptor_lock_valid),
        .descriptor_lock_addr(dma_descriptor_lock_addr),
        .descriptor_lock_length(dma_descriptor_lock_length),
        .payload_lock_valid(dma_payload_lock_valid),
        .payload_lock_addr(dma_payload_lock_addr),
        .payload_lock_length(dma_payload_lock_length),
        .dma_req(dma_dm_req), .dma_write(dma_dm_write), .dma_addr(dma_dm_addr),
        .dma_wdata(dma_dm_wdata), .dma_byteena(dma_byteena),
        .dma_ready(dma_dm_ready), .dma_rvalid(dma_dm_rvalid), .dma_rdata(dma_dm_rdata),
        .descriptor_conflict(dma_descriptor_conflict),
        .payload_conflict(dma_payload_conflict),
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(ram_mem_write),
        .mem_read(ram_mem_read),
        .mem_funct3(mem_funct3),
        .addr(addr),
        .din(din),
        .dout(ram_dout)
    );

    uart_mmio #(
        .CLK_HZ(SOC_CLK_HZ),
        .BAUD(`V40_UART_BAUD)
    ) u_uart_mmio (
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(uart_mem_write),
        .mem_read(uart_mem_read),
        .addr(addr),
        .din(din),
        .dout(uart_dout),
        .uart_txd(uart_txd_i)
    );

    timer_mmio u_timer_mmio (
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(timer_mem_write),
        .mem_read(timer_mem_read),
        .addr(addr),
        .din(din),
        .dout(timer_dout)
    );

    board_gpio_mmio u_board_gpio_mmio (
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(board_mem_write),
        .mem_read(board_mem_read),
        .addr(addr),
        .din(din),
        .sw_in(board_sw_i),
        .key_in(board_key_i),
        .ledr_out(board_ledr_i),
        .ledg_out(board_ledg_i),
        .dout(board_dout)
    );

    phy_mdio_mmio #(
        .CLK_HZ(SOC_CLK_HZ),
        .MDC_HZ(`V40_MDIO_MDC_HZ),
        .HW_RESET_CYCLES(PHY_RESET_CYCLES),
        .SIM_PHY_MODEL(PHY_SIM_MODEL)
    ) u_phy_mdio_mmio (
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(mdio_mem_write),
        .mem_read(mdio_mem_read),
        .addr(addr),
        .din(din),
        .mdio_in(mdio_in_i),
        .dout(mdio_dout),
        .phy_reset_n(phy_reset_n_i),
        .mdc(mdio_mdc_i),
        .mdio_drive_low(mdio_drive_low_i)
    );

`ifdef BOARD_DE2115
    // The only custom-RTL boundary to the generated Intel TSE and ENET0 MII.
    tse_mii_board_if u_tse_mii_board_if (
        .clk(clk),
        .rst_n(rst_n),
        .csr_address(tse_csr_address),
        .csr_read(tse_csr_read),
        .csr_write(tse_csr_write),
        .csr_writedata(tse_csr_writedata),
        .csr_readdata(tse_csr_readdata),
        .csr_waitrequest(tse_csr_waitrequest),
        .csr_readdatavalid(tse_csr_readdatavalid),
        .tx_data(tse_tx_data),
        .tx_empty(tse_tx_empty),
        .tx_valid(tse_tx_valid),
        .tx_startofpacket(tse_tx_startofpacket),
        .tx_endofpacket(tse_tx_endofpacket),
        .tx_ready(tse_tx_ready),
        .rx_data(tse_rx_data),
        .rx_empty(tse_rx_empty),
        .rx_valid(tse_rx_valid),
        .rx_startofpacket(tse_rx_startofpacket),
        .rx_endofpacket(tse_rx_endofpacket),
        .rx_ready(tse_rx_ready),
        .mii_debug_mem_write(mii_debug_mem_write),
        .mii_debug_mem_read(mii_debug_mem_read),
        .mii_debug_addr(addr),
        .mii_debug_wdata(din),
        .mii_debug_rdata(mii_debug_rdata),
        .phy_reset_n(phy_reset_n_i),
        .enet0_tx_clk(enet0_tx_clk),
        .enet0_rx_clk(enet0_rx_clk),
        .enet0_rx_data(enet0_rx_data),
        .enet0_rx_dv(enet0_rx_dv),
        .enet0_rx_er(enet0_rx_er),
        .enet0_rx_crs(enet0_rx_crs),
        .enet0_rx_col(enet0_rx_col),
        .enet0_link100(enet0_link100),
        .enet0_tx_data(enet0_tx_data),
        .enet0_tx_en(enet0_tx_en),
        .enet0_tx_er(enet0_tx_er),
        .eth_mode(tse_eth_mode),
        .ena_10(tse_ena_10)
    );
`else
    assign tse_csr_waitrequest = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tse_csr_readdata <= 32'b0;
            tse_csr_readdatavalid <= 1'b0;
            sim_tse_tx_cmd_stat <= 32'h00040000;
            sim_tse_rx_cmd_stat <= 32'h02000000;
        end else begin
            tse_csr_readdatavalid <= tse_csr_read;
            if (tse_csr_write) begin
                case (tse_csr_address)
                    10'h03a: sim_tse_tx_cmd_stat <= tse_csr_writedata;
                    10'h03b: sim_tse_rx_cmd_stat <= tse_csr_writedata;
                    default: begin
                    end
                endcase
            end
            if (tse_csr_read) begin
                case (tse_csr_address)
                    10'h03a: tse_csr_readdata <= sim_tse_tx_cmd_stat;
                    10'h03b: tse_csr_readdata <= sim_tse_rx_cmd_stat;
                    default: tse_csr_readdata <= {16'h5453, 6'b0,
                                                  tse_csr_address};
                endcase
            end
        end
    end

    // Non-board simulation keeps the synthetic stream boundary so CPU/MMIO
    // tests do not need the encrypted generated TSE simulation model.
`ifdef TSE_NET_SIM
    assign tse_tx_ready = sim_tse_tx_ready;
    assign tse_rx_data = sim_tse_rx_data;
    assign tse_rx_empty = sim_tse_rx_empty;
    assign tse_rx_valid = sim_tse_rx_valid;
    assign tse_rx_startofpacket = sim_tse_rx_startofpacket;
    assign tse_rx_endofpacket = sim_tse_rx_endofpacket;
    assign sim_tse_rx_ready = tse_rx_ready;
    assign sim_tse_tx_data = tse_tx_data;
    assign sim_tse_tx_empty = tse_tx_empty;
    assign sim_tse_tx_valid = tse_tx_valid;
    assign sim_tse_tx_startofpacket = tse_tx_startofpacket;
    assign sim_tse_tx_endofpacket = tse_tx_endofpacket;
`else
    assign tse_tx_ready = 1'b1;
    assign tse_rx_data = 32'b0;
    assign tse_rx_empty = 2'b0;
    assign tse_rx_valid = 1'b0;
    assign tse_rx_startofpacket = 1'b0;
    assign tse_rx_endofpacket = 1'b0;
`endif
    assign tse_eth_mode = 1'b0;
    assign tse_ena_10 = 1'b0;
    // TSE_NET_SIM is intentionally not an MII-side generated-IP
    // execution path.  A zero status makes firmware report this as unavailable
    // instead of inferring physical-wire activity from FF-side counters.
    assign mii_debug_rdata = 32'b0;
`endif

    // CPU-facing TSE MMIO control registers and packet-stream window.
    tse_mac_wrapper #(.DMA_ENABLE(1)) u_tse_mac_wrapper (
        .dma_lock(dma_packet_lock), .dma_direction(dma_direction),
        .dma_commit(dma_commit), .dma_cancel(dma_cancel),
        .dma_rx_pop(dma_rx_pop), .dma_tx_autorun(dma_tx_autorun),
        .dma_mode_active(dma_enabled), .dma_length(dma_length),
        .dma_req(dma_pkt_req), .dma_write(dma_pkt_write), .dma_addr(dma_pkt_addr),
        .dma_wdata(dma_pkt_wdata), .dma_byteena(dma_packet_byteena),
        .dma_ready(dma_pkt_ready), .dma_rvalid(dma_pkt_rvalid), .dma_rdata(dma_pkt_rdata),
        .dma_rx_available(dma_rx_available), .dma_rx_length(dma_rx_length),
        .dma_tx_available(dma_tx_available), .dma_conflict(dma_pkt_conflict),
        .clk(clk),
        .rst_n(rst_n),
        .cpu_mem_write(tse_mem_write),
        .cpu_mem_read(tse_mem_read),
        .cpu_addr(addr),
        .cpu_wdata(din),
        .cpu_rdata(tse_dout),
        .tse_csr_address(tse_csr_address),
        .tse_csr_read(tse_csr_read),
        .tse_csr_write(tse_csr_write),
        .tse_csr_writedata(tse_csr_writedata),
        .tse_csr_readdata(tse_csr_readdata),
        .tse_csr_waitrequest(tse_csr_waitrequest),
        .tse_csr_readdatavalid(tse_csr_readdatavalid),
        .tse_tx_data(tse_tx_data),
        .tse_tx_empty(tse_tx_empty),
        .tse_tx_valid(tse_tx_valid),
        .tse_tx_startofpacket(tse_tx_startofpacket),
        .tse_tx_endofpacket(tse_tx_endofpacket),
        .tse_tx_ready(tse_tx_ready),
        .tse_rx_data(tse_rx_data),
        .tse_rx_empty(tse_rx_empty),
        .tse_rx_valid(tse_rx_valid),
        .tse_rx_startofpacket(tse_rx_startofpacket),
        .tse_rx_endofpacket(tse_rx_endofpacket),
        .tse_rx_ready(tse_rx_ready),
        .mii_debug_mem_write(mii_debug_mem_write),
        .mii_debug_mem_read(mii_debug_mem_read),
        .mii_debug_rdata(mii_debug_rdata),
        .phy_tx_clk(clk),
        .phy_rx_clk(clk),
        .phy_rxd(4'b0),
        .phy_rx_dv(1'b0),
        .phy_rx_er(1'b0),
        .phy_txd(tse_phy_txd),
        .phy_tx_en(tse_phy_tx_en),
        .phy_tx_er(tse_phy_tx_er),
        .phy_mdc(tse_phy_mdc),
        .phy_mdio_in(1'b1),
        .phy_mdio_out(tse_phy_mdio_out),
        .phy_mdio_oe(tse_phy_mdio_oe),
        .phy_reset_n(tse_phy_reset_n)
    );

    wire unused_tse_wrapper_phy;
    assign unused_tse_wrapper_phy = tse_phy_txd[0] ^ tse_phy_tx_en ^
                                tse_phy_tx_er ^ tse_phy_mdc ^
                                tse_phy_mdio_out ^ tse_phy_mdio_oe ^
                                tse_phy_reset_n ^ tse_eth_mode ^ tse_ena_10;

endmodule
