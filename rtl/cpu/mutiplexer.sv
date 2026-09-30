module mutiplexer_2input #(
    parameter WIDTH = 32
)(
    input              control,
    input  [WIDTH-1:0] d_in0,
    input  [WIDTH-1:0] d_in1,
    output reg [WIDTH-1:0] dout
);

    always @(*) begin
        case (control)
            1'b0: dout = d_in0;
            1'b1: dout = d_in1;
            default: dout = d_in0; // Default case to handle X/Z
        endcase
    end

endmodule


module mutiplexer_3input #(
    parameter WIDTH = 32
)(
    input  [1:0]        control,
    input  [WIDTH-1:0]  d_in0,
    input  [WIDTH-1:0]  d_in1,
    input  [WIDTH-1:0]  d_in2,
    output reg [WIDTH-1:0] dout
);

    always @(*) begin
        case (control)
            2'b00: dout = d_in0;
            2'b01: dout = d_in1;
            2'b10: dout = d_in2;
            default: dout = d_in0; // Default case to handle X/Z or unexpected control values
        endcase
    end

endmodule
