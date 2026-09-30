module sync_2ff #(
    parameter integer WIDTH = 1,
    parameter [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b0}}
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [WIDTH-1:0] async_in,
    output wire [WIDTH-1:0] sync_out
);

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [WIDTH-1:0] sync_stage1;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [WIDTH-1:0] sync_stage2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_stage1 <= RESET_VALUE;
            sync_stage2 <= RESET_VALUE;
        end else begin
            sync_stage1 <= async_in;
            sync_stage2 <= sync_stage1;
        end
    end

    assign sync_out = sync_stage2;

endmodule
