module Mem_stage(
    input        clk,
    input        rst_n,

    // Inputs from EX/MEM pipeline register
    input [31:0] EX_MEM_ALUResult,
    input [31:0] EX_MEM_WriteData,
    input [4:0]  EX_MEM_WriteReg,
    input        EX_MEM_MemRead,           
    input        EX_MEM_MemWrite,          
    input [2:0]  EX_MEM_MemFunct3,
    input [1:0]  EX_MEM_MemToReg,    
    input        EX_MEM_RegWrite,
    input [31:0] EX_MEM_jalpc,
    input        EX_MEM_valid,

    // Outputs to MEM/WB pipeline register
    output reg [31:0] MEM_ALUResult,
    output reg [31:0] MEM_MemData,
    output reg [31:0] MEM_jalPC,
    output reg [4:0]  MEM_WriteReg,    
    output reg [1:0]  MEM_MemToReg,    
    output reg        MEM_RegWrite,
    output reg        MEM_valid,
    output             mem_stall,
    output [31:0]     MEM_forward_data
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

    // Memory data output
    wire [31:0] mem_dout;
    wire mem_req_ready;
    wire mem_rsp_valid;
    wire mem_rsp_error;
    reg  mem_pending;
    wire memory_op = EX_MEM_valid && (EX_MEM_MemRead || EX_MEM_MemWrite);
    wire request_start = memory_op && !mem_pending;
    wire request_fire = request_start && mem_req_ready;

    // EX/MEM is held while one synchronous transaction is outstanding. Reads
    // remain selected until response so MMIO read data stays stable; writes are
    // pulsed only on request_fire and therefore cannot be duplicated.
    assign mem_stall = memory_op && !(mem_pending && mem_rsp_valid);

    // Instantiate data memory on the shared CPU clock.
    data_mem dm (
        .clk       (clk),
        .rst_n       (rst_n),
        // req_start is a level-valid request; all write/read side effects use
        // request_fire so backpressure can never duplicate a transaction.
        .req_start (request_start),
        .req_ready (mem_req_ready),
        .rsp_valid (mem_rsp_valid),
        .rsp_error (mem_rsp_error),
        .mem_write (request_fire && EX_MEM_MemWrite),
        .mem_read  (request_fire && EX_MEM_MemRead),
        .mem_funct3(EX_MEM_MemFunct3),
        .addr      (EX_MEM_ALUResult),
        .din       (EX_MEM_WriteData),
        .dout      (mem_dout)
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

    assign MEM_forward_data = (EX_MEM_MemRead && mem_rsp_valid) ? mem_dout : MEM_MemData;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mem_pending <= 1'b0;
        else begin
            if (request_fire)
                mem_pending <= 1'b1;
            if (mem_pending && mem_rsp_valid)
                mem_pending <= 1'b0;
        end
    end

    // Pipeline register updates
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            MEM_ALUResult <= 32'b0;
            MEM_MemData   <= 32'b0;
            MEM_WriteReg  <= 5'b0;
            MEM_MemToReg  <= 2'b0;
            MEM_RegWrite  <= 1'b0;
            MEM_jalPC     <= 32'b0;
            MEM_valid     <= 1'b0;
        end else if (memory_op) begin
            if (mem_pending && mem_rsp_valid) begin
                MEM_ALUResult <= EX_MEM_ALUResult;
                MEM_MemData   <= EX_MEM_MemRead ? mem_dout : 32'b0;
                MEM_WriteReg  <= EX_MEM_WriteReg;
                MEM_MemToReg  <= EX_MEM_MemToReg;
                MEM_RegWrite  <= EX_MEM_RegWrite && !mem_rsp_error;
                MEM_jalPC     <= EX_MEM_jalpc;
                MEM_valid     <= 1'b1;
            end else begin
                MEM_RegWrite <= 1'b0;
                MEM_valid <= 1'b0;
            end
        end else begin
            MEM_ALUResult <= EX_MEM_ALUResult;
            MEM_WriteReg  <= EX_MEM_WriteReg;
            MEM_MemToReg  <= EX_MEM_MemToReg;
            MEM_RegWrite  <= EX_MEM_valid && EX_MEM_RegWrite;
            MEM_jalPC     <= EX_MEM_jalpc;
            MEM_MemData   <= 32'b0;
            MEM_valid     <= EX_MEM_valid;
        end
    end

endmodule
