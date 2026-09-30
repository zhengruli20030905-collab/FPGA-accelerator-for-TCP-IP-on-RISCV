module ID_Stage (
    input clk,
    input rst_n,
    // Inputs from IF/ID pipeline register
    input [31:0] IF_ID_instr,
    input [31:0] IF_ID_pc,
    input [31:0] IF_ID_jalpc,
    input        IF_ID_valid,
    // Inputs for Register File write-back
    input [31:0] write_data,
    input [4:0]  write_addr,
    input        WB_RegWrite,
    // Inputs from hazard detection and forwarding units
    input stall,
    input hold,
    input flush,
    input [4:0] EX_MEM_rd_addr,
    input       EX_MEM_reg_write_enable,
    // Outputs to ID/EX pipeline register
    output reg [31:0] ID_EX_rs_data,
    output reg [31:0] ID_EX_rt_data,
    output reg [31:0] ID_EX_ext_imm,
    output reg [25:0] ID_EX_jump_target,
    output reg [3:0]  ID_EX_ALU_control,
    output reg        ID_EX_alu_enable,
    output reg [1:0]  ID_EX_reg_dst,
    output reg [1:0]  ID_EX_alu_src_a,
    output reg        ID_EX_alu_src,
    output reg        ID_EX_mem_write,
    output reg        ID_EX_mem_read,
    output reg [2:0]  ID_EX_mem_funct3,
    output reg [1:0]  ID_EX_mem_to_reg,
    output reg        ID_EX_reg_write_enable,
    output reg        ID_EX_pc_op,
    output reg [2:0]  ID_EX_branch_type,
    output reg        ID_EX_jump,
    output reg        ID_EX_jump_register,
    output reg        ID_EX_halt,
    output reg [4:0]  ID_EX_rs_addr,
    output reg [4:0]  ID_EX_rt_addr,
    output reg [4:0]  ID_EX_rd_addr,
    output reg [4:0]  ID_EX_shamt,
    output reg [15:0] ID_EX_imm,
    output reg [10:6] ID_EX_sl,
    output reg [31:0] ID_pc,
    output reg [31:0] ID_EX_jalpc,
    output reg        ID_EX_valid,
    // Outputs for hazard detection
    output reg [6:0] opcode_reg,
    output reg [6:0] func_reg,
    output           ID_stall_request
);

    // 1. RV32I Instruction Fields
    wire [6:0] opcode    = IF_ID_instr[6:0];
    wire [4:0] rd_addr   = IF_ID_instr[11:7];
    wire [2:0] funct3    = IF_ID_instr[14:12];
    wire [4:0] rs_addr   = IF_ID_instr[19:15];
    wire [4:0] rt_addr   = IF_ID_instr[24:20]; // RV32I rs2, kept as rt for local style
    wire [6:0] funct7    = IF_ID_instr[31:25];
    wire [15:0] imm      = IF_ID_instr[15:0];
    wire [4:0] shamt     = IF_ID_instr[24:20];
    wire [25:0] jump_target = 26'b0;

    // 2. Control Signals
    wire        control_alu_enable;
    wire        control_mem_read;
    wire        control_mem_write;
    wire        control_pc_op;
    wire        control_jump;
    wire        control_jump_register;
    wire        control_halt;
    wire [1:0]  control_reg_dst;
    wire [1:0]  control_alu_src_a;
    wire [1:0]  control_mem_to_reg;
    wire [2:0]  control_mem_funct3;
    wire [2:0]  control_imm_sel;
    wire [2:0]  control_branch_type;
    wire [3:0]  control_ALU_control;
    wire        control_alu_src;
    wire        control_reg_write_enable;

    // 3. Immediate Extension
    wire [31:0] extended_imm;
    extention imm_ext (
        .instr(IF_ID_instr),
        .imm_sel(control_imm_sel),
        .d_out(extended_imm)
    );

    // 4. Register File Read
    wire [31:0] reg_rs_data_raw;
    wire [31:0] reg_rt_data_raw;
    wire [31:0] held_rs_data_raw;
    wire [31:0] held_rt_data_raw;
    RF  rf(
        .clk(clk),
        .rst_n(rst_n),
        .RegWrite(WB_RegWrite),
        .ra1(rs_addr),
        .ra2(rt_addr),
        .hold_ra1(ID_EX_rs_addr),
        .hold_ra2(ID_EX_rt_addr),
        .wa(write_addr),
        .wd(write_data),
        .rd1(reg_rs_data_raw),
        .rd2(reg_rt_data_raw),
        .hold_rd1(held_rs_data_raw),
        .hold_rd2(held_rt_data_raw)
    );

    // With RF write-back also moved to posedge, an instruction decoded on the
    // same edge must see the just-retired value explicitly.
    wire wb_hits_rs = WB_RegWrite && (write_addr != 5'b0) && (write_addr == rs_addr);
    wire wb_hits_rt = WB_RegWrite && (write_addr != 5'b0) && (write_addr == rt_addr);
    wire [31:0] reg_rs_data = wb_hits_rs ? write_data : reg_rs_data_raw;
    wire [31:0] reg_rt_data = wb_hits_rt ? write_data : reg_rt_data_raw;

    reg [4:0] WriteReg_candidate;
    reg       stall_reg;
    // 5. Control Unit
    control_unit ctrl_unit (
        .operation(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .zero(1'b0), // Zero flag not used here
        .isLoad(ID_EX_mem_read),
        .rs1_ID(rs_addr),
        .rs2_ID(rt_addr),
        .rd_EX(WriteReg_candidate),
        .rd_MEM(EX_MEM_rd_addr),
        .RegWrite_EX(ID_EX_reg_write_enable),
        .RegWrite_MEM(EX_MEM_reg_write_enable),
        .alu_en(control_alu_enable),
        .Aluctr(control_ALU_control),
        .RegDst(control_reg_dst),
        .AlusrcA(control_alu_src_a),
        .Alusrc(control_alu_src),
        .Reg_en(control_reg_write_enable),
        .mem_read(control_mem_read),
        .mem_write(control_mem_write),
        .mem_funct3(control_mem_funct3),
        .mem_to_reg(control_mem_to_reg),
        .pc_op(control_pc_op),
        .imm_sel(control_imm_sel),
        .branch_type(control_branch_type),
        .jump(control_jump),
        .jumpr(control_jump_register),
        .halt(control_halt),
        .stall(stall_reg)
    );

    // The old negedge register formed the worst half-cycle path. The hazard is
    // metadata-only and is now a same-cycle combinational request.
    assign ID_stall_request = IF_ID_valid && stall_reg && !flush;

    // 6. Pipeline Register Updates (original clock with stall/flush control)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Clear pipeline registers on reset
            ID_EX_rs_data          <= 32'b0;
            ID_EX_rt_data          <= 32'b0;
            ID_EX_ext_imm          <= 32'b0;
            ID_EX_jump_target      <= 26'b0;
            ID_EX_ALU_control      <= 4'b0;
            ID_EX_alu_enable       <= 1'b0;
            ID_EX_reg_dst          <= 2'b0;
            ID_EX_alu_src_a        <= 2'b0;
            ID_EX_alu_src          <= 1'b0;
            ID_EX_mem_write        <= 1'b0;
            ID_EX_mem_read         <= 1'b0;
            ID_EX_mem_funct3       <= 3'b010;
            ID_EX_mem_to_reg       <= 2'b0;
            ID_EX_reg_write_enable <= 1'b0;
            ID_EX_pc_op            <= 1'b0;
            ID_EX_branch_type      <= 3'b0;
            ID_EX_jump             <= 1'b0;
            ID_EX_jump_register    <= 1'b0;
            ID_EX_halt             <= 1'b0;
            ID_EX_rs_addr          <= 5'b0;
            ID_EX_rt_addr          <= 5'b0;
            ID_EX_rd_addr          <= 5'b0;
            ID_EX_shamt            <= 5'b0;
            ID_EX_imm              <= 16'b0;
            ID_EX_sl               <= 5'b0;
            opcode_reg             <= 7'b0;
            func_reg               <= 7'b0;
            ID_pc                  <= 'h0 ;
            ID_EX_jalpc            <= 32'b0;
            ID_EX_valid            <= 1'b0;
            WriteReg_candidate     <= 5'b0;
        end else if (hold) begin
            // A pending MEM transaction freezes ID/EX exactly; no request or
            // instruction may be duplicated while the response is outstanding.
            // Refresh operands because an older WB instruction can retire while
            // this instruction is held after its original decode edge.
            ID_EX_rs_data <= (WB_RegWrite && (write_addr != 5'b0) &&
                              (write_addr == ID_EX_rs_addr)) ? write_data : held_rs_data_raw;
            ID_EX_rt_data <= (WB_RegWrite && (write_addr != 5'b0) &&
                              (write_addr == ID_EX_rt_addr)) ? write_data : held_rt_data_raw;
        end else if (flush) begin
            // Clear pipeline registers on reset or flush
            ID_EX_rs_data          <= 32'b0;
            ID_EX_rt_data          <= 32'b0;
            ID_EX_ext_imm          <= 32'b0;
            ID_EX_jump_target      <= 26'b0;
            ID_EX_ALU_control      <= 4'b0;
            ID_EX_alu_enable       <= 1'b0;
            ID_EX_reg_dst          <= 2'b0;
            ID_EX_alu_src_a        <= 2'b0;
            ID_EX_alu_src          <= 1'b0;
            ID_EX_mem_write        <= 1'b0;
            ID_EX_mem_read         <= 1'b0;
            ID_EX_mem_funct3       <= 3'b010;
            ID_EX_mem_to_reg       <= 2'b0;
            ID_EX_reg_write_enable <= 1'b0;
            ID_EX_pc_op            <= 1'b0;
            ID_EX_branch_type      <= 3'b0;
            ID_EX_jump             <= 1'b0;
            ID_EX_jump_register    <= 1'b0;
            ID_EX_halt             <= 1'b0;
            ID_EX_rs_addr          <= 5'b0;
            ID_EX_rt_addr          <= 5'b0;
            ID_EX_rd_addr          <= 5'b0;
            ID_EX_shamt            <= 5'b0;
            ID_EX_imm              <= 16'b0;
            ID_EX_sl               <= 5'b0;
            opcode_reg             <= 7'b0;
            func_reg               <= 7'b0;
            ID_pc                  <= 'h0 ;
            ID_EX_jalpc            <= 32'b0;
            ID_EX_valid            <= 1'b0;
            WriteReg_candidate     <= 5'b0;
        end else if (stall) begin
            // Insert one bubble for load-use hazards while IF holds the instruction.
            ID_EX_rs_data          <= 32'b0;
            ID_EX_rt_data          <= 32'b0;
            ID_EX_ext_imm          <= 32'b0;
            ID_EX_jump_target      <= 26'b0;
            ID_EX_ALU_control      <= 4'b0;
            ID_EX_alu_enable       <= 1'b0;
            ID_EX_reg_dst          <= 2'b0;
            ID_EX_alu_src_a        <= 2'b0;
            ID_EX_alu_src          <= 1'b0;
            ID_EX_mem_write        <= 1'b0;
            ID_EX_mem_read         <= 1'b0;
            ID_EX_mem_funct3       <= 3'b010;
            ID_EX_mem_to_reg       <= 2'b0;
            ID_EX_reg_write_enable <= 1'b0;
            ID_EX_pc_op            <= 1'b0;
            ID_EX_branch_type      <= 3'b0;
            ID_EX_jump             <= 1'b0;
            ID_EX_jump_register    <= 1'b0;
            ID_EX_halt             <= 1'b0;
            ID_EX_rs_addr          <= 5'b0;
            ID_EX_rt_addr          <= 5'b0;
            ID_EX_rd_addr          <= 5'b0;
            ID_EX_shamt            <= 5'b0;
            ID_EX_imm              <= 16'b0;
            ID_EX_sl               <= 5'b0;
            opcode_reg             <= 7'b0;
            func_reg               <= 7'b0;
            ID_pc                  <= 32'b0;
            ID_EX_jalpc            <= 32'b0;
            ID_EX_valid            <= 1'b0;
            WriteReg_candidate     <= 5'b0;
        end else begin
            // Update pipeline registers if not stalled
            ID_EX_rs_data          <= reg_rs_data;
            ID_EX_rt_data          <= reg_rt_data;
            ID_EX_ext_imm          <= extended_imm;
            ID_EX_jump_target      <= jump_target;
            ID_EX_ALU_control      <= control_ALU_control;
            ID_EX_alu_enable       <= control_alu_enable;
            ID_EX_reg_dst          <= control_reg_dst;
            ID_EX_alu_src_a        <= control_alu_src_a;
            ID_EX_alu_src          <= control_alu_src;
            ID_EX_mem_write        <= IF_ID_valid && control_mem_write;
            ID_EX_mem_read         <= IF_ID_valid && control_mem_read;
            ID_EX_mem_funct3       <= control_mem_funct3;
            ID_EX_mem_to_reg       <= control_mem_to_reg;
            ID_EX_reg_write_enable <= IF_ID_valid && control_reg_write_enable;
            ID_EX_pc_op            <= IF_ID_valid && control_pc_op;
            ID_EX_branch_type      <= control_branch_type;
            ID_EX_jump             <= IF_ID_valid && control_jump;
            ID_EX_jump_register    <= IF_ID_valid && control_jump_register;
            ID_EX_halt             <= IF_ID_valid && control_halt;
            ID_EX_rs_addr          <= rs_addr;
            ID_EX_rt_addr          <= rt_addr;
            ID_EX_rd_addr          <= rd_addr;
            ID_EX_shamt            <= shamt;
            ID_EX_imm              <= imm;
            ID_EX_sl               <= shamt;
            opcode_reg             <= opcode;
            func_reg               <= funct7;
            ID_pc                  <= IF_ID_pc;
            ID_EX_jalpc            <= IF_ID_jalpc;
            ID_EX_valid            <= IF_ID_valid;
            WriteReg_candidate     <= (IF_ID_valid && control_reg_write_enable) ? rd_addr : 5'b0;
        end
    end

endmodule
