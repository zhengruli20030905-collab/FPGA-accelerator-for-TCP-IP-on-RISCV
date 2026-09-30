module alu( 
    input clk,                // Legacy interface clock; ALU logic is combinational
    input rst_n,                // Reset input
    input alu_en, 
    input [3:0] Aluctr, 
    input [31:0] Input_A, 
    input [31:0] Input_B,
    input [4:0]  sl, 
    output reg [31:0] alu_output, 
    output reg zero,
    output reg alu_busy            // Signal to indicate ALU is processing
);

    parameter 
        ADD = 4'b0001,
        SUB = 4'b0010,
        AND = 4'b0011,
        OR  = 4'b0100,
        XOR = 4'b0101,
        SLT = 4'b1001,
        SLTU = 4'b1010,
        SLL = 4'b0110,
        SRL = 4'b0111,
        SRA = 4'b1000;

    always @(*) begin
        if (!rst_n) begin
            alu_output = 32'b0;
            zero = 1'b1;
            alu_busy = 1'b0;
        end else if (alu_en) begin
            alu_busy = 1'b0;
            case (Aluctr)
                ADD : alu_output = Input_A + Input_B;
                SUB : alu_output = Input_A - Input_B;
                AND : alu_output = Input_A & Input_B;
                OR  : alu_output = Input_A | Input_B;
                XOR : alu_output = Input_A ^ Input_B;
                SLT : alu_output = ($signed(Input_A) < $signed(Input_B)) ? 32'h00000001 : 32'h00000000;
                SLTU: alu_output = (Input_A < Input_B) ? 32'h00000001 : 32'h00000000;
                SLL : alu_output = Input_A << Input_B[4:0];
                SRL : alu_output = Input_A >> Input_B[4:0];
                SRA : alu_output = $signed(Input_A) >>> Input_B[4:0];
                default: alu_output = 32'b0;
            endcase
            zero = (alu_output == 32'b0) ? 1'b1 : 1'b0;
        end else begin
            alu_busy = 1'b0;
            alu_output = 32'b0;
            zero = 1'b1;
        end
    end

endmodule
