module reset_sync #(
    parameter integer STAGES = 3
) (
    input  wire clk,
    input  wire async_rst_n,
    output wire rst_n
);

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg [STAGES-1:0] reset_pipe;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            reset_pipe <= {STAGES{1'b0}};
        end else begin
            reset_pipe <= {reset_pipe[STAGES-2:0], 1'b1};
        end
    end

    assign rst_n = reset_pipe[STAGES-1];

endmodule
