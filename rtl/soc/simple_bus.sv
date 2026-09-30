`include "soc_addr_map.svh"
`include "dma_addr_map.svh"

// REAL/SOC-STRUCTURE
//
// simple_bus owns only address decode, peripheral request strobes, and the
// read-data mux. Peripheral state and transaction sequencing stay in the
// selected endpoint. It represents the small SoC interconnect concept:
//   - low 128 KiB RAM
//   - high-address UART MMIO
//   - high-address timer MMIO
//   - board GPIO MMIO
//   - PHY MDIO MMIO
//   - TSE wrapper CPU-facing MMIO/CSR staging window
//
// Writes to unmapped addresses are ignored. Reads from unmapped addresses
// return zero. The optional warning below is simulation debug only.
module simple_bus(
    input clk,
    input rst_n,
    input mem_write,
    input mem_read,
    input [31:0] addr,
    input [31:0] ram_dout,
    input [31:0] uart_dout,
    input [31:0] timer_dout,
    input [31:0] board_dout,
    input [31:0] mdio_dout,
    input [31:0] tse_dout,
    input [31:0] dma_dout,
    output dma_mem_write, output dma_mem_read,
    output logic ram_mem_write,
    output logic ram_mem_read,
    output logic uart_mem_write,
    output logic uart_mem_read,
    output logic timer_mem_write,
    output logic timer_mem_read,
    output logic board_mem_write,
    output logic board_mem_read,
    output logic mdio_mem_write,
    output logic mdio_mem_read,
    output logic tse_mem_write,
    output logic tse_mem_read,
    output logic [31:0] dout
);

    localparam [31:0] DATA_RAM_START_ADDR = `SOC_DATA_RAM_START_ADDR;
    localparam [31:0] DATA_RAM_END_ADDR   = `SOC_DATA_RAM_END_ADDR;
    localparam [31:0] UART_TX_DATA_ADDR   = `SOC_UART_TX_DATA_ADDR;
    localparam [31:0] UART_STATUS_ADDR    = `SOC_UART_STATUS_ADDR;
    localparam [31:0] UART_CTRL_ADDR      = `SOC_UART_CTRL_ADDR;
    localparam [31:0] UART_TX_LEVEL_ADDR  = `SOC_UART_TX_LEVEL_ADDR;
    localparam [31:0] TIMER_COUNTER_ADDR  = `SOC_TIMER_COUNTER_ADDR;
    localparam [31:0] TIMER_COMPARE_ADDR  = `SOC_TIMER_COMPARE_ADDR;
    localparam [31:0] TIMER_STATUS_ADDR   = `SOC_TIMER_STATUS_ADDR;
    localparam [31:0] MDIO_BASE_ADDR      = `SOC_MDIO_BASE_ADDR;
    localparam [31:0] MDIO_END_ADDR       = `SOC_MDIO_END_ADDR;
    localparam [31:0] BOARD_BASE_ADDR     = `SOC_BOARD_BASE_ADDR;
    localparam [31:0] BOARD_END_ADDR      = `SOC_BOARD_END_ADDR;
    localparam [31:0] TSE_BASE_ADDR       = `SOC_TSE_BASE_ADDR;
    localparam [31:0] TSE_END_ADDR        = `SOC_TSE_END_ADDR;

    wire ram_sel;
    wire uart_sel;
    wire timer_sel;
    wire board_sel;
    wire mdio_sel;
    wire tse_sel;
    wire mapped_sel;
    wire dma_sel = addr >= `DMA_BASE && addr < `DMA_END;
    assign dma_mem_write = mem_write && dma_sel;
    assign dma_mem_read = mem_read && dma_sel;

    assign ram_sel = (addr >= DATA_RAM_START_ADDR) && (addr < DATA_RAM_END_ADDR);
    assign uart_sel = (addr == UART_TX_DATA_ADDR) ||
                      (addr == UART_STATUS_ADDR) ||
                      (addr == UART_CTRL_ADDR) ||
                      (addr == UART_TX_LEVEL_ADDR);
    assign timer_sel = (addr == TIMER_COUNTER_ADDR) ||
                       (addr == TIMER_COMPARE_ADDR) ||
                       (addr == TIMER_STATUS_ADDR);
    assign board_sel = (addr >= BOARD_BASE_ADDR) && (addr < BOARD_END_ADDR);
    assign mdio_sel = (addr >= MDIO_BASE_ADDR) && (addr < MDIO_END_ADDR);
    assign tse_sel = (addr >= TSE_BASE_ADDR) && (addr < TSE_END_ADDR);
    assign mapped_sel = ram_sel || uart_sel || timer_sel ||
                        board_sel || mdio_sel || tse_sel || dma_sel;

    // Requests are combinational one-cycle qualifications of the CPU MEM-stage
    // request. Defaults make the no-request/unmapped behavior explicit.
    always_comb begin
        ram_mem_write = 1'b0;
        ram_mem_read = 1'b0;
        uart_mem_write = 1'b0;
        uart_mem_read = 1'b0;
        timer_mem_write = 1'b0;
        timer_mem_read = 1'b0;
        board_mem_write = 1'b0;
        board_mem_read = 1'b0;
        mdio_mem_write = 1'b0;
        mdio_mem_read = 1'b0;
        tse_mem_write = 1'b0;
        tse_mem_read = 1'b0;

        if (mem_write) begin
            ram_mem_write = ram_sel;
            uart_mem_write = uart_sel;
            timer_mem_write = timer_sel;
            board_mem_write = board_sel;
            mdio_mem_write = mdio_sel;
            tse_mem_write = tse_sel;
        end
        if (mem_read) begin
            ram_mem_read = ram_sel;
            uart_mem_read = uart_sel;
            timer_mem_read = timer_sel;
            board_mem_read = board_sel;
            mdio_mem_read = mdio_sel;
            tse_mem_read = tse_sel;
        end
    end

    // Address regions are non-overlapping; the priority order is nevertheless
    // explicit so an accidental future overlap has deterministic readback.
    always_comb begin
        dout = 32'b0;
        if (ram_sel) begin
            dout = ram_dout;
        end else if (uart_sel) begin
            dout = uart_dout;
        end else if (timer_sel) begin
            dout = timer_dout;
        end else if (board_sel) begin
            dout = board_dout;
        end else if (mdio_sel) begin
            dout = mdio_dout;
        end else if (tse_sel) begin
            dout = tse_dout;
        end else if (dma_sel) begin
            dout = dma_dout;
        end
    end

`ifndef BOARD_DE2115
`ifndef SYNTHESIS
    always @(posedge clk or negedge rst_n) begin
        if (rst_n && mem_write && !mapped_sel) begin
            $display("WARNING: write to unmapped address 0x%08h ignored", addr);
        end
    end
`endif
`endif

endmodule
