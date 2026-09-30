module WB_Stage(
    input         clk,
    input         rst_n,
    // Inputs from MEM/WB pipeline register
    input [31:0]  MEM_WB_ALUResult,
    input [31:0]  MEM_WB_MemData,
    input [31:0]  MEM_WB_jalPC,
    input [4:0]   MEM_WB_WriteReg,
    input [1:0]   MEM_WB_MemToReg,
    input         MEM_WB_RegWrite,
    input         MEM_WB_valid,

    // Outputs to Register File
    output reg [31:0] WB_WriteData,
    output reg [4:0]  WB_WriteReg,
    output reg        WB_RegWrite
);

    // Write-Back Data Selection
    reg [31:0] write_data_mux_out;

    always @(*) begin
        case (MEM_WB_MemToReg)
            2'b00: write_data_mux_out = MEM_WB_ALUResult; // From ALU
            2'b01: write_data_mux_out = MEM_WB_MemData;   // From Memory
            2'b10: write_data_mux_out = MEM_WB_jalPC;     // From Jump Address (for JAL)
            default: write_data_mux_out = 32'b0;
        endcase
    end

    // Output Registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            WB_WriteData <= 32'b0;
            WB_WriteReg  <= 5'b0;
            WB_RegWrite  <= 1'b0;
        end else begin
            WB_WriteData <= write_data_mux_out;
            WB_WriteReg  <= MEM_WB_WriteReg;
            WB_RegWrite  <= MEM_WB_valid && MEM_WB_RegWrite;
        end
    end

endmodule
