`include "tse_addr_map.svh"

// Board-side MII activity monitor for the generated Intel TSE boundary.
//
// This module deliberately observes the MII pins outside the generated IP.
// It neither changes nor drives the MII datapath.  The CPU/MMIO clock is
// independent of ENET0_TX_CLK and ENET0_RX_CLK.
//
// CDC contract:
//   * TX/RX source domains count events in local binary counters and register
//     their Gray-coded forms.  Only the registered Gray forms cross to CPU.
//   * Every Gray bit has a two-flop synchronizer in the CPU domain; CPU-only
//     combinational Gray-to-binary conversion happens after synchronizer 2.
//   * CPU clear is a one-bit toggle.  It crosses to each MII domain through a
//     two-flop synchronizer, is consumed exactly once, then each source sends
//     its ack toggle back through another two-flop synchronizer.
//   * rst_n may assert asynchronously.  Its release is locally
//     synchronized before it releases either MII-domain state.  A stopped MII
//     clock therefore leaves the matching clear-pending bit asserted.
//
// Status CDC_VALID says the CPU-side synchronizer pipelines have had two CPU
// clocks after reset.  It is not a PHY-link indication and does not prove that
// an MII clock is toggling.
module tse_mii_debug_monitor #(
    parameter integer COUNTER_WIDTH = 32
)(
    // v21 reset contract: this active-low self-authored module input is rst_n.
    input  wire                     cpu_clk,
    input  wire                     rst_n,
    input  wire                     cpu_mem_write,
    input  wire                     cpu_mem_read,
    input  wire [31:0]              cpu_addr,
    input  wire [31:0]              cpu_wdata,
    output reg  [31:0]              cpu_rdata,

    // Real board-side MII signals.  Data nibbles are intentionally never
    // transferred to CPU; the defined counters are enable/error observables.
    input  wire                     enet0_tx_clk,
    input  wire [3:0]               enet0_tx_data,
    input  wire                     enet0_tx_en,
    input  wire                     enet0_tx_er,
    input  wire                     enet0_rx_clk,
    input  wire [3:0]               enet0_rx_data,
    input  wire                     enet0_rx_dv,
    input  wire                     enet0_rx_er
);

    localparam [31:0] MII_DEBUG_CONTROL_ADDR          = `TSE_MMIO_MII_DEBUG_CONTROL_ADDR;
    localparam [31:0] MII_TX_FRAME_COUNT_ADDR         = `TSE_MMIO_MII_TX_FRAME_COUNT_ADDR;
    localparam [31:0] MII_TX_ACTIVE_NIBBLE_COUNT_ADDR = `TSE_MMIO_MII_TX_ACTIVE_NIBBLE_COUNT_ADDR;
    localparam [31:0] MII_TX_ERROR_NIBBLE_COUNT_ADDR  = `TSE_MMIO_MII_TX_ERROR_NIBBLE_COUNT_ADDR;
    localparam [31:0] MII_RX_FRAME_COUNT_ADDR         = `TSE_MMIO_MII_RX_FRAME_COUNT_ADDR;
    localparam [31:0] MII_RX_ACTIVE_NIBBLE_COUNT_ADDR = `TSE_MMIO_MII_RX_ACTIVE_NIBBLE_COUNT_ADDR;
    localparam [31:0] MII_RX_ERROR_NIBBLE_COUNT_ADDR  = `TSE_MMIO_MII_RX_ERROR_NIBBLE_COUNT_ADDR;
    localparam [31:0] MII_DEBUG_STATUS_ADDR           = `TSE_MMIO_MII_DEBUG_STATUS_ADDR;

    reg [COUNTER_WIDTH-1:0] tx_frame_binary;
    reg [COUNTER_WIDTH-1:0] tx_active_binary;
    reg [COUNTER_WIDTH-1:0] tx_error_binary;
    reg [COUNTER_WIDTH-1:0] rx_frame_binary;
    reg [COUNTER_WIDTH-1:0] rx_active_binary;
    reg [COUNTER_WIDTH-1:0] rx_error_binary;

    // Explicit source-register names let SDC cut only the paths into the
    // first destination synchronizer stage.
    reg [COUNTER_WIDTH-1:0] tx_frame_gray_source;
    reg [COUNTER_WIDTH-1:0] tx_active_gray_source;
    reg [COUNTER_WIDTH-1:0] tx_error_gray_source;
    reg [COUNTER_WIDTH-1:0] rx_frame_gray_source;
    reg [COUNTER_WIDTH-1:0] rx_active_gray_source;
    reg [COUNTER_WIDTH-1:0] rx_error_gray_source;
    reg tx_en_q;
    reg rx_dv_q;

    // MII-local reset pipelines: asynchronous assertion, MII-clocked release.
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [1:0] tx_reset_pipe;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [1:0] rx_reset_pipe;
    wire tx_rst_n = tx_reset_pipe[1];
    wire rx_rst_n = rx_reset_pipe[1];

    // CPU clear toggle and source-domain synchronizers/acknowledgements.
    reg clear_request_toggle;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg tx_clear_request_sync1, tx_clear_request_sync2;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg rx_clear_request_sync1, rx_clear_request_sync2;
    reg tx_clear_request_seen, rx_clear_request_seen;
    reg tx_clear_ack_toggle, rx_clear_ack_toggle;

    // Source Gray counters synchronized into the CPU domain.
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [COUNTER_WIDTH-1:0] tx_frame_gray_sync1, tx_frame_gray_sync2;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [COUNTER_WIDTH-1:0] tx_active_gray_sync1, tx_active_gray_sync2;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [COUNTER_WIDTH-1:0] tx_error_gray_sync1, tx_error_gray_sync2;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [COUNTER_WIDTH-1:0] rx_frame_gray_sync1, rx_frame_gray_sync2;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [COUNTER_WIDTH-1:0] rx_active_gray_sync1, rx_active_gray_sync2;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [COUNTER_WIDTH-1:0] rx_error_gray_sync1, rx_error_gray_sync2;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg tx_clear_ack_sync1, tx_clear_ack_sync2;
    (* ASYNC_REG = "TRUE", altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg rx_clear_ack_sync1, rx_clear_ack_sync2;
    reg [1:0] cpu_cdc_valid_pipe;

    wire [COUNTER_WIDTH-1:0] cpu_tx_frame_count;
    wire [COUNTER_WIDTH-1:0] cpu_tx_active_nibble_count;
    wire [COUNTER_WIDTH-1:0] cpu_tx_error_nibble_count;
    wire [COUNTER_WIDTH-1:0] cpu_rx_frame_count;
    wire [COUNTER_WIDTH-1:0] cpu_rx_active_nibble_count;
    wire [COUNTER_WIDTH-1:0] cpu_rx_error_nibble_count;
    wire tx_clear_pending;
    wire rx_clear_pending;

    function automatic [COUNTER_WIDTH-1:0] binary_to_gray;
        input [COUNTER_WIDTH-1:0] binary_value;
        begin
            binary_to_gray = binary_value ^ (binary_value >> 1);
        end
    endfunction

    function automatic [COUNTER_WIDTH-1:0] gray_to_binary;
        input [COUNTER_WIDTH-1:0] gray_value;
        integer bit_index;
        begin
            gray_to_binary[COUNTER_WIDTH-1] = gray_value[COUNTER_WIDTH-1];
            for (bit_index = COUNTER_WIDTH - 2; bit_index >= 0;
                 bit_index = bit_index - 1) begin
                gray_to_binary[bit_index] = gray_to_binary[bit_index + 1] ^
                                            gray_value[bit_index];
            end
        end
    endfunction

    assign cpu_tx_frame_count = gray_to_binary(tx_frame_gray_sync2);
    assign cpu_tx_active_nibble_count = gray_to_binary(tx_active_gray_sync2);
    assign cpu_tx_error_nibble_count = gray_to_binary(tx_error_gray_sync2);
    assign cpu_rx_frame_count = gray_to_binary(rx_frame_gray_sync2);
    assign cpu_rx_active_nibble_count = gray_to_binary(rx_active_gray_sync2);
    assign cpu_rx_error_nibble_count = gray_to_binary(rx_error_gray_sync2);
    assign tx_clear_pending = clear_request_toggle ^ tx_clear_ack_sync2;
    assign rx_clear_pending = clear_request_toggle ^ rx_clear_ack_sync2;

    always @(posedge enet0_tx_clk or negedge rst_n) begin
        if (!rst_n)
            tx_reset_pipe <= 2'b00;
        else
            tx_reset_pipe <= {tx_reset_pipe[0], 1'b1};
    end

    always @(posedge enet0_rx_clk or negedge rst_n) begin
        if (!rst_n)
            rx_reset_pipe <= 2'b00;
        else
            rx_reset_pipe <= {rx_reset_pipe[0], 1'b1};
    end

    // TX source domain.  A frame is counted exactly on the sampled low-to-high
    // transition of TX_EN.  Active/error counters count sampled MII nibbles.
    always @(posedge enet0_tx_clk or negedge tx_rst_n) begin
        if (!tx_rst_n) begin
            tx_frame_binary <= {COUNTER_WIDTH{1'b0}};
            tx_active_binary <= {COUNTER_WIDTH{1'b0}};
            tx_error_binary <= {COUNTER_WIDTH{1'b0}};
            tx_frame_gray_source <= {COUNTER_WIDTH{1'b0}};
            tx_active_gray_source <= {COUNTER_WIDTH{1'b0}};
            tx_error_gray_source <= {COUNTER_WIDTH{1'b0}};
            tx_en_q <= 1'b0;
            tx_clear_request_sync1 <= 1'b0;
            tx_clear_request_sync2 <= 1'b0;
            tx_clear_request_seen <= 1'b0;
            tx_clear_ack_toggle <= 1'b0;
        end else begin
            tx_clear_request_sync1 <= clear_request_toggle;
            tx_clear_request_sync2 <= tx_clear_request_sync1;
            tx_en_q <= enet0_tx_en;

            if (tx_clear_request_sync2 != tx_clear_request_seen) begin
                tx_frame_binary <= {COUNTER_WIDTH{1'b0}};
                tx_active_binary <= {COUNTER_WIDTH{1'b0}};
                tx_error_binary <= {COUNTER_WIDTH{1'b0}};
                tx_frame_gray_source <= {COUNTER_WIDTH{1'b0}};
                tx_active_gray_source <= {COUNTER_WIDTH{1'b0}};
                tx_error_gray_source <= {COUNTER_WIDTH{1'b0}};
                tx_clear_request_seen <= tx_clear_request_sync2;
                tx_clear_ack_toggle <= ~tx_clear_ack_toggle;
            end else begin
                if (enet0_tx_en && !tx_en_q) begin
                    tx_frame_binary <= tx_frame_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
                    tx_frame_gray_source <= binary_to_gray(
                        tx_frame_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1});
                end
                if (enet0_tx_en) begin
                    tx_active_binary <= tx_active_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
                    tx_active_gray_source <= binary_to_gray(
                        tx_active_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1});
                end
                if (enet0_tx_en && enet0_tx_er) begin
                    tx_error_binary <= tx_error_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
                    tx_error_gray_source <= binary_to_gray(
                        tx_error_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1});
                end
            end
        end
    end

    // RX source domain.  The RX_DV semantics mirror TX_EN above.
    always @(posedge enet0_rx_clk or negedge rx_rst_n) begin
        if (!rx_rst_n) begin
            rx_frame_binary <= {COUNTER_WIDTH{1'b0}};
            rx_active_binary <= {COUNTER_WIDTH{1'b0}};
            rx_error_binary <= {COUNTER_WIDTH{1'b0}};
            rx_frame_gray_source <= {COUNTER_WIDTH{1'b0}};
            rx_active_gray_source <= {COUNTER_WIDTH{1'b0}};
            rx_error_gray_source <= {COUNTER_WIDTH{1'b0}};
            rx_dv_q <= 1'b0;
            rx_clear_request_sync1 <= 1'b0;
            rx_clear_request_sync2 <= 1'b0;
            rx_clear_request_seen <= 1'b0;
            rx_clear_ack_toggle <= 1'b0;
        end else begin
            rx_clear_request_sync1 <= clear_request_toggle;
            rx_clear_request_sync2 <= rx_clear_request_sync1;
            rx_dv_q <= enet0_rx_dv;

            if (rx_clear_request_sync2 != rx_clear_request_seen) begin
                rx_frame_binary <= {COUNTER_WIDTH{1'b0}};
                rx_active_binary <= {COUNTER_WIDTH{1'b0}};
                rx_error_binary <= {COUNTER_WIDTH{1'b0}};
                rx_frame_gray_source <= {COUNTER_WIDTH{1'b0}};
                rx_active_gray_source <= {COUNTER_WIDTH{1'b0}};
                rx_error_gray_source <= {COUNTER_WIDTH{1'b0}};
                rx_clear_request_seen <= rx_clear_request_sync2;
                rx_clear_ack_toggle <= ~rx_clear_ack_toggle;
            end else begin
                if (enet0_rx_dv && !rx_dv_q) begin
                    rx_frame_binary <= rx_frame_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
                    rx_frame_gray_source <= binary_to_gray(
                        rx_frame_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1});
                end
                if (enet0_rx_dv) begin
                    rx_active_binary <= rx_active_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
                    rx_active_gray_source <= binary_to_gray(
                        rx_active_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1});
                end
                if (enet0_rx_dv && enet0_rx_er) begin
                    rx_error_binary <= rx_error_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
                    rx_error_gray_source <= binary_to_gray(
                        rx_error_binary + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1});
                end
            end
        end
    end

    // CPU destination domain.  No multi-bit binary source counter is sampled
    // here; all six data CDCs terminate in sync2 Gray registers.
    always @(posedge cpu_clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_request_toggle <= 1'b0;
            tx_frame_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            tx_frame_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            tx_active_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            tx_active_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            tx_error_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            tx_error_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            rx_frame_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            rx_frame_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            rx_active_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            rx_active_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            rx_error_gray_sync1 <= {COUNTER_WIDTH{1'b0}};
            rx_error_gray_sync2 <= {COUNTER_WIDTH{1'b0}};
            tx_clear_ack_sync1 <= 1'b0;
            tx_clear_ack_sync2 <= 1'b0;
            rx_clear_ack_sync1 <= 1'b0;
            rx_clear_ack_sync2 <= 1'b0;
            cpu_cdc_valid_pipe <= 2'b00;
        end else begin
            if (cpu_mem_write && (cpu_addr == MII_DEBUG_CONTROL_ADDR) &&
                cpu_wdata[0]) begin
                clear_request_toggle <= ~clear_request_toggle;
            end
            tx_frame_gray_sync1 <= tx_frame_gray_source;
            tx_frame_gray_sync2 <= tx_frame_gray_sync1;
            tx_active_gray_sync1 <= tx_active_gray_source;
            tx_active_gray_sync2 <= tx_active_gray_sync1;
            tx_error_gray_sync1 <= tx_error_gray_source;
            tx_error_gray_sync2 <= tx_error_gray_sync1;
            rx_frame_gray_sync1 <= rx_frame_gray_source;
            rx_frame_gray_sync2 <= rx_frame_gray_sync1;
            rx_active_gray_sync1 <= rx_active_gray_source;
            rx_active_gray_sync2 <= rx_active_gray_sync1;
            rx_error_gray_sync1 <= rx_error_gray_source;
            rx_error_gray_sync2 <= rx_error_gray_sync1;
            tx_clear_ack_sync1 <= tx_clear_ack_toggle;
            tx_clear_ack_sync2 <= tx_clear_ack_sync1;
            rx_clear_ack_sync1 <= rx_clear_ack_toggle;
            rx_clear_ack_sync2 <= rx_clear_ack_sync1;
            cpu_cdc_valid_pipe <= {cpu_cdc_valid_pipe[0], 1'b1};
        end
    end

    // CPU readback is wholly in cpu_clk domain; no source-domain binary bus is
    // exposed here. The default also defines disabled and unmapped reads.
    always_comb begin
        cpu_rdata = 32'd0;
        if (cpu_mem_read) begin
            case (cpu_addr)
                MII_DEBUG_CONTROL_ADDR: begin
                    // bit 0 is write-one-to-request-clear; reads are zero.
                    cpu_rdata = 32'd0;
                end
                MII_TX_FRAME_COUNT_ADDR: begin
                    cpu_rdata = cpu_tx_frame_count;
                end
                MII_TX_ACTIVE_NIBBLE_COUNT_ADDR: begin
                    cpu_rdata = cpu_tx_active_nibble_count;
                end
                MII_TX_ERROR_NIBBLE_COUNT_ADDR: begin
                    cpu_rdata = cpu_tx_error_nibble_count;
                end
                MII_RX_FRAME_COUNT_ADDR: begin
                    cpu_rdata = cpu_rx_frame_count;
                end
                MII_RX_ACTIVE_NIBBLE_COUNT_ADDR: begin
                    cpu_rdata = cpu_rx_active_nibble_count;
                end
                MII_RX_ERROR_NIBBLE_COUNT_ADDR: begin
                    cpu_rdata = cpu_rx_error_nibble_count;
                end
                MII_DEBUG_STATUS_ADDR: begin
                    // [0] TX Gray CDC pipeline valid, [1] RX pipeline valid,
                    // [2] TX clear pending, [3] RX clear pending.
                    cpu_rdata = {28'd0, rx_clear_pending, tx_clear_pending,
                                 cpu_cdc_valid_pipe[1], cpu_cdc_valid_pipe[1]};
                end
                default: begin
                    cpu_rdata = 32'd0;
                end
            endcase
        end
    end

    // Keep the complete board-side signal interface explicit.  These nibbles
    // are intentionally not part of any count or CDC path in this revision.
    wire unused_mii_data = ^{enet0_tx_data, enet0_rx_data};

endmodule
