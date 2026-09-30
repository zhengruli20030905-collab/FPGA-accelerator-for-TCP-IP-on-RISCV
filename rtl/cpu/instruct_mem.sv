module instruct_mem #(
    parameter [1023:0] IMEM_INIT_FILE = "software/boardprep_imem.hex",
    parameter [31:0] IMEM_BASE_ADDR = 32'h00003000,
    parameter integer IMEM_WORD_COUNT = 16384
) (
    input         clk,
    input         rst_n,
    input         read_en,
    input  [31:0] pc_addr,
    output        request_ready,
    output [31:0] instruction,
    output        response_valid,
    output [31:0] response_pc
);

    localparam integer IMEM_ADDR_W = $clog2(IMEM_WORD_COUNT);
    localparam [31:0] IMEM_END_ADDR = IMEM_BASE_ADDR + (IMEM_WORD_COUNT * 4);
    localparam [31:0] RV32I_NOP = 32'h00000013;

    wire address_valid;
    wire [31:0] address_word;
    wire [IMEM_ADDR_W-1:0] address;
    reg response_valid_r;
    reg [31:0] response_pc_r;
    wire request_fire = read_en && request_ready;

    assign address_valid = (pc_addr >= IMEM_BASE_ADDR) &&
                           (pc_addr < IMEM_END_ADDR) &&
                           (pc_addr[1:0] == 2'b00);
    assign address_word = (pc_addr - IMEM_BASE_ADDR) >> 2;
    assign address = address_word[IMEM_ADDR_W-1:0];
    assign response_valid = response_valid_r;
    assign response_pc = response_pc_r;

`ifdef V40_RANDOM_IMEM_WAIT
    integer sim_wait_max;
    reg [7:0] sim_wait_count;
    reg sim_wait_active;
    reg [15:0] sim_wait_lfsr;

    initial begin
        sim_wait_max = 3;
        if (!$value$plusargs("IMEM_WAIT_MAX=%d", sim_wait_max))
            sim_wait_max = 3;
    end

    assign request_ready = sim_wait_active && (sim_wait_count == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sim_wait_count <= 8'b0;
            sim_wait_active <= 1'b0;
            sim_wait_lfsr <= 16'h2D5B;
        end else begin
            sim_wait_lfsr <= {sim_wait_lfsr[14:0],
                              sim_wait_lfsr[15] ^ sim_wait_lfsr[13] ^
                              sim_wait_lfsr[12] ^ sim_wait_lfsr[10]};
            if (!sim_wait_active && read_en) begin
                sim_wait_active <= 1'b1;
                sim_wait_count <= sim_wait_lfsr[7:0] % (sim_wait_max + 1);
            end else if (sim_wait_active && (sim_wait_count != 0)) begin
                sim_wait_count <= sim_wait_count - 8'd1;
            end else if (request_fire) begin
                sim_wait_active <= 1'b0;
            end
        end
    end
`else
    assign request_ready = 1'b1;
`endif

`ifdef BOARD_DE2115
`ifndef V19_MII_SYSTEM_SIM
`define IMEM_USE_ALTSYNCRAM
`endif
`endif

`ifdef IMEM_USE_ALTSYNCRAM
    wire [31:0] ram_q;

    // V40 uses a true positive-edge synchronous M9K. A request accepted on
    // one rising edge is consumed by IF on the following rising edge.
    altsyncram #(
        .operation_mode("SINGLE_PORT"),
        .width_a(32),
        .widthad_a(IMEM_ADDR_W),
        .numwords_a(IMEM_WORD_COUNT),
        .outdata_reg_a("UNREGISTERED"),
        .address_aclr_a("NONE"),
        .outdata_aclr_a("NONE"),
        .read_during_write_mode_port_a("DONT_CARE"),
        .ram_block_type("M9K"),
        .init_file("../software/boardprep_imem.mif"),
        .init_file_layout("PORT_A"),
        .intended_device_family("Cyclone IV E"),
        .lpm_type("altsyncram")
    ) u_board_imem_ram (
        .address_a(address),
        .clock0(clk),
        .clocken0(1'b1),
        .data_a(32'b0),
        .rden_a(request_fire),
        .wren_a(1'b0),
        .aclr0(1'b0),
        .addressstall_a(1'b0),
        .q_a(ram_q)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            response_valid_r <= 1'b0;
            response_pc_r <= IMEM_BASE_ADDR;
        end else if (request_fire) begin
            response_valid_r <= address_valid;
            response_pc_r <= pc_addr;
        end else begin
            response_valid_r <= 1'b0;
        end
    end

    assign instruction = response_valid_r ? ram_q : RV32I_NOP;
`else
    reg [31:0] im [0:IMEM_WORD_COUNT-1];
    reg [31:0] instruction_reg;
    reg [1023:0] memfile;

    initial begin
        memfile = IMEM_INIT_FILE;
`ifndef SYNTHESIS
        if (!$value$plusargs("MEMFILE=%s", memfile))
            memfile = IMEM_INIT_FILE;
`endif
        $readmemh(memfile, im);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            response_valid_r <= 1'b0;
            response_pc_r <= IMEM_BASE_ADDR;
            instruction_reg <= RV32I_NOP;
        end else if (request_fire) begin
            response_valid_r <= address_valid;
            response_pc_r <= pc_addr;
            instruction_reg <= address_valid ? im[address] : RV32I_NOP;
        end else begin
            response_valid_r <= 1'b0;
        end
    end

    assign instruction = response_valid_r ? instruction_reg : RV32I_NOP;
`endif

endmodule

`ifdef IMEM_USE_ALTSYNCRAM
`undef IMEM_USE_ALTSYNCRAM
`endif
