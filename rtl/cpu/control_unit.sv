module control_unit (
    input [6:0] operation,
    input [2:0] funct3,
    input [6:0] funct7,
    input zero,
    input isLoad,
    input [4:0] rs1_ID, rs2_ID, rd_EX, rd_MEM,
    input RegWrite_EX, RegWrite_MEM,
    output reg alu_en,
    output reg [3:0] Aluctr,
    output reg [1:0] RegDst,
    output reg [1:0] AlusrcA,
    output reg Alusrc,
    output reg Reg_en,
    output reg mem_read,
    output reg mem_write,
    output reg [2:0] mem_funct3,
    output reg [1:0] mem_to_reg,
    output reg pc_op,
    output reg [2:0] imm_sel,
    output reg [2:0] branch_type,
    output reg jump,
    output reg jumpr,
    output reg halt,
    output reg stall
);

    localparam OP_R      = 7'b0110011;
    localparam OP_I      = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_MISC_MEM = 7'b0001111;
    localparam OP_SYSTEM = 7'b1110011;

    localparam ALU_ADD  = 4'b0001;
    localparam ALU_SUB  = 4'b0010;
    localparam ALU_AND  = 4'b0011;
    localparam ALU_OR   = 4'b0100;
    localparam ALU_XOR  = 4'b0101;
    localparam ALU_SLL  = 4'b0110;
    localparam ALU_SRL  = 4'b0111;
    localparam ALU_SRA  = 4'b1000;
    localparam ALU_SLT  = 4'b1001;
    localparam ALU_SLTU = 4'b1010;

    localparam IMM_NONE = 3'b000;
    localparam IMM_I    = 3'b001;
    localparam IMM_S    = 3'b010;
    localparam IMM_B    = 3'b011;
    localparam IMM_U    = 3'b100;
    localparam IMM_J    = 3'b101;

    localparam BR_NONE = 3'b000;
    localparam BR_BEQ  = 3'b001;
    localparam BR_BNE  = 3'b010;
    localparam BR_BLT  = 3'b011;
    localparam BR_BGE  = 3'b100;
    localparam BR_BLTU = 3'b101;
    localparam BR_BGEU = 3'b110;

    reg use_rs1;
    reg use_rs2;

    always @(*) begin
        use_rs1 = 1'b0;
        use_rs2 = 1'b0;

        case (operation)
            OP_R: begin
                use_rs1 = 1'b1;
                use_rs2 = 1'b1;
            end
            OP_I, OP_LOAD, OP_JALR: begin
                use_rs1 = 1'b1;
            end
            OP_STORE, OP_BRANCH: begin
                use_rs1 = 1'b1;
                use_rs2 = 1'b1;
            end
            default: begin
                use_rs1 = 1'b0;
                use_rs2 = 1'b0;
            end
        endcase
    end

    // Hazard Detection Unit
    always @(*) begin
        if (isLoad && RegWrite_EX && (rd_EX != 0) &&
            ((use_rs1 && (rd_EX == rs1_ID)) || (use_rs2 && (rd_EX == rs2_ID)))) begin
            stall = 1'b1;
        end else begin
            stall = 1'b0;
        end
    end

    always @(*) begin
        // Default Control Signals
        alu_en = 0;
        Aluctr = ALU_ADD;
        AlusrcA = 2'b00;       // 00: rs1, 01: pc, 10: zero
        Alusrc = 0;
        RegDst = 2'b01;        // RV32I writes the encoded rd field
        Reg_en = 0;
        mem_read = 0;
        mem_write = 0;
        mem_funct3 = 3'b010;
        mem_to_reg = 2'b00;    // 00: ALU, 01: memory, 10: pc + 4
        pc_op = 0;
        imm_sel = IMM_NONE;
        branch_type = BR_NONE;
        jump = 0;
        jumpr = 0;
        halt = 0;

        // Control signals based on RV32I opcode
        case(operation)
            OP_R: begin
                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_ADD;
                        end else if (funct7 == 7'b0100000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_SUB;
                        end else begin
                            halt = 1;
                        end
                    end
                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_SLL;
                        end else begin
                            halt = 1;
                        end
                    end
                    3'b010: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_SLT;
                        end else begin
                            halt = 1;
                        end
                    end
                    3'b011: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_SLTU;
                        end else begin
                            halt = 1;
                        end
                    end
                    3'b100: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_XOR;
                        end else begin
                            halt = 1;
                        end
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_SRL;
                        end else if (funct7 == 7'b0100000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_SRA;
                        end else begin
                            halt = 1;
                        end
                    end
                    3'b110: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_OR;
                        end else begin
                            halt = 1;
                        end
                    end
                    3'b111: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_AND;
                        end else begin
                            halt = 1;
                        end
                    end
                    default: begin
                        halt = 1;
                    end
                endcase
            end

            OP_I: begin
                Alusrc = 1;
                imm_sel = IMM_I;
                case (funct3)
                    3'b000: begin
                        alu_en = 1;
                        Reg_en = 1;
                        Aluctr = ALU_ADD;   // addi
                    end
                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_SLL;   // slli
                        end else begin
                            halt = 1;
                        end
                    end
                    3'b010: begin
                        alu_en = 1;
                        Reg_en = 1;
                        Aluctr = ALU_SLT;   // slti
                    end
                    3'b011: begin
                        alu_en = 1;
                        Reg_en = 1;
                        Aluctr = ALU_SLTU;  // sltiu
                    end
                    3'b100: begin
                        alu_en = 1;
                        Reg_en = 1;
                        Aluctr = ALU_XOR;   // xori
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_SRL;   // srli
                        end else if (funct7 == 7'b0100000) begin
                            alu_en = 1;
                            Reg_en = 1;
                            Aluctr = ALU_SRA;   // srai
                        end else begin
                            halt = 1;
                        end
                    end
                    3'b110: begin
                        alu_en = 1;
                        Reg_en = 1;
                        Aluctr = ALU_OR;    // ori
                    end
                    3'b111: begin
                        alu_en = 1;
                        Reg_en = 1;
                        Aluctr = ALU_AND;   // andi
                    end
                    default: begin
                        halt = 1;
                    end
                endcase
            end

            OP_LOAD: begin
                case (funct3)
                    3'b000, // lb
                    3'b001, // lh
                    3'b010, // lw
                    3'b100, // lbu
                    3'b101: begin // lhu
                        alu_en = 1;
                        Aluctr = ALU_ADD;
                        Alusrc = 1;
                        Reg_en = 1;
                        mem_read = 1;
                        mem_funct3 = funct3;
                        mem_to_reg = 2'b01;
                        imm_sel = IMM_I;
                    end
                    default: begin
                        halt = 1;
                    end
                endcase
            end

            OP_STORE: begin
                case (funct3)
                    3'b000, // sb
                    3'b001, // sh
                    3'b010: begin // sw
                        alu_en = 1;
                        Aluctr = ALU_ADD;
                        Alusrc = 1;
                        mem_write = 1;
                        mem_funct3 = funct3;
                        imm_sel = IMM_S;
                    end
                    default: begin
                        halt = 1;
                    end
                endcase
            end

            OP_BRANCH: begin
                imm_sel = IMM_B;
                case (funct3)
                    3'b000: begin
                        pc_op = 1;
                        branch_type = BR_BEQ;
                    end
                    3'b001: begin
                        pc_op = 1;
                        branch_type = BR_BNE;
                    end
                    3'b100: begin
                        pc_op = 1;
                        branch_type = BR_BLT;
                    end
                    3'b101: begin
                        pc_op = 1;
                        branch_type = BR_BGE;
                    end
                    3'b110: begin
                        pc_op = 1;
                        branch_type = BR_BLTU;
                    end
                    3'b111: begin
                        pc_op = 1;
                        branch_type = BR_BGEU;
                    end
                    default: begin
                        halt = 1;
                        branch_type = BR_NONE;
                    end
                endcase
            end

            OP_JAL: begin
                Reg_en = 1;
                mem_to_reg = 2'b10;
                jump = 1;
                imm_sel = IMM_J;
            end

            OP_JALR: begin
                if (funct3 == 3'b000) begin
                    alu_en = 1;
                    Aluctr = ALU_ADD;
                    Alusrc = 1;
                    Reg_en = 1;
                    mem_to_reg = 2'b10;
                    jumpr = 1;
                    imm_sel = IMM_I;
                end else begin
                    halt = 1;
                end
            end

            OP_LUI: begin
                alu_en = 1;
                Aluctr = ALU_ADD;
                AlusrcA = 2'b10;
                Alusrc = 1;
                Reg_en = 1;
                imm_sel = IMM_U;
            end

            OP_AUIPC: begin
                alu_en = 1;
                Aluctr = ALU_ADD;
                AlusrcA = 2'b01;
                Alusrc = 1;
                Reg_en = 1;
                imm_sel = IMM_U;
            end

            OP_MISC_MEM: begin
                // FENCE/FENCE.TSO are ordering barriers.  This core is
                // in-order and has no cache or write buffer, so no datapath
                // action is required; recognizing funct3=000 keeps the
                // architectural instruction legal for descriptor handoff.
                if (funct3 != 3'b000)
                    halt = 1;
            end

            OP_SYSTEM: begin
                // ecall/ebreak and unsupported SYSTEM instructions halt safely.
                halt = 1;
            end

            default: begin
                // Unsupported opcodes halt safely in this RV32I-only core.
                halt = 1;
            end
        endcase
    end
endmodule
