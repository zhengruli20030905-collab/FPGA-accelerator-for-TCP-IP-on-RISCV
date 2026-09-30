`include "soc_addr_map.svh"

// DE2-115 board GPIO MMIO.
//
// KEY reads return the raw board pins.  DE2-115 push-buttons are active-low, so
// a pressed key reads as 0 in this first bring-up version.
module board_gpio_mmio(
    input clk,
    input rst_n,
    input mem_write,
    input mem_read,
    input [31:0] addr,
    input [31:0] din,
    input [17:0] sw_in,
    input [3:0] key_in,
    output logic [17:0] ledr_out,
    output logic [8:0] ledg_out,
    output logic [31:0] dout
);

    localparam [31:0] BOARD_LEDR_ADDR = `SOC_BOARD_LEDR_ADDR;
    localparam [31:0] BOARD_LEDG_ADDR = `SOC_BOARD_LEDG_ADDR;
    localparam [31:0] BOARD_SW_ADDR   = `SOC_BOARD_SW_ADDR;
    localparam [31:0] BOARD_KEY_ADDR  = `SOC_BOARD_KEY_ADDR;

    wire ledr_write;
    wire ledg_write;
    wire ledr_read;
    wire ledg_read;
    wire sw_read;
    wire key_read;

    assign ledr_write = mem_write && (addr == BOARD_LEDR_ADDR);
    assign ledg_write = mem_write && (addr == BOARD_LEDG_ADDR);
    assign ledr_read = mem_read && (addr == BOARD_LEDR_ADDR);
    assign ledg_read = mem_read && (addr == BOARD_LEDG_ADDR);
    assign sw_read = mem_read && (addr == BOARD_SW_ADDR);
    assign key_read = mem_read && (addr == BOARD_KEY_ADDR);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ledr_out <= 18'b0;
            ledg_out <= 9'b0;
        end else begin
            if (ledr_write) begin
                ledr_out <= din[17:0];
            end

            if (ledg_write) begin
                ledg_out <= din[8:0];
            end
        end
    end

    always @(*) begin
        if (ledr_read) begin
            dout = {14'b0, ledr_out};
        end else if (ledg_read) begin
            dout = {23'b0, ledg_out};
        end else if (sw_read) begin
            dout = {14'b0, sw_in};
        end else if (key_read) begin
            dout = {28'b0, key_in};
        end else begin
            dout = 32'b0;
        end
    end

endmodule
