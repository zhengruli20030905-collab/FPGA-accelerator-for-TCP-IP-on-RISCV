`include "soc_addr_map.svh"

// REAL/SOC-STRUCTURE
//
// 128 KiB low-address data RAM:
//   0x00000000 - 0x0001ffff
//
// This module preserves the Version7 RV32I byte/halfword/word load-store
// behavior, little-endian byte lanes, and +DMEMFILE initialization. The dm[]
// array remains visible for the simulation testbench through:
//   uut.u_Mem_stage.dm.u_data_ram.dm[word_addr]
module data_ram #(
    parameter [1023:0] DMEM_INIT_FILE = "software/boardprep_dmem.hex",
    parameter integer DMA_ENABLE = 0
) (
    input clk,
    input rst_n,
    input mem_write,
    input mem_read,
    input [2:0] mem_funct3,
    input [31:0] addr,
    input [31:0] din,
    output logic [31:0] dout,

    input dma_access_active,
    input descriptor_lock_valid,
    input [31:0] descriptor_lock_addr,
    input [31:0] descriptor_lock_length,
    input payload_lock_valid,
    input [31:0] payload_lock_addr,
    input [31:0] payload_lock_length,
    input dma_req, input dma_write, input [31:0] dma_addr,
    input [31:0] dma_wdata, input [3:0] dma_byteena,
    output dma_ready, output logic dma_rvalid,
    output [31:0] dma_rdata,
    output descriptor_conflict,
    output payload_conflict
);

// BOARD_DE2115 normally selects the Cyclone IV altsyncram implementation.
// v19's ModelSim-only CPU/TSE/MII test needs the visible behavioral RAM so it
// can load an independent diagnostic image with +DMEMFILE and inspect result
// markers.  This define is never supplied to Quartus or board builds.
`ifdef BOARD_DE2115
`ifndef V19_MII_SYSTEM_SIM
`define DATA_RAM_USE_ALTSYNCRAM
`endif
`endif

    localparam integer RAM_WORD_COUNT = `SOC_DATA_RAM_WORD_COUNT;

    wire [14:0] ram_word_addr;
    wire [1:0] byte_offset;
`ifdef DATA_RAM_USE_ALTSYNCRAM
    wire [31:0] ram_q;
`else
    (* ramstyle = "M9K" *) reg [31:0] dm [0:RAM_WORD_COUNT-1];
`endif

    reg [1023:0] dmemfile;
    reg has_dmemfile;

    integer i;
    reg [7:0] load_byte;
    reg [15:0] load_half;

`ifdef DATA_RAM_USE_ALTSYNCRAM
    wire [31:0] ram_read_word;
    reg [1:0] ram_read_byte_offset;
    reg [2:0] ram_read_funct3;
    reg ram_read_valid;
    reg [3:0] ram_byteena;
    reg [31:0] ram_write_data;
`endif

    assign ram_word_addr = addr[16:2];
    assign byte_offset = addr[1:0];

    wire descriptor_locked_word = DMA_ENABLE && descriptor_lock_valid &&
        ({2'd0,addr[31:2]} >= (descriptor_lock_addr >> 2)) &&
        ({2'd0,addr[31:2]} <
         ((descriptor_lock_addr + descriptor_lock_length + 3) >> 2));
    wire payload_locked_word = DMA_ENABLE && payload_lock_valid &&
        ({2'd0,addr[31:2]} >= (payload_lock_addr >> 2)) &&
        ({2'd0,addr[31:2]} <
         ((payload_lock_addr + payload_lock_length + 3) >> 2));
    // Descriptor reads are allowed so software can poll OWN/STATUS. Writes to
    // either owned range are blocked; payload reads retain the V30 exclusion.
    wire cpu_read = mem_read && !payload_locked_word;
    wire cpu_write = mem_write && !descriptor_locked_word &&
                     !payload_locked_word;
    reg descriptor_conflict_at_cpu_edge;
    reg payload_conflict_at_cpu_edge;
    assign descriptor_conflict = DMA_ENABLE && descriptor_lock_valid &&
        (descriptor_conflict_at_cpu_edge ||
         (descriptor_locked_word && mem_write));
    assign payload_conflict = DMA_ENABLE && payload_lock_valid &&
        (payload_conflict_at_cpu_edge ||
         (payload_locked_word && (mem_read || mem_write)));
    assign dma_ready = DMA_ENABLE && rst_n && dma_access_active &&
                       !descriptor_conflict && !payload_conflict;
    wire dma_fire = dma_req && dma_ready;
    wire [31:0] dma_q;
    assign dma_rdata = DMA_ENABLE ? dma_q : 32'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            descriptor_conflict_at_cpu_edge <= 1'b0;
            payload_conflict_at_cpu_edge <= 1'b0;
        end else begin
            descriptor_conflict_at_cpu_edge <= descriptor_locked_word && mem_write;
            payload_conflict_at_cpu_edge <= payload_locked_word &&
                                            (mem_read || mem_write);
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dma_rvalid <= 1'b0;
        else dma_rvalid <= dma_fire && !dma_write;
    end

`ifdef DATA_RAM_USE_ALTSYNCRAM
    assign ram_read_word = ram_q;

    altsyncram #(
        .operation_mode(DMA_ENABLE ? "BIDIR_DUAL_PORT" : "SINGLE_PORT"),
        .width_a(32),
        .widthad_a(15),
        .numwords_a(RAM_WORD_COUNT),
        .width_byteena_a(4),
        .width_b(32),
        .widthad_b(15),
        .numwords_b(RAM_WORD_COUNT),
        .width_byteena_b(4),
        .address_reg_b("CLOCK1"),
        .indata_reg_b("CLOCK1"),
        .wrcontrol_wraddress_reg_b("CLOCK1"),
        .byteena_reg_b("CLOCK1"),
        .outdata_reg_b("UNREGISTERED"),
        .read_during_write_mode_port_b("NEW_DATA_WITH_NBE_READ"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .byte_size(8),
        .outdata_reg_a("UNREGISTERED"),
        .address_aclr_a("NONE"),
        .indata_aclr_a("NONE"),
        .wrcontrol_aclr_a("NONE"),
        .byteena_aclr_a("NONE"),
        .outdata_aclr_a("NONE"),
        .read_during_write_mode_port_a("NEW_DATA_WITH_NBE_READ"),
        .ram_block_type("M9K"),
        .init_file("../software/boardprep_dmem.mif"),
        .init_file_layout("PORT_A"),
        .intended_device_family("Cyclone IV E"),
        .lpm_type("altsyncram")
    ) u_board_dmem_ram (
        .address_a(ram_word_addr),
        .byteena_a(ram_byteena),
        .clock0(clk),
        .clocken0(1'b1),
        .data_a(ram_write_data),
        .rden_a(cpu_read),
        .wren_a(cpu_write && (ram_byteena != 4'b0000)),
        .clock1(clk),
        .clocken1(1'b1),
        .clocken2(1'b1),
        .clocken3(1'b1),
        .eccstatus(),
        .aclr1(1'b0),
        .address_b(dma_addr[16:2]),
        .addressstall_b(1'b0),
        .data_b(dma_wdata),
        .byteena_b(dma_byteena),
        .rden_b(dma_fire && !dma_write),
        .wren_b(dma_fire && dma_write),
        .q_b(dma_q),
        .aclr0(1'b0),
        .addressstall_a(1'b0),
        .q_a(ram_q)
    );

    always @(*) begin
        ram_byteena = 4'b0000;
        ram_write_data = din;

        if (mem_write) begin
            case (mem_funct3)
                3'b000: begin
                    case (byte_offset)
                        2'b00: begin
                            ram_byteena = 4'b0001;
                            ram_write_data = {24'b0, din[7:0]};
                        end
                        2'b01: begin
                            ram_byteena = 4'b0010;
                            ram_write_data = {16'b0, din[7:0], 8'b0};
                        end
                        2'b10: begin
                            ram_byteena = 4'b0100;
                            ram_write_data = {8'b0, din[7:0], 16'b0};
                        end
                        2'b11: begin
                            ram_byteena = 4'b1000;
                            ram_write_data = {din[7:0], 24'b0};
                        end
                        default: begin
                            ram_byteena = 4'b0000;
                            ram_write_data = din;
                        end
                    endcase
                end
                3'b001: begin
                    if (byte_offset[1] == 1'b0) begin
                        ram_byteena = 4'b0011;
                        ram_write_data = {16'b0, din[15:0]};
                    end else begin
                        ram_byteena = 4'b1100;
                        ram_write_data = {din[15:0], 16'b0};
                    end
                end
                3'b010: begin
                    ram_byteena = 4'b1111;
                    ram_write_data = din;
                end
                default: begin
                    ram_byteena = 4'b0000;
                    ram_write_data = din;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ram_read_byte_offset <= 2'b0;
            ram_read_funct3 <= 3'b010;
            ram_read_valid <= 1'b0;
        end else begin
            if (cpu_read) begin
                ram_read_byte_offset <= byte_offset;
                ram_read_funct3 <= mem_funct3;
                ram_read_valid <= 1'b1;
            end else begin
                ram_read_byte_offset <= 2'b0;
                ram_read_funct3 <= 3'b010;
                ram_read_valid <= 1'b0;
            end
        end
    end

    always @(*) begin
        case (ram_read_byte_offset)
            2'b00: load_byte = ram_read_word[7:0];
            2'b01: load_byte = ram_read_word[15:8];
            2'b10: load_byte = ram_read_word[23:16];
            2'b11: load_byte = ram_read_word[31:24];
            default: load_byte = 8'b0;
        endcase

        if (ram_read_byte_offset[1] == 1'b0) begin
            load_half = ram_read_word[15:0];
        end else begin
            load_half = ram_read_word[31:16];
        end
    end

    always @(*) begin
        if (ram_read_valid) begin
            case (ram_read_funct3)
                3'b000: dout = {{24{load_byte[7]}}, load_byte};
                3'b001: dout = {{16{load_half[15]}}, load_half};
                3'b010: dout = ram_read_word;
                3'b100: dout = {24'b0, load_byte};
                3'b101: dout = {16'b0, load_half};
                default: dout = 32'b0;
            endcase
        end else begin
            dout = 32'b0;
        end
    end
`else
    reg [31:0] dma_q_sim;
    reg [31:0] cpu_read_word_sim;
    reg [1:0] cpu_read_byte_offset_sim;
    reg [2:0] cpu_read_funct3_sim;
    reg cpu_read_valid_sim;
    assign dma_q = dma_q_sim;
    integer dma_lane;
    // Independent port B. The behavioral model preserves the same posedge
    // read/write contract as altsyncram; legacy CPU and test helpers use A.
    always @(posedge clk) begin
        if (dma_fire) begin
            if (dma_write) begin
                for (dma_lane = 0; dma_lane < 4; dma_lane = dma_lane + 1)
                    if (dma_byteena[dma_lane])
                        dm[dma_addr[16:2]][dma_lane*8 +: 8] <= dma_wdata[dma_lane*8 +: 8];
            end else dma_q_sim <= dm[dma_addr[16:2]];
        end
    end
    task init_dmem;
        begin
`ifndef DATA_RAM_USE_ALTSYNCRAM
            for (i = 0; i < RAM_WORD_COUNT; i = i + 1) begin
                dm[i] = 32'b0;
            end

`endif
`ifdef DATA_RAM_USE_ALTSYNCRAM
            $readmemh("../software/boardprep_dmem.hex", dm);
`else
            $readmemh(dmemfile, dm);
`endif
        end
    endtask

    initial begin
        dmemfile = DMEM_INIT_FILE;
`ifdef DATA_RAM_USE_ALTSYNCRAM
        has_dmemfile = 1'b0;
`else
`ifndef SYNTHESIS
        has_dmemfile = $value$plusargs("DMEMFILE=%s", dmemfile);
        if (!has_dmemfile)
            dmemfile = DMEM_INIT_FILE;
`else
        has_dmemfile = 1'b0;
`endif
`endif
        init_dmem();
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
`ifndef DATA_RAM_USE_ALTSYNCRAM
            init_dmem();
`endif
            cpu_read_word_sim <= 32'b0;
            cpu_read_byte_offset_sim <= 2'b0;
            cpu_read_funct3_sim <= 3'b010;
            cpu_read_valid_sim <= 1'b0;
        end else begin
            cpu_read_valid_sim <= cpu_read;
            if (cpu_read) begin
                cpu_read_word_sim <= dm[ram_word_addr];
                cpu_read_byte_offset_sim <= byte_offset;
                cpu_read_funct3_sim <= mem_funct3;
            end
            if (cpu_write) begin
                case (mem_funct3)
                    3'b000: begin
                        case (byte_offset)
                            2'b00: dm[ram_word_addr][7:0] <= din[7:0];
                            2'b01: dm[ram_word_addr][15:8] <= din[7:0];
                            2'b10: dm[ram_word_addr][23:16] <= din[7:0];
                            2'b11: dm[ram_word_addr][31:24] <= din[7:0];
                            default: dm[ram_word_addr] <= dm[ram_word_addr];
                        endcase
                    end
                    3'b001: begin
                        if (byte_offset[1] == 1'b0) begin
                            dm[ram_word_addr][15:0] <= din[15:0];
                        end else begin
                            dm[ram_word_addr][31:16] <= din[15:0];
                        end
                    end
                    3'b010: begin
                        dm[ram_word_addr] <= din;
                    end
                    default: begin
                        dm[ram_word_addr] <= dm[ram_word_addr];
                    end
                endcase
            end
        end
    end

    always @(*) begin
        case (cpu_read_byte_offset_sim)
            2'b00: load_byte = cpu_read_word_sim[7:0];
            2'b01: load_byte = cpu_read_word_sim[15:8];
            2'b10: load_byte = cpu_read_word_sim[23:16];
            2'b11: load_byte = cpu_read_word_sim[31:24];
            default: load_byte = 8'b0;
        endcase

        if (cpu_read_byte_offset_sim[1] == 1'b0) begin
            load_half = cpu_read_word_sim[15:0];
        end else begin
            load_half = cpu_read_word_sim[31:16];
        end
    end

    always @(*) begin
        if (cpu_read_valid_sim) begin
            case (cpu_read_funct3_sim)
                3'b000: dout = {{24{load_byte[7]}}, load_byte};
                3'b001: dout = {{16{load_half[15]}}, load_half};
                3'b010: dout = cpu_read_word_sim;
                3'b100: dout = {24'b0, load_byte};
                3'b101: dout = {16'b0, load_half};
                default: dout = 32'b0;
            endcase
        end else begin
            dout = 32'b0;
        end
    end

`endif
endmodule

// This local selection must not affect source files compiled after this one.
`ifdef DATA_RAM_USE_ALTSYNCRAM
`undef DATA_RAM_USE_ALTSYNCRAM
`endif
