`include "soc_addr_map.svh"

// Memory-mapped MDIO/PHY reset block for DE2-115 ENET0.
//
// Register map:
//   0x10001100 MDIO_ADDR       [9:5] phy_addr, [4:0] reg_addr
//   0x10001104 MDIO_WDATA
//   0x10001108 MDIO_CMD        bit0=start, bit1=write_en
//   0x1000110c MDIO_RDATA
//   0x10001110 MDIO_STATUS     bit0=busy, bit1=done, bit2=error/timeout
//   0x10001114 PHY_RESET_CTRL  write bit0=sw_reset_n;
//                              read bit0=sw_reset_n, bit1=hw_done, bit2=pin
module phy_mdio_mmio #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer MDC_HZ = 1_000_000,
    parameter integer HW_RESET_CYCLES = 250_000,
    parameter integer SIM_PHY_MODEL = 0
) (
    input clk,
    input rst_n,
    input mem_write,
    input mem_read,
    input [31:0] addr,
    input [31:0] din,
    input mdio_in,
    output logic [31:0] dout,
    output logic phy_reset_n,
    output mdc,
    output mdio_drive_low
);

    localparam [31:0] MDIO_ADDR_ADDR      = `SOC_MDIO_ADDR_ADDR;
    localparam [31:0] MDIO_WDATA_ADDR     = `SOC_MDIO_WDATA_ADDR;
    localparam [31:0] MDIO_CMD_ADDR       = `SOC_MDIO_CMD_ADDR;
    localparam [31:0] MDIO_RDATA_ADDR     = `SOC_MDIO_RDATA_ADDR;
    localparam [31:0] MDIO_STATUS_ADDR    = `SOC_MDIO_STATUS_ADDR;
    localparam [31:0] PHY_RESET_CTRL_ADDR = `SOC_PHY_RESET_CTRL_ADDR;
    localparam integer RESET_CYCLES = (HW_RESET_CYCLES < 1) ? 1 : HW_RESET_CYCLES;

    reg [9:0] mdio_addr_reg;
    reg [15:0] mdio_wdata_reg;
    reg [15:0] mdio_rdata_reg;
    reg done_latched;
    reg error_latched;
    reg sw_reset_n;
    reg hw_reset_done;
    reg [31:0] reset_counter;
    reg master_start;
    reg master_write_en;

    wire master_busy;
    wire master_done;
    wire master_error;
    wire [15:0] master_rdata;

    wire mdio_addr_write;
    wire mdio_wdata_write;
    wire mdio_cmd_write;
    wire phy_reset_ctrl_write;

    wire mdio_addr_read;
    wire mdio_wdata_read;
    wire mdio_cmd_read;
    wire mdio_rdata_read;
    wire mdio_status_read;
    wire phy_reset_ctrl_read;

    assign mdio_addr_write = mem_write && (addr == MDIO_ADDR_ADDR);
    assign mdio_wdata_write = mem_write && (addr == MDIO_WDATA_ADDR);
    assign mdio_cmd_write = mem_write && (addr == MDIO_CMD_ADDR);
    assign phy_reset_ctrl_write = mem_write && (addr == PHY_RESET_CTRL_ADDR);

    assign mdio_addr_read = mem_read && (addr == MDIO_ADDR_ADDR);
    assign mdio_wdata_read = mem_read && (addr == MDIO_WDATA_ADDR);
    assign mdio_cmd_read = mem_read && (addr == MDIO_CMD_ADDR);
    assign mdio_rdata_read = mem_read && (addr == MDIO_RDATA_ADDR);
    assign mdio_status_read = mem_read && (addr == MDIO_STATUS_ADDR);
    assign phy_reset_ctrl_read = mem_read && (addr == PHY_RESET_CTRL_ADDR);

    function automatic [15:0] sim_phy_read;
        input [4:0] phy_addr;
        input [4:0] reg_addr;
        begin
            if (phy_addr != 5'h10) begin
                sim_phy_read = 16'hffff;
            end else begin
                case (reg_addr)
                    5'd1: sim_phy_read = 16'h786d;  // basic status, link bit set
                    5'd2: sim_phy_read = 16'h0141;  // 88E1111 PHY ID high
                    5'd3: sim_phy_read = 16'h0cc2;  // model bits 0x0cc0, revision 2
                    5'd17: sim_phy_read = 16'hac00; // useful nonzero vendor status sample
                    default: sim_phy_read = 16'h0000;
                endcase
            end
        end
    endfunction

    generate
        if (SIM_PHY_MODEL != 0) begin : g_sim_phy
            assign mdc = 1'b0;
            assign mdio_drive_low = 1'b0;
            assign master_busy = 1'b0;
            assign master_done = 1'b0;
            assign master_error = 1'b0;
            assign master_rdata = 16'b0;
        end else begin : g_real_mdio
            mdio_master #(
                .CLK_HZ(CLK_HZ),
                .MDC_HZ(MDC_HZ)
            ) u_mdio_master (
                .clk(clk),
                .rst_n(rst_n),
                .start(master_start),
                .write_en(master_write_en),
                .phy_addr(mdio_addr_reg[9:5]),
                .reg_addr(mdio_addr_reg[4:0]),
                .wdata(mdio_wdata_reg),
                .mdio_in(mdio_in),
                .rdata(master_rdata),
                .busy(master_busy),
                .done(master_done),
                .timeout(master_error),
                .mdc(mdc),
                .mdio_drive_low(mdio_drive_low)
            );
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reset_counter <= 32'b0;
            hw_reset_done <= 1'b0;
        end else if (!hw_reset_done) begin
            if (reset_counter >= (RESET_CYCLES - 1)) begin
                hw_reset_done <= 1'b1;
            end else begin
                reset_counter <= reset_counter + 32'd1;
            end
        end
    end

    always @(*) begin
        phy_reset_n = hw_reset_done && sw_reset_n;
    end

    // Keep MDIO command registers on the same edge as mdio_master so
    // master_start is a full-cycle pulse without a half-cycle timing path.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mdio_addr_reg <= {5'h10, 5'd0};
            mdio_wdata_reg <= 16'b0;
            mdio_rdata_reg <= 16'b0;
            done_latched <= 1'b0;
            error_latched <= 1'b0;
            sw_reset_n <= 1'b1;
            master_start <= 1'b0;
            master_write_en <= 1'b0;
        end else begin
            master_start <= 1'b0;

            if (master_done) begin
                mdio_rdata_reg <= master_rdata;
                done_latched <= 1'b1;
                error_latched <= master_error;
            end

            if (mdio_addr_write) begin
                mdio_addr_reg <= din[9:0];
            end

            if (mdio_wdata_write) begin
                mdio_wdata_reg <= din[15:0];
            end

            if (phy_reset_ctrl_write) begin
                sw_reset_n <= din[0];
            end

            if (mdio_cmd_write && din[0]) begin
                if (master_busy) begin
                    error_latched <= 1'b1;
                end else begin
                    done_latched <= 1'b0;
                    error_latched <= 1'b0;
                    master_write_en <= din[1];

                    if (SIM_PHY_MODEL != 0) begin
                        if (din[1]) begin
                            mdio_rdata_reg <= 16'b0;
                        end else begin
                            mdio_rdata_reg <= sim_phy_read(mdio_addr_reg[9:5],
                                                           mdio_addr_reg[4:0]);
                        end
                        done_latched <= 1'b1;
                    end else begin
                        master_start <= 1'b1;
                    end
                end
            end
        end
    end

    always @(*) begin
        if (mdio_addr_read) begin
            dout = {22'b0, mdio_addr_reg};
        end else if (mdio_wdata_read) begin
            dout = {16'b0, mdio_wdata_reg};
        end else if (mdio_cmd_read) begin
            dout = 32'b0;
        end else if (mdio_rdata_read) begin
            dout = {16'b0, mdio_rdata_reg};
        end else if (mdio_status_read) begin
            dout = {29'b0, error_latched, done_latched, master_busy};
        end else if (phy_reset_ctrl_read) begin
            dout = {29'b0, phy_reset_n, hw_reset_done, sw_reset_n};
        end else begin
            dout = 32'b0;
        end
    end

endmodule
