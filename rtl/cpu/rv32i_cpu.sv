module rv32i_cpu(
    input  clk,
    input  rst_n,
    output halted
`ifdef BOARD_DE2115
    ,
    input [17:0] board_sw,
    input [3:0] board_key,
    output [17:0] board_ledr,
    output [8:0] board_ledg,
    output uart_txd,
    output enet0_rst_n,
    output enet0_mdc,
    input enet0_mdio_in,
    output enet0_mdio_drive_low,
    input enet0_tx_clk,
    output [3:0] enet0_tx_data,
    output enet0_tx_en,
    output enet0_tx_er,
    input enet0_rx_clk,
    input [3:0] enet0_rx_data,
    input enet0_rx_dv,
    input enet0_rx_er,
    input enet0_rx_crs,
    input enet0_rx_col,
    input enet0_link100
`endif
`ifdef TSE_NET_SIM
    ,
    input [31:0] sim_tse_rx_data,
    input [1:0] sim_tse_rx_empty,
    input sim_tse_rx_valid,
    input sim_tse_rx_startofpacket,
    input sim_tse_rx_endofpacket,
    output sim_tse_rx_ready,
    output [31:0] sim_tse_tx_data,
    output [1:0] sim_tse_tx_empty,
    output sim_tse_tx_valid,
    output sim_tse_tx_startofpacket,
    output sim_tse_tx_endofpacket,
    input sim_tse_tx_ready
`endif
);

    wire [31:0] IF_ID_instr;
    wire [31:0] IF_ID_pc;
    wire [31:0] IF_ID_jalpc;
    wire        IF_ID_valid;
    wire        mispredict;

    wire [31:0] ID_EX_rs_data;
    wire [31:0] ID_EX_rt_data;
    wire [31:0] ID_EX_ext_imm;
    wire [25:0] ID_EX_jump_target;
    wire [3:0]  ID_EX_ALU_control;
    wire        ID_EX_alu_enable;
    wire [1:0]  ID_EX_reg_dst;
    wire [1:0]  ID_EX_alu_src_a;
    wire        ID_EX_alu_src;
    wire        ID_EX_mem_write;
    wire        ID_EX_mem_read;
    wire [2:0]  ID_EX_mem_funct3;
    wire [1:0]  ID_EX_mem_to_reg;
    wire        ID_EX_reg_write_enable;
    wire        ID_EX_pc_op;
    wire [2:0]  ID_EX_branch_type;
    wire        ID_EX_jump;
    wire        ID_EX_jump_register;
    wire        ID_EX_halt;
    wire [4:0]  ID_EX_rs_addr;
    wire [4:0]  ID_EX_rt_addr;
    wire [4:0]  ID_EX_rd_addr;
    wire [4:0]  ID_EX_shamt;
    wire [15:0] ID_EX_imm;
    wire [10:6] ID_EX_sl;
    wire [31:0] ID_pc;
    wire [31:0] ID_EX_jalpc;
    wire [6:0]  opcode_reg;
    wire [6:0]  func_reg;
    wire        ID_stall_request;
    wire        ID_EX_valid;

    wire [31:0] EX_ALUResult;
    wire [31:0] EX_WriteData;
    wire [4:0]  EX_WriteReg;
    wire        EX_MemRead;
    wire        EX_MemWrite;
    wire [2:0]  EX_MemFunct3;
    wire [1:0]  EX_MemToReg;
    wire        EX_RegWrite;
    wire        EX_Zero;
    wire [31:0] EX_pc;
    wire [31:0] EX_jalpc;
    wire        branch_taken;
    wire [31:0] branch_target;
    wire        flush_out;
    wire        EX_halt;
    wire        EX_valid;
    wire        trap_flush;

    wire [31:0] MEM_ALUResult;
    wire [31:0] MEM_MemData;
    wire [31:0] MEM_jalPC;
    wire [4:0]  MEM_WriteReg;
    wire [1:0]  MEM_MemToReg;
    wire        MEM_RegWrite;
    wire [31:0] MEM_forward_data;
    wire        MEM_valid;
    wire        mem_stall;

    wire [31:0] WB_WriteData;
    wire [4:0]  WB_WriteReg;
    wire        WB_RegWrite;
    reg  [31:0] WB_forward_data;

    always @(*) begin
        case (MEM_MemToReg)
            2'b00: WB_forward_data = MEM_ALUResult;
            2'b01: WB_forward_data = MEM_MemData;
            2'b10: WB_forward_data = MEM_jalPC;
            default: WB_forward_data = 32'b0;
        endcase
    end

    reg halted_r;
    assign halted = halted_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            halted_r <= 1'b0;
        else if (EX_halt)
            halted_r <= 1'b1;
    end

    wire pipeline_hold = mem_stall || halted_r;
    wire cpu_stall = ID_stall_request || pipeline_hold;
    assign trap_flush = flush_out || EX_halt;

    // Minimal v40 timing/performance counters. They are intentionally kept
    // outside the control path and are available to simulation or SignalTap
    // through hierarchy. No new MMIO address or software-visible behavior is
    // introduced in this timing-only version.
    (* preserve *) reg [31:0] perf_cycle_count;
    (* preserve *) reg [31:0] perf_retired_count;
    (* preserve *) reg [31:0] perf_load_use_stall_cycles;
    (* preserve *) reg [31:0] perf_imem_wait_cycles;
    (* preserve *) reg [31:0] perf_dmem_wait_cycles;
    (* preserve *) reg [31:0] perf_mmio_wait_cycles;
    (* preserve *) reg [31:0] perf_branch_flush_count;
    (* preserve *) reg [31:0] perf_trap_count;
    (* preserve *) reg [31:0] perf_pipeline_hold_cycles;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            perf_cycle_count           <= 32'b0;
            perf_retired_count         <= 32'b0;
            perf_load_use_stall_cycles <= 32'b0;
            perf_imem_wait_cycles      <= 32'b0;
            perf_dmem_wait_cycles      <= 32'b0;
            perf_mmio_wait_cycles      <= 32'b0;
            perf_branch_flush_count    <= 32'b0;
            perf_trap_count            <= 32'b0;
            perf_pipeline_hold_cycles  <= 32'b0;
        end else begin
            perf_cycle_count <= perf_cycle_count + 32'd1;
            if (MEM_valid)
                perf_retired_count <= perf_retired_count + 32'd1;
            if (ID_stall_request && !pipeline_hold)
                perf_load_use_stall_cycles <= perf_load_use_stall_cycles + 32'd1;
            if (!IF_ID_valid && !pipeline_hold && !trap_flush)
                perf_imem_wait_cycles <= perf_imem_wait_cycles + 32'd1;
            if (mem_stall && (EX_ALUResult < 32'h0002_0000))
                perf_dmem_wait_cycles <= perf_dmem_wait_cycles + 32'd1;
            if (mem_stall && (EX_ALUResult >= 32'h0002_0000))
                perf_mmio_wait_cycles <= perf_mmio_wait_cycles + 32'd1;
            if (branch_taken)
                perf_branch_flush_count <= perf_branch_flush_count + 32'd1;
            if (EX_halt && !halted_r)
                perf_trap_count <= perf_trap_count + 32'd1;
            if (mem_stall)
                perf_pipeline_hold_cycles <= perf_pipeline_hold_cycles + 32'd1;
        end
    end

    IF_Stage u_IF_Stage (
        .clk(clk),
        .rst_n(rst_n),
        .stall(cpu_stall),
        .flush(trap_flush),
        .pc_op(branch_taken),
        .jump(1'b0),
        .tmp(32'b0),
        .jumpr(1'b0),
        .imm16(16'b0),
        .imm26(26'b0),
        .rsd(32'b0),
        .beq(branch_taken),
        .beq_pc(EX_pc),
        .branch_target(branch_target),
        .ID_pc(branch_target),
        .IF_reg_instr(IF_ID_instr),
        .IF_reg_pc(IF_ID_pc),
        .IF_reg_jalPC(IF_ID_jalpc),
        .IF_reg_valid(IF_ID_valid),
        .mispredict(mispredict)
    );

    ID_Stage u_ID_Stage (
        .clk(clk),
        .rst_n(rst_n),
        .IF_ID_instr(IF_ID_instr),
        .IF_ID_pc(IF_ID_pc),
        .IF_ID_jalpc(IF_ID_jalpc),
        .IF_ID_valid(IF_ID_valid),
        .write_data(WB_WriteData),
        .write_addr(WB_WriteReg),
        .WB_RegWrite(WB_RegWrite),
        .stall(ID_stall_request),
        .hold(pipeline_hold),
        .flush(trap_flush),
        .EX_MEM_rd_addr(EX_WriteReg),
        .EX_MEM_reg_write_enable(EX_RegWrite),
        .ID_EX_rs_data(ID_EX_rs_data),
        .ID_EX_rt_data(ID_EX_rt_data),
        .ID_EX_ext_imm(ID_EX_ext_imm),
        .ID_EX_jump_target(ID_EX_jump_target),
        .ID_EX_ALU_control(ID_EX_ALU_control),
        .ID_EX_alu_enable(ID_EX_alu_enable),
        .ID_EX_reg_dst(ID_EX_reg_dst),
        .ID_EX_alu_src_a(ID_EX_alu_src_a),
        .ID_EX_alu_src(ID_EX_alu_src),
        .ID_EX_mem_write(ID_EX_mem_write),
        .ID_EX_mem_read(ID_EX_mem_read),
        .ID_EX_mem_funct3(ID_EX_mem_funct3),
        .ID_EX_mem_to_reg(ID_EX_mem_to_reg),
        .ID_EX_reg_write_enable(ID_EX_reg_write_enable),
        .ID_EX_pc_op(ID_EX_pc_op),
        .ID_EX_branch_type(ID_EX_branch_type),
        .ID_EX_jump(ID_EX_jump),
        .ID_EX_jump_register(ID_EX_jump_register),
        .ID_EX_halt(ID_EX_halt),
        .ID_EX_rs_addr(ID_EX_rs_addr),
        .ID_EX_rt_addr(ID_EX_rt_addr),
        .ID_EX_rd_addr(ID_EX_rd_addr),
        .ID_EX_shamt(ID_EX_shamt),
        .ID_EX_imm(ID_EX_imm),
        .ID_EX_sl(ID_EX_sl),
        .ID_pc(ID_pc),
        .ID_EX_jalpc(ID_EX_jalpc),
        .ID_EX_valid(ID_EX_valid),
        .opcode_reg(opcode_reg),
        .func_reg(func_reg),
        .ID_stall_request(ID_stall_request)
    );

    EX_Stage u_EX_Stage (
        .clk(clk),
        .rst_n(rst_n),
        .stall(pipeline_hold),
        .ID_EX_pc(ID_pc),
        .ID_EX_jalpc(ID_EX_jalpc),
        .ID_EX_rs_data(ID_EX_rs_data),
        .ID_EX_rt_data(ID_EX_rt_data),
        .ID_EX_ext_imm(ID_EX_ext_imm),
        .ID_EX_ALU_control(ID_EX_ALU_control),
        .ID_EX_alu_enable(ID_EX_alu_enable),
        .ID_EX_reg_dst(ID_EX_reg_dst),
        .ID_EX_alu_src_a(ID_EX_alu_src_a),
        .ID_EX_alu_src(ID_EX_alu_src),
        .ID_EX_mem_write(ID_EX_mem_write),
        .ID_EX_mem_read(ID_EX_mem_read),
        .ID_EX_mem_funct3(ID_EX_mem_funct3),
        .ID_EX_mem_to_reg(ID_EX_mem_to_reg),
        .ID_EX_reg_write_enable(ID_EX_reg_write_enable),
        .ID_EX_rs_addr(ID_EX_rs_addr),
        .ID_EX_rt_addr(ID_EX_rt_addr),
        .ID_EX_rd_addr(ID_EX_rd_addr),
        .ID_EX_shamt(ID_EX_shamt),
        .ID_EX_pc_op(ID_EX_pc_op),
        .ID_EX_branch_type(ID_EX_branch_type),
        .ID_EX_jump(ID_EX_jump),
        .ID_EX_jump_register(ID_EX_jump_register),
        .ID_EX_halt(ID_EX_halt),
        .ID_EX_valid(ID_EX_valid),
        .ID_EX_imm(ID_EX_imm),
        .MEM_WB_rd_addr(MEM_WriteReg),
        .MEM_WB_reg_write_enable(MEM_RegWrite),
        .WB_mux_WB(WB_forward_data),
        .WB_rd_addr(WB_WriteReg),
        .WB_reg_write_enable(WB_RegWrite),
        .WB_forward_data(WB_WriteData),
        .MEM_forward_data(MEM_forward_data),
        .EX_ALUResult(EX_ALUResult),
        .EX_WriteData(EX_WriteData),
        .EX_WriteReg(EX_WriteReg),
        .EX_MemRead(EX_MemRead),
        .EX_MemWrite(EX_MemWrite),
        .EX_MemFunct3(EX_MemFunct3),
        .EX_MemToReg(EX_MemToReg),
        .EX_RegWrite(EX_RegWrite),
        .EX_Zero(EX_Zero),
        .EX_pc(EX_pc),
        .EX_jalpc(EX_jalpc),
        .EX_valid(EX_valid),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .flush_out(flush_out),
        .halt_out(EX_halt)
    );

    Mem_stage u_Mem_stage (
        .clk(clk),
        .rst_n(rst_n),
        .EX_MEM_ALUResult(EX_ALUResult),
        .EX_MEM_WriteData(EX_WriteData),
        .EX_MEM_WriteReg(EX_WriteReg),
        .EX_MEM_MemRead(EX_MemRead),
        .EX_MEM_MemWrite(EX_MemWrite),
        .EX_MEM_MemFunct3(EX_MemFunct3),
        .EX_MEM_MemToReg(EX_MemToReg),
        .EX_MEM_RegWrite(EX_RegWrite),
        .EX_MEM_jalpc(EX_jalpc),
        .EX_MEM_valid(EX_valid),
        .MEM_ALUResult(MEM_ALUResult),
        .MEM_MemData(MEM_MemData),
        .MEM_jalPC(MEM_jalPC),
        .MEM_WriteReg(MEM_WriteReg),
        .MEM_MemToReg(MEM_MemToReg),
        .MEM_RegWrite(MEM_RegWrite),
        .MEM_valid(MEM_valid),
        .mem_stall(mem_stall),
        .MEM_forward_data(MEM_forward_data)
`ifdef BOARD_DE2115
        ,
        .board_sw(board_sw),
        .board_key(board_key),
        .board_ledr(board_ledr),
        .board_ledg(board_ledg),
        .uart_txd(uart_txd),
        .enet0_rst_n(enet0_rst_n),
        .enet0_mdc(enet0_mdc),
        .enet0_mdio_in(enet0_mdio_in),
        .enet0_mdio_drive_low(enet0_mdio_drive_low),
        .enet0_tx_clk(enet0_tx_clk),
        .enet0_tx_data(enet0_tx_data),
        .enet0_tx_en(enet0_tx_en),
        .enet0_tx_er(enet0_tx_er),
        .enet0_rx_clk(enet0_rx_clk),
        .enet0_rx_data(enet0_rx_data),
        .enet0_rx_dv(enet0_rx_dv),
        .enet0_rx_er(enet0_rx_er),
        .enet0_rx_crs(enet0_rx_crs),
        .enet0_rx_col(enet0_rx_col),
        .enet0_link100(enet0_link100)
`endif
`ifdef TSE_NET_SIM
        ,
        .sim_tse_rx_data(sim_tse_rx_data),
        .sim_tse_rx_empty(sim_tse_rx_empty),
        .sim_tse_rx_valid(sim_tse_rx_valid),
        .sim_tse_rx_startofpacket(sim_tse_rx_startofpacket),
        .sim_tse_rx_endofpacket(sim_tse_rx_endofpacket),
        .sim_tse_rx_ready(sim_tse_rx_ready),
        .sim_tse_tx_data(sim_tse_tx_data),
        .sim_tse_tx_empty(sim_tse_tx_empty),
        .sim_tse_tx_valid(sim_tse_tx_valid),
        .sim_tse_tx_startofpacket(sim_tse_tx_startofpacket),
        .sim_tse_tx_endofpacket(sim_tse_tx_endofpacket),
        .sim_tse_tx_ready(sim_tse_tx_ready)
`endif
    );

    WB_Stage u_WB_Stage (
        .clk(clk),
        .rst_n(rst_n),
        .MEM_WB_ALUResult(MEM_ALUResult),
        .MEM_WB_MemData(MEM_MemData),
        .MEM_WB_jalPC(MEM_jalPC),
        .MEM_WB_WriteReg(MEM_WriteReg),
        .MEM_WB_MemToReg(MEM_MemToReg),
        .MEM_WB_RegWrite(MEM_RegWrite),
        .MEM_WB_valid(MEM_valid),
        .WB_WriteData(WB_WriteData),
        .WB_WriteReg(WB_WriteReg),
        .WB_RegWrite(WB_RegWrite)
    );

endmodule
