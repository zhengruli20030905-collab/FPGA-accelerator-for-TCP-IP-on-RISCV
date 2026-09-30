`include "soc_addr_map.svh"

// UART TX MMIO with a single-clock queued-byte FIFO.
//
//   0x10000000 UART_TX_DATA  W: enqueue din[7:0]
//   0x10000004 UART_STATUS   R: level/status flags
//   0x10000008 UART_CTRL     W: bit0 clear overflow, bit1 flush queue
//   0x1000000c UART_TX_LEVEL R: queued bytes only
//
// STATUS bit0 remains software compatible with the old UART_TX_READY bit, but
// now means FIFO not full. The FIFO does not include a byte already owned by
// uart_tx_hw. Flush removes queued bytes and never aborts that in-flight byte.
// The FIFO head and serializer use a same-rising-edge valid/ready handshake.
module uart_mmio #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer BAUD = 115_200,
    parameter integer FIFO_DEPTH = 16
) (
    input clk,
    input rst_n,
    input mem_write,
    input mem_read,
    input [31:0] addr,
    input [31:0] din,
    output logic [31:0] dout,
    output uart_txd
);

    localparam [31:0] UART_TX_DATA_ADDR  = `SOC_UART_TX_DATA_ADDR;
    localparam [31:0] UART_STATUS_ADDR   = `SOC_UART_STATUS_ADDR;
    localparam [31:0] UART_CTRL_ADDR     = `SOC_UART_CTRL_ADDR;
    localparam [31:0] UART_TX_LEVEL_ADDR = `SOC_UART_TX_LEVEL_ADDR;
    localparam integer FIFO_PTR_W = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam integer FIFO_COUNT_W = $clog2(FIFO_DEPTH + 1);
    localparam logic [FIFO_COUNT_W-1:0] FIFO_DEPTH_COUNT = FIFO_DEPTH[FIFO_COUNT_W-1:0];

    reg [7:0] tx_fifo [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_W-1:0] fifo_write_ptr;
    reg [FIFO_PTR_W-1:0] fifo_read_ptr;
    reg [FIFO_COUNT_W-1:0] fifo_count;
    reg tx_overflow;

    wire uart_tx_write = mem_write && (addr == UART_TX_DATA_ADDR);
    wire uart_ctrl_write = mem_write && (addr == UART_CTRL_ADDR);
    wire clear_overflow_request = uart_ctrl_write && din[0];
    wire flush_request = uart_ctrl_write && din[1];
    wire fifo_empty = (fifo_count == {FIFO_COUNT_W{1'b0}});
    wire fifo_full = (fifo_count == FIFO_DEPTH_COUNT);
    wire fifo_not_full = !fifo_full;
    wire [31:0] fifo_count_ext = fifo_count;

`ifdef BOARD_DE2115
    wire serializer_busy;
    wire serializer_ready;
    wire serializer_valid = !fifo_empty && !flush_request;
    wire [7:0] serializer_data = tx_fifo[fifo_read_ptr];

    uart_tx_hw #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_uart_tx_hw (
        .clk(clk),
        .rst_n(rst_n),
        .tx_valid(serializer_valid),
        .tx_data(serializer_data),
        .tx_busy(serializer_busy),
        .tx_ready(serializer_ready),
        .uart_txd(uart_txd)
    );
`else
    wire serializer_busy = 1'b0;
    wire serializer_ready = 1'b1;
    wire serializer_valid = !fifo_empty && !flush_request;
    wire [7:0] serializer_data = tx_fifo[fifo_read_ptr];
    assign uart_txd = 1'b1;
`endif

    // This is the only event that transfers ownership of the FIFO head.  Both
    // uart_tx_hw and the FIFO observe it on the same rising edge, so neither a
    // registered command pulse nor a falling-edge staging convention is used.
    wire dequeue_accept = serializer_valid && serializer_ready;
    // At full occupancy a simultaneous dequeue creates room for one enqueue.
    wire enqueue_accept = uart_tx_write && (!fifo_full || dequeue_accept) &&
                          !flush_request;

    function [FIFO_PTR_W-1:0] next_fifo_ptr;
        input [FIFO_PTR_W-1:0] ptr;
        begin
            if (ptr == (FIFO_DEPTH - 1)) begin
                next_fifo_ptr = {FIFO_PTR_W{1'b0}};
            end else begin
                next_fifo_ptr = ptr + {{(FIFO_PTR_W-1){1'b0}}, 1'b1};
            end
        end
    endfunction

    // CPU MMIO writes, FIFO bookkeeping, and the serializer handshake all use
    // the rising edge.  serializer_valid/data remain stable while ready is low.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_write_ptr <= {FIFO_PTR_W{1'b0}};
            fifo_read_ptr <= {FIFO_PTR_W{1'b0}};
            fifo_count <= {FIFO_COUNT_W{1'b0}};
            tx_overflow <= 1'b0;
        end else begin
            if (clear_overflow_request) begin
                tx_overflow <= 1'b0;
            end

            if (flush_request) begin
                fifo_write_ptr <= {FIFO_PTR_W{1'b0}};
                fifo_read_ptr <= {FIFO_PTR_W{1'b0}};
                fifo_count <= {FIFO_COUNT_W{1'b0}};
            end else begin
                if (enqueue_accept) begin
                    tx_fifo[fifo_write_ptr] <= din[7:0];
                    fifo_write_ptr <= next_fifo_ptr(fifo_write_ptr);
                end else if (uart_tx_write) begin
                    tx_overflow <= 1'b1;
                end

                if (dequeue_accept) begin
                    fifo_read_ptr <= next_fifo_ptr(fifo_read_ptr);
`ifdef BOARD_DE2115
`else
`ifndef SYNTHESIS
                    $write("%c", serializer_data);
`endif
`endif
                end

                case ({enqueue_accept, dequeue_accept})
                    2'b10: fifo_count <= fifo_count +
                                              {{(FIFO_COUNT_W-1){1'b0}}, 1'b1};
                    2'b01: fifo_count <= fifo_count -
                                              {{(FIFO_COUNT_W-1){1'b0}}, 1'b1};
                    default: fifo_count <= fifo_count;
                endcase
            end
        end
    end

    always_comb begin
        dout = 32'd0;
        if (mem_read) begin
            case (addr)
                UART_STATUS_ADDR: begin
                    dout = {16'd0, fifo_count_ext[7:0], 3'd0,
                            tx_overflow, serializer_busy, fifo_full,
                            fifo_empty, fifo_not_full};
                end
                UART_TX_LEVEL_ADDR: begin
                    dout = fifo_count_ext;
                end
                default: begin
                    dout = 32'd0;
                end
            endcase
        end
    end

endmodule
