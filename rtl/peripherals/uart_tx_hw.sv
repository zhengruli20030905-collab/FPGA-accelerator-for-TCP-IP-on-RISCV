// REAL BOARD UART TRANSMITTER
//
// 8N1 transmitter used by BOARD_DE2115.  tx_valid/tx_ready form a conventional
// same-edge handshake: the transmitter owns tx_data on a rising edge only when
// both signals are high.  The producer must keep tx_valid and tx_data stable
// until that transfer edge.
module uart_tx_hw #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer BAUD   = 115_200
) (
    input clk,
    input rst_n,
    input tx_valid,
    input [7:0] tx_data,
    output logic tx_busy,
    output wire tx_ready,
    output logic uart_txd
);

    // Round to the nearest integer divider.  At 25 MHz/115200 this is 217.
    localparam integer CLKS_PER_BIT_RAW = (CLK_HZ + (BAUD / 2)) / BAUD;
    localparam integer CLKS_PER_BIT = (CLKS_PER_BIT_RAW < 1) ? 1 : CLKS_PER_BIT_RAW;

    reg [31:0] baud_count;
    reg [3:0] bit_index;
    reg [9:0] shifter;

    assign tx_ready = !tx_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_busy <= 1'b0;
            uart_txd <= 1'b1;
            baud_count <= 32'b0;
            bit_index <= 4'b0;
            shifter <= 10'h3ff;
        end else begin
            if (!tx_busy) begin
                uart_txd <= 1'b1;
                baud_count <= 32'b0;
                bit_index <= 4'b0;

                if (tx_valid) begin
                    shifter <= {1'b1, tx_data, 1'b0};
                    uart_txd <= 1'b0;
                    tx_busy <= 1'b1;
                end
            end else begin
                if (baud_count == (CLKS_PER_BIT - 1)) begin
                    baud_count <= 32'b0;
                    shifter <= {1'b1, shifter[9:1]};

                    if (bit_index == 4'd9) begin
                        tx_busy <= 1'b0;
                        uart_txd <= 1'b1;
                    end else begin
                        bit_index <= bit_index + 4'd1;
                        uart_txd <= shifter[1];
                    end
                end else begin
                    baud_count <= baud_count + 32'd1;
                end
            end
        end
    end

endmodule
