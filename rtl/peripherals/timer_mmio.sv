`include "soc_addr_map.svh"

// REAL/SOC-STRUCTURE
//
// Simple memory-mapped timer:
//   0x10000100 = TIMER_COUNTER
//   0x10000104 = TIMER_COMPARE
//   0x10000108 = TIMER_STATUS
//
// Counter increments every clock while reset is released. Compare is readable
// and writable. Status bit0 is counter >= compare. Future versions may add an
// interrupt output, but this boardprep version intentionally keeps polling.
module timer_mmio(
    input clk,
    input rst_n,
    input mem_write,
    input mem_read,
    input [31:0] addr,
    input [31:0] din,
    output logic [31:0] dout
);

    localparam [31:0] TIMER_COUNTER_ADDR = `SOC_TIMER_COUNTER_ADDR;
    localparam [31:0] TIMER_COMPARE_ADDR = `SOC_TIMER_COMPARE_ADDR;
    localparam [31:0] TIMER_STATUS_ADDR  = `SOC_TIMER_STATUS_ADDR;

    reg [31:0] timer_counter;
    reg [31:0] timer_compare;
    wire timer_expired;

    wire timer_counter_read;
    wire timer_compare_read;
    wire timer_status_read;
    wire timer_compare_write;

    assign timer_counter_read = mem_read && (addr == TIMER_COUNTER_ADDR);
    assign timer_compare_read = mem_read && (addr == TIMER_COMPARE_ADDR);
    assign timer_status_read = mem_read && (addr == TIMER_STATUS_ADDR);
    assign timer_compare_write = mem_write && (addr == TIMER_COMPARE_ADDR);
    assign timer_expired = (timer_counter >= timer_compare);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_counter <= 32'b0;
        end else begin
            timer_counter <= timer_counter + 32'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_compare <= 32'hffffffff;
        end else if (timer_compare_write) begin
            timer_compare <= din;
        end
    end

    always @(*) begin
        if (timer_counter_read) begin
            dout = timer_counter;
        end else if (timer_compare_read) begin
            dout = timer_compare;
        end else if (timer_status_read) begin
            dout = {31'b0, timer_expired};
        end else begin
            dout = 32'b0;
        end
    end

endmodule
