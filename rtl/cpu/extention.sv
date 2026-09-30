module extention(
    input [31:0] instr,
    input [2:0]  imm_sel,
    output reg [31:0] d_out
);

    localparam IMM_NONE = 3'b000;
    localparam IMM_I    = 3'b001;
    localparam IMM_S    = 3'b010;
    localparam IMM_B    = 3'b011;
    localparam IMM_U    = 3'b100;
    localparam IMM_J    = 3'b101;

    always @(*) begin
        case (imm_sel)
            IMM_I: d_out = {{20{instr[31]}}, instr[31:20]};
            IMM_S: d_out = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            IMM_B: d_out = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            IMM_U: d_out = {instr[31:12], 12'b0};
            IMM_J: d_out = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default: d_out = 32'b0;
        endcase
    end
endmodule
