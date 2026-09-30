module EX_Stage (
    input clk,
    input rst_n,
    input stall,                         // Stall signal for pipeline control
    // From ID/EX pipeline register
    input [31:0] ID_EX_pc,
    input [31:0] ID_EX_jalpc,
    input [31:0] ID_EX_rs_data,
    input [31:0] ID_EX_rt_data,
    input [31:0] ID_EX_ext_imm,
    input [3:0]  ID_EX_ALU_control,
    input        ID_EX_alu_enable,
    input [1:0]  ID_EX_reg_dst,
    input [1:0]  ID_EX_alu_src_a,
    input        ID_EX_alu_src,
    input        ID_EX_mem_write,
    input        ID_EX_mem_read,
    input [2:0]  ID_EX_mem_funct3,
    input [1:0]  ID_EX_mem_to_reg,
    input        ID_EX_reg_write_enable,
    input [4:0]  ID_EX_rs_addr,
    input [4:0]  ID_EX_rt_addr,
    input [4:0]  ID_EX_rd_addr,
    input [4:0]  ID_EX_shamt,
    // indicates if the current instruction is a branch
    input        ID_EX_pc_op,
    input [2:0]  ID_EX_branch_type,
    input        ID_EX_jump,
    input        ID_EX_jump_register,
    input        ID_EX_halt,
    input        ID_EX_valid,
    input [15:0] ID_EX_imm,
    // Forwarding inputs
    input [4:0] MEM_WB_rd_addr,
    input       MEM_WB_reg_write_enable,
    input [31:0] WB_mux_WB,
    input [4:0] WB_rd_addr,
    input       WB_reg_write_enable,
    input [31:0] WB_forward_data,
    input [31:0] MEM_forward_data,
    // Outputs to EX/MEM pipeline register
    output [31:0] EX_ALUResult,
    output [31:0] EX_WriteData,
    output [4:0]  EX_WriteReg,
    output        EX_MemRead,
    output        EX_MemWrite,
    output [2:0]  EX_MemFunct3,
    output [1:0]  EX_MemToReg,
    output        EX_RegWrite,
    output        EX_Zero,
    output [31:0] EX_pc,
    output [31:0] EX_jalpc,
    output        EX_valid,
    //outout for if stage beq
    output        branch_taken,
    output [31:0] branch_target,
    output        flush_out,
    output        halt_out
);

    localparam BR_NONE = 3'b000;
    localparam BR_BEQ  = 3'b001;
    localparam BR_BNE  = 3'b010;
    localparam BR_BLT  = 3'b011;
    localparam BR_BGE  = 3'b100;
    localparam BR_BLTU = 3'b101;
    localparam BR_BGEU = 3'b110;

    // Forwarded source operands
    reg [31:0] ALU_in1_forwarded;
    reg [31:0] ALU_in2_forwarded;

    // ALU input selection
    reg  [31:0] ALU_in1_mux;
    wire [31:0] ALU_in2_mux;
    reg [1:0] forwardA_reg;
    reg [1:0] forwardB_reg;

    always @(*) begin
        // Forwarding for rs_data
        if (EX_RegWrite && (EX_WriteReg != 0) && (EX_WriteReg == ID_EX_rs_addr)) begin
            forwardA_reg = 2'b10;
        end else if (MEM_WB_reg_write_enable && (MEM_WB_rd_addr != 0) && (MEM_WB_rd_addr == ID_EX_rs_addr)) begin
            forwardA_reg = 2'b01;
        end else if (WB_reg_write_enable && (WB_rd_addr != 0) && (WB_rd_addr == ID_EX_rs_addr)) begin
            forwardA_reg = 2'b11;
        end else begin
            forwardA_reg = 2'b00;
        end

        // Forwarding for rt_data
        if (EX_RegWrite && (EX_WriteReg != 0) && (EX_WriteReg == ID_EX_rt_addr)) begin
            forwardB_reg = 2'b10;
        end else if (MEM_WB_reg_write_enable && (MEM_WB_rd_addr != 0) && (MEM_WB_rd_addr == ID_EX_rt_addr)) begin
            forwardB_reg = 2'b01;
        end else if (WB_reg_write_enable && (WB_rd_addr != 0) && (WB_rd_addr == ID_EX_rt_addr)) begin
            forwardB_reg = 2'b11;
        end else begin
            forwardB_reg = 2'b00;
        end
    end

    // Handle forwarding for ALU input A
    always @(*) begin
        case (forwardA_reg)
            2'b00: ALU_in1_forwarded = ID_EX_rs_data;
            2'b01: ALU_in1_forwarded = WB_mux_WB;          // Forward from WB stage
            2'b10: ALU_in1_forwarded = EX_MemRead ? MEM_forward_data : EX_ALUResult; // Forward from MEM stage
            2'b11: ALU_in1_forwarded = WB_forward_data;    // Forward from registered WB output
            default: ALU_in1_forwarded = ID_EX_rs_data;
        endcase
    end

    // Handle forwarding for ALU input B / store data
    always @(*) begin
        case (forwardB_reg)
            2'b00: ALU_in2_forwarded = ID_EX_rt_data;
            2'b01: ALU_in2_forwarded = WB_mux_WB;          // Forward from WB stage
            2'b10: ALU_in2_forwarded = EX_MemRead ? MEM_forward_data : EX_ALUResult; // Forward from MEM stage
            2'b11: ALU_in2_forwarded = WB_forward_data;    // Forward from registered WB output
            default: ALU_in2_forwarded = ID_EX_rt_data;
        endcase
    end

    always @(*) begin
        case (ID_EX_alu_src_a)
            2'b00: ALU_in1_mux = ALU_in1_forwarded;
            2'b01: ALU_in1_mux = ID_EX_pc;
            2'b10: ALU_in1_mux = 32'b0;
            default: ALU_in1_mux = ALU_in1_forwarded;
        endcase
    end

    // ALU input B selection (immediate or register value)
    assign ALU_in2_mux = ID_EX_alu_src ? ID_EX_ext_imm : ALU_in2_forwarded;

    // ALU module instantiation
    wire [31:0] ALU_out;
    wire Zero;

    alu alu_unit (
        .clk(clk),
        .rst_n(rst_n),
        .alu_en(ID_EX_alu_enable),
        .Aluctr(ID_EX_ALU_control),
        .Input_A(ALU_in1_mux),
        .Input_B(ALU_in2_mux),
        .sl(ID_EX_shamt),
        .alu_output(ALU_out),
        .zero(Zero),
        .alu_busy()
    );

    reg branch_condition;
    always @(*) begin
        case (ID_EX_branch_type)
            BR_BEQ:  branch_condition = (ALU_in1_forwarded == ALU_in2_forwarded);
            BR_BNE:  branch_condition = (ALU_in1_forwarded != ALU_in2_forwarded);
            BR_BLT:  branch_condition = ($signed(ALU_in1_forwarded) < $signed(ALU_in2_forwarded));
            BR_BGE:  branch_condition = ($signed(ALU_in1_forwarded) >= $signed(ALU_in2_forwarded));
            BR_BLTU: branch_condition = (ALU_in1_forwarded < ALU_in2_forwarded);
            BR_BGEU: branch_condition = (ALU_in1_forwarded >= ALU_in2_forwarded);
            default: branch_condition = 1'b0;
        endcase
    end

    wire branch_taken_now = ID_EX_valid &&
                            ((ID_EX_pc_op && branch_condition) ||
                             ID_EX_jump || ID_EX_jump_register);
    wire [31:0] jalr_target = (ALU_in1_forwarded + ID_EX_ext_imm) & 32'hFFFF_FFFE;
    wire [31:0] pc_imm_target = ID_EX_pc + ID_EX_ext_imm;
    wire [31:0] branch_target_now = ID_EX_jump_register ? jalr_target : pc_imm_target;
    wire mem_word_access = (ID_EX_mem_funct3 == 3'b010);
    wire mem_half_access = (ID_EX_mem_funct3 == 3'b001) || (ID_EX_mem_funct3 == 3'b101);
    wire mem_align_error = ID_EX_valid && (ID_EX_mem_read || ID_EX_mem_write) &&
                           ((mem_word_access && (ALU_out[1:0] != 2'b00)) ||
                            (mem_half_access && (ALU_out[0] != 1'b0)));
    wire pc_align_error = branch_taken_now && (branch_target_now[1:0] != 2'b00);
    wire trap_now = (ID_EX_valid && ID_EX_halt) || mem_align_error || pc_align_error;

    assign branch_taken = branch_taken_now && !trap_now;
    assign branch_target = branch_target_now;
    assign flush_out = branch_taken || trap_now;
    assign halt_out = trap_now;

    always @(posedge clk) begin
        if (rst_n && mem_align_error)
            $display("TRAP: unaligned load/store address %h at pc %h", ALU_out, ID_EX_pc);
        if (rst_n && pc_align_error)
            $display("TRAP: unaligned instruction target %h at pc %h", branch_target_now, ID_EX_pc);
        if (rst_n && ID_EX_halt)
            $display("TRAP: halt/illegal/system instruction at pc %h", ID_EX_pc);
    end

    reg [31:0] EX_ALUResult_r, EX_WriteData_r, EX_pc_r, EX_jalpc_r;
    reg [4:0]  EX_WriteReg_r;
    reg        EX_MemRead_r, EX_MemWrite_r, EX_RegWrite_r, EX_Zero_r, EX_valid_r;
    reg [2:0]  EX_MemFunct3_r;
    reg [1:0]  EX_MemToReg_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            EX_ALUResult_r <= 0;
            EX_WriteData_r <= 0;
            EX_WriteReg_r <= 0;
            EX_MemRead_r <= 0;
            EX_MemWrite_r <= 0;
            EX_MemFunct3_r <= 3'b010;
            EX_MemToReg_r <= 0;
            EX_RegWrite_r <= 0;
            EX_Zero_r <= 0;
            EX_pc_r <= 0;
            EX_jalpc_r <= 0;
            EX_valid_r <= 1'b0;
        end else if (stall) begin
            // Hold the complete EX/MEM transaction until MEM acknowledges it.
        end else begin
            EX_ALUResult_r <= ALU_out;
            EX_WriteData_r <= ALU_in2_forwarded;
            EX_WriteReg_r <= ID_EX_rd_addr;
            EX_MemRead_r <= ID_EX_valid && ID_EX_mem_read && !trap_now;
            EX_MemWrite_r <= ID_EX_valid && ID_EX_mem_write && !trap_now;
            EX_MemFunct3_r <= ID_EX_mem_funct3;
            EX_MemToReg_r <= ID_EX_mem_to_reg;
            EX_RegWrite_r <= ID_EX_valid && ID_EX_reg_write_enable && !trap_now;
            EX_Zero_r <= Zero;
            EX_pc_r <= ID_EX_pc;
            EX_jalpc_r <= ID_EX_jalpc;
            EX_valid_r <= ID_EX_valid && !trap_now;
        end
    end

    assign EX_ALUResult = EX_ALUResult_r;
    assign EX_WriteData = EX_WriteData_r;
    assign EX_WriteReg = EX_WriteReg_r;
    assign EX_MemRead = EX_MemRead_r;
    assign EX_MemWrite = EX_MemWrite_r;
    assign EX_MemFunct3 = EX_MemFunct3_r;
    assign EX_MemToReg = EX_MemToReg_r;
    assign EX_RegWrite = EX_RegWrite_r;
    assign EX_Zero = EX_Zero_r;
    assign EX_pc = EX_pc_r;
    assign EX_jalpc = EX_jalpc_r;
    assign EX_valid = EX_valid_r;

endmodule
