// Converts between the project's little-endian packet-word convention and
// the Intel TSE 32-bit FIFO convention, where the most-significant byte is
// transferred first. The empty/mod count is unchanged: after byte reversal,
// any invalid bytes in the internal high lanes occupy the MAC low lanes.
module tse_stream_byte_order_adapter (
    input  wire [31:0] internal_tx_data,
    input  wire [1:0]  internal_tx_empty,
    output wire [31:0] mac_tx_data,
    output wire [1:0]  mac_tx_empty,

    input  wire [31:0] mac_rx_data,
    input  wire [1:0]  mac_rx_empty,
    output wire [31:0] internal_rx_data,
    output wire [1:0]  internal_rx_empty
);

    function automatic [31:0] reverse_bytes32;
        input [31:0] value;
        begin
            reverse_bytes32 = {value[7:0], value[15:8],
                               value[23:16], value[31:24]};
        end
    endfunction

    assign mac_tx_data = reverse_bytes32(internal_tx_data);
    assign mac_tx_empty = internal_tx_empty;
    assign internal_rx_data = reverse_bytes32(mac_rx_data);
    assign internal_rx_empty = mac_rx_empty;

endmodule
