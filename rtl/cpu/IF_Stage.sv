module IF_Stage (
    input         clk,
    input         rst_n,
    input         stall,
    input         flush,
    input         pc_op,
    input         jump,
    input  [31:0] tmp,
    input         jumpr,
    input  [15:0] imm16,
    input  [25:0] imm26,
    input  [31:0] rsd,
    input         beq,
    input  [31:0] beq_pc,
    input  [31:0] branch_target,
    input  [31:0] ID_pc,
    output reg [31:0] IF_reg_instr,
    output reg [31:0] IF_reg_pc,
    output reg [31:0] IF_reg_jalPC,
    output reg        IF_reg_valid,
    output            mispredict
);

    localparam [31:0] RESET_PC = 32'h00003000;
    localparam [31:0] RV32I_NOP = 32'h00000013;

    // pc always denotes the address of the next request. On a redirect the
    // target request is issued immediately; the stale response is discarded.
    reg [31:0] pc;
    wire redirect = pc_op || beq || jump || jumpr;
    wire [31:0] fetch_addr = redirect ? branch_target : pc;
    wire read_en = !stall;
    wire [31:0] instr_from_mem;
    wire imem_request_ready;
    wire imem_response_valid;
    wire [31:0] imem_response_pc;
    wire imem_request_fire = read_en && imem_request_ready;
    reg [31:0] buffered_instr;
    reg [31:0] buffered_pc;
    reg        buffered_valid;

    assign mispredict = redirect;

    instruct_mem U_instruct_mem (
        .clk(clk),
        .rst_n(rst_n),
        .read_en(read_en),
        .pc_addr(fetch_addr),
        .request_ready(imem_request_ready),
        .instruction(instr_from_mem),
        .response_valid(imem_response_valid),
        .response_pc(imem_response_pc)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= RESET_PC;
            IF_reg_instr <= RV32I_NOP;
            IF_reg_pc <= 32'b0;
            IF_reg_jalPC <= 32'b0;
            IF_reg_valid <= 1'b0;
            buffered_instr <= RV32I_NOP;
            buffered_pc <= 32'b0;
            buffered_valid <= 1'b0;
        end else begin
            if (flush || redirect) begin
                pc <= imem_request_fire ? (branch_target + 32'd4) : branch_target;
                IF_reg_instr <= RV32I_NOP;
                IF_reg_pc <= 32'b0;
                IF_reg_jalPC <= 32'b0;
                IF_reg_valid <= 1'b0;
                buffered_valid <= 1'b0;
            end else if (stall) begin
                if (imem_response_valid && !buffered_valid) begin
                    buffered_instr <= instr_from_mem;
                    buffered_pc <= imem_response_pc;
                    buffered_valid <= 1'b1;
                end
            end else begin
                if (imem_request_fire)
                    pc <= fetch_addr + 32'd4;
                if (buffered_valid) begin
                    IF_reg_instr <= buffered_instr;
                    IF_reg_pc <= buffered_pc;
                    IF_reg_jalPC <= buffered_pc + 32'd4;
                    IF_reg_valid <= 1'b1;
                    buffered_valid <= 1'b0;
                end else if (imem_response_valid) begin
                    IF_reg_instr <= instr_from_mem;
                    IF_reg_pc <= imem_response_pc;
                    IF_reg_jalPC <= imem_response_pc + 32'd4;
                    IF_reg_valid <= 1'b1;
                end else begin
                    IF_reg_instr <= RV32I_NOP;
                    IF_reg_pc <= 32'b0;
                    IF_reg_jalPC <= 32'b0;
                    IF_reg_valid <= 1'b0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && read_en && (fetch_addr[1:0] != 2'b00))
            $display("TRAP: instruction PC is not word-aligned: %h", fetch_addr);
    end

    // Retain the old ports so the board hierarchy remains stable; V40 resolves
    // control flow in EX and protects the returned instruction with valid.
    wire unused_legacy_inputs = ^{tmp, imm16, imm26, rsd, beq_pc, ID_pc};

endmodule
