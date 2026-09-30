`include "tse_addr_map.svh"

// CPU-facing TSE control and CSR staging registers.
//
// This module owns CONTROL, STATUS, scratch, CSR address/write-data staging,
// and CSR command/status only. STREAM/TX/RX packet movement belongs to
// tse_stream_fifo_stub. Accepted CSR commands are single-cycle pulses;
// BOARD_DE2115 builds route them through tse_mii_board_if to generated IP.
module tse_mmio_regs(
    input clk,
    input rst_n,

    input mem_write,
    input mem_read,
    input [31:0] addr,
    input [31:0] din,
    output logic [31:0] dout,

    output logic probe_enable,
    output logic soft_reset_req,

    output logic [9:0] csr_address,
    output logic [31:0] csr_writedata,
    output logic csr_read,
    output logic csr_write,
    input [31:0] csr_readdata,
    input csr_waitrequest,
    input csr_readdatavalid,

    input tx_fifo_empty,
    input tx_fifo_full,
    input rx_fifo_empty,
    input rx_fifo_full
);

    localparam [31:0] ID_ADDR            = `TSE_MMIO_ID_ADDR;
    localparam [31:0] VERSION_ADDR       = `TSE_MMIO_VERSION_ADDR;
    localparam [31:0] CONTROL_ADDR       = `TSE_MMIO_CONTROL_ADDR;
    localparam [31:0] STATUS_ADDR        = `TSE_MMIO_STATUS_ADDR;
    localparam [31:0] SCRATCH_ADDR       = `TSE_MMIO_SCRATCH_ADDR;
    localparam [31:0] CSR_ADDR_ADDR      = `TSE_MMIO_CSR_ADDR_ADDR;
    localparam [31:0] CSR_WDATA_ADDR     = `TSE_MMIO_CSR_WDATA_ADDR;
    localparam [31:0] CSR_RDATA_ADDR     = `TSE_MMIO_CSR_RDATA_ADDR;
    localparam [31:0] CSR_CMD_ADDR       = `TSE_MMIO_CSR_CMD_ADDR;
    localparam [31:0] CSR_STATUS_ADDR    = `TSE_MMIO_CSR_STATUS_ADDR;
    // csr_read_pending spans command acceptance through readdatavalid.
    // csr_last_* are sampled status, not completion pulses.
    reg [31:0] scratch;
    reg [31:0] csr_rdata_hold;
    reg csr_read_pending;
    reg csr_last_waitrequest;
    reg csr_last_readdatavalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            probe_enable <= 1'b0;
            soft_reset_req <= 1'b0;
            csr_address <= 10'b0;
            csr_writedata <= 32'b0;
            csr_read <= 1'b0;
            csr_write <= 1'b0;
            csr_rdata_hold <= 32'b0;
            csr_read_pending <= 1'b0;
            csr_last_waitrequest <= 1'b0;
            csr_last_readdatavalid <= 1'b0;
            scratch <= 32'b0;
        end else begin
            csr_read <= 1'b0;
            csr_write <= 1'b0;
            csr_last_waitrequest <= csr_waitrequest;
            csr_last_readdatavalid <= csr_readdatavalid;

            if (csr_readdatavalid) begin
                csr_rdata_hold <= csr_readdata;
                csr_read_pending <= 1'b0;
            end

            if (mem_write) begin
                case (addr)
                    CONTROL_ADDR: begin
                        probe_enable <= din[0];
                        soft_reset_req <= din[1];
                    end
                    SCRATCH_ADDR: begin
                        scratch <= din;
                    end
                    CSR_ADDR_ADDR: begin
                        csr_address <= din[9:0];
                    end
                    CSR_WDATA_ADDR: begin
                        csr_writedata <= din;
                    end
                    CSR_CMD_ADDR: begin
                        if (din[0] && !csr_waitrequest) begin
                            csr_read <= 1'b1;
                            csr_read_pending <= 1'b1;
                        end
                        if (din[1] && !csr_waitrequest) begin
                            csr_write <= 1'b1;
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

    always_comb begin
        dout = 32'b0;
        if (mem_read) begin
            case (addr)
                ID_ADDR: begin
                    dout = `TSE_PROBE_ID_VALUE;
                end
                VERSION_ADDR: begin
                    dout = `TSE_PROBE_VERSION_VALUE;
                end
                CONTROL_ADDR: begin
                    dout = {30'b0, soft_reset_req, probe_enable};
                end
                STATUS_ADDR: begin
                    dout = {24'b0, rx_fifo_full, rx_fifo_empty,
                            tx_fifo_full, tx_fifo_empty,
                            csr_read_pending, csr_last_waitrequest,
                            soft_reset_req, probe_enable};
                end
                SCRATCH_ADDR: begin
                    dout = scratch;
                end
                CSR_ADDR_ADDR: begin
                    dout = {22'b0, csr_address};
                end
                CSR_WDATA_ADDR: begin
                    dout = csr_writedata;
                end
                CSR_RDATA_ADDR: begin
                    dout = csr_rdata_hold;
                end
                CSR_STATUS_ADDR: begin
                    dout = {28'b0, csr_last_readdatavalid, csr_last_waitrequest,
                            csr_read_pending, probe_enable};
                end
                default: begin
                end
            endcase
        end
    end

endmodule
