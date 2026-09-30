`timescale 1ns/1ps

module tb_v40_peripheral_timing;
    localparam integer CLK_HZ = 25_000_000;
    localparam integer CLK_PERIOD_NS = 40;
    localparam integer UART_CLKS_PER_BIT = 217;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    logic timer_write, timer_read;
    logic [31:0] timer_addr, timer_din;
    wire [31:0] timer_dout;
    timer_mmio u_timer (
        .clk(clk), .rst_n(rst_n), .mem_write(timer_write), .mem_read(timer_read),
        .addr(timer_addr), .din(timer_din), .dout(timer_dout)
    );

    logic uart_valid;
    logic [7:0] uart_data;
    wire uart_busy, uart_ready, uart_txd;
    uart_tx_hw #(.CLK_HZ(CLK_HZ), .BAUD(115_200)) u_uart (
        .clk(clk), .rst_n(rst_n), .tx_valid(uart_valid), .tx_data(uart_data),
        .tx_busy(uart_busy), .tx_ready(uart_ready), .uart_txd(uart_txd)
    );

    logic uart_mmio_write, uart_mmio_read;
    logic [31:0] uart_mmio_addr, uart_mmio_din;
    wire [31:0] uart_mmio_dout;
    wire uart_mmio_txd;
    integer uart_mmio_decoded_count;
    uart_mmio #(.CLK_HZ(CLK_HZ), .BAUD(115_200), .FIFO_DEPTH(4)) u_uart_mmio (
        .clk(clk), .rst_n(rst_n), .mem_write(uart_mmio_write),
        .mem_read(uart_mmio_read), .addr(uart_mmio_addr),
        .din(uart_mmio_din), .dout(uart_mmio_dout), .uart_txd(uart_mmio_txd)
    );

    logic noisy_key;
    wire clean_key;
    debounce #(.WIDTH(1), .STABLE_CYCLES(125_000), .RESET_VALUE(1'b1)) u_debounce (
        .clk(clk), .rst_n(rst_n), .noisy_in(noisy_key), .clean_out(clean_key)
    );

    logic mdio_mem_write, mdio_mem_read;
    logic [31:0] mdio_addr, mdio_din;
    wire [31:0] mdio_dout;
    wire phy_reset_n, unused_mdc, unused_mdio_drive;
    phy_mdio_mmio #(
        .CLK_HZ(CLK_HZ), .MDC_HZ(1_000_000),
        .HW_RESET_CYCLES(250_000), .SIM_PHY_MODEL(1)
    ) u_phy_reset (
        .clk(clk), .rst_n(rst_n), .mem_write(mdio_mem_write), .mem_read(mdio_mem_read),
        .addr(mdio_addr), .din(mdio_din), .mdio_in(1'b1), .dout(mdio_dout),
        .phy_reset_n(phy_reset_n), .mdc(unused_mdc), .mdio_drive_low(unused_mdio_drive)
    );

    logic master_start, master_write;
    wire [15:0] master_rdata;
    wire master_busy, master_done, master_timeout, master_mdc, master_drive_low;
    integer mdc_rises;
    always @(posedge master_mdc) mdc_rises = mdc_rises + 1;
    mdio_master #(.CLK_HZ(CLK_HZ), .MDC_HZ(1_000_000)) u_mdio (
        .clk(clk), .rst_n(rst_n), .start(master_start), .write_en(master_write),
        .phy_addr(5'h10), .reg_addr(5'd4), .wdata(16'h0de1), .mdio_in(1'b1),
        .rdata(master_rdata), .busy(master_busy), .done(master_done),
        .timeout(master_timeout), .mdc(master_mdc), .mdio_drive_low(master_drive_low)
    );

    time reset_release_time;
    time debounce_change_time;
    time debounce_release_time;
    time phy_release_time;
    always @(negedge clean_key) debounce_release_time = $time;
    always @(posedge phy_reset_n) phy_release_time = $time;

    function automatic logic uart_frame_bit(input [7:0] value, input integer index);
        if (index == 0) uart_frame_bit = 1'b0;
        else if (index == 9) uart_frame_bit = 1'b1;
        else uart_frame_bit = value[index-1];
    endfunction

    task automatic check_uart_character(input [7:0] value);
        integer bit_index;
        integer cycle_index;
        begin
            wait (uart_ready === 1'b1);
            @(negedge clk);
            uart_data = value;
            uart_valid = 1'b1;
            @(posedge clk);
            #1 uart_valid = 1'b0;
            for (bit_index = 0; bit_index < 10; bit_index = bit_index + 1) begin
                for (cycle_index = 0; cycle_index < UART_CLKS_PER_BIT; cycle_index = cycle_index + 1) begin
                    #1;
                    if (uart_txd !== uart_frame_bit(value, bit_index))
                        $fatal(1, "UART bit mismatch char=%02x bit=%0d cycle=%0d", value, bit_index, cycle_index);
                    @(posedge clk);
                end
            end
            wait (uart_ready === 1'b1);
        end
    endtask

    task automatic check_uart_mmio_character(input [7:0] expected);
        integer bit_index;
        reg [7:0] observed;
        begin
            // Find the start bit, then sample each data bit at its centre.
            @(negedge uart_mmio_txd);
            #(UART_CLKS_PER_BIT * CLK_PERIOD_NS +
              (UART_CLKS_PER_BIT * CLK_PERIOD_NS) / 2);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                observed[bit_index] = uart_mmio_txd;
                #(UART_CLKS_PER_BIT * CLK_PERIOD_NS);
            end
            if (uart_mmio_txd !== 1'b1)
                $fatal(1, "UART MMIO stop bit mismatch expected=%02x", expected);
            if (observed !== expected)
                $fatal(1, "UART MMIO decoded=%02x expected=%02x", observed, expected);
            uart_mmio_decoded_count = uart_mmio_decoded_count + 1;
        end
    endtask

    task automatic uart_mmio_write_once(input [31:0] write_addr,
                                        input [31:0] write_data);
        begin
            @(negedge clk);
            uart_mmio_addr = write_addr;
            uart_mmio_din = write_data;
            uart_mmio_write = 1'b1;
            @(negedge clk);
            uart_mmio_write = 1'b0;
        end
    endtask

    time mdc_first_rise;
    time mdc_second_rise;
    integer timer_start_count;

    initial begin
        timer_write = 0; timer_read = 0; timer_addr = 0; timer_din = 0;
        uart_valid = 0; uart_data = 0;
        uart_mmio_write = 0; uart_mmio_read = 0;
        uart_mmio_addr = 0; uart_mmio_din = 0;
        uart_mmio_decoded_count = 0;
        noisy_key = 1;
        mdio_mem_write = 0; mdio_mem_read = 0; mdio_addr = 0; mdio_din = 0;
        master_start = 0; master_write = 1;
        mdc_rises = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        reset_release_time = $time;
        debounce_change_time = $time;
        noisy_key = 1'b0;

        timer_start_count = u_timer.timer_counter;

        fork
            begin
                check_uart_character(8'ha5);
                check_uart_character(8'h3c);
                $display("PASS UART 115200 divider=%0d actual_baud=%0d", UART_CLKS_PER_BIT,
                         CLK_HZ / UART_CLKS_PER_BIT);
            end
            begin
                @(negedge clk); master_start = 1'b1;
                @(negedge clk); master_start = 1'b0;
                @(posedge master_mdc); mdc_first_rise = $time;
                @(posedge master_mdc); mdc_second_rise = $time;
                if ((mdc_second_rise - mdc_first_rise) != 1040)
                    $fatal(1, "MDC period mismatch: %0t ns", mdc_second_rise-mdc_first_rise);
                wait (master_done === 1'b1);
                #1;
                if (master_timeout || mdc_rises != 64)
                    $fatal(1, "MDIO frame mismatch timeout=%0b rises=%0d", master_timeout, mdc_rises);
                $display("PASS MDIO Clause22 rises=%0d period_ns=%0d actual_hz=%0d",
                         mdc_rises, mdc_second_rise-mdc_first_rise, 1_000_000_000/(mdc_second_rise-mdc_first_rise));
            end
            begin
                fork
                    begin
                        // Decode the real serial pin.  Merely counting an
                        // internal launch request would miss a same-edge
                        // producer/consumer ownership bug.
                        check_uart_mmio_character(8'h41);
                        check_uart_mmio_character(8'h42);
                        check_uart_mmio_character(8'h43);
                        check_uart_mmio_character(8'h44);
                        check_uart_mmio_character(8'h45);
                    end
                    begin
                        // The first byte enters the serializer while the next
                        // four fill the queue.  A sixth write must overflow and
                        // must never appear at the UART pin.
                        uart_mmio_write_once(32'h1000_0000, 32'h41);
                        uart_mmio_write_once(32'h1000_0000, 32'h42);
                        uart_mmio_write_once(32'h1000_0000, 32'h43);
                        uart_mmio_write_once(32'h1000_0000, 32'h44);
                        uart_mmio_write_once(32'h1000_0000, 32'h45);
                        uart_mmio_write_once(32'h1000_0000, 32'h46);
                        #1;
                        if (!u_uart_mmio.tx_overflow || !u_uart_mmio.fifo_full)
                            $fatal(1, "UART MMIO FIFO did not report full/overflow");
                    end
                join
                wait (u_uart_mmio.fifo_empty && u_uart_mmio.serializer_ready);
                repeat (4) @(posedge clk);
                if (uart_mmio_decoded_count != 5)
                    $fatal(1, "UART MMIO serial decode count=%0d expected=5",
                           uart_mmio_decoded_count);
                uart_mmio_write_once(32'h1000_0008, 32'h1);
                #1;
                if (u_uart_mmio.tx_overflow)
                    $fatal(1, "UART MMIO overflow clear failed");
                $display("PASS UART_MMIO valid/ready serial sequence ABCDE count=%0d",
                         uart_mmio_decoded_count);
            end
        join

        while (($time - reset_release_time) < 10_000_200) @(posedge clk);
        #1;
        if ((u_timer.timer_counter - timer_start_count) < 250_000)
            $fatal(1, "Timer did not count at 25 MHz");
        if (debounce_release_time == 0 ||
            (debounce_release_time - debounce_change_time) < 5_000_000 ||
            (debounce_release_time - debounce_change_time) > 5_000_080)
            $fatal(1, "Debounce interval mismatch: %0d ns", debounce_release_time-debounce_change_time);
        if (phy_release_time == 0 ||
            (phy_release_time - reset_release_time) < 9_999_960 ||
            (phy_release_time - reset_release_time) > 10_000_040)
            $fatal(1, "PHY reset interval mismatch: %0d ns", phy_release_time-reset_release_time);

        $display("PASS TIMER cycles_per_ms=25000");
        $display("PASS DEBOUNCE interval_ns=%0d", debounce_release_time-debounce_change_time);
        $display("PASS PHY_RESET interval_ns=%0d", phy_release_time-reset_release_time);
        $display("V40 PERIPHERAL TIMING SIMULATION PASSED");
        $finish;
    end

    initial begin
        #12_000_000;
        $fatal(1, "V40 peripheral timing watchdog");
    end
endmodule
