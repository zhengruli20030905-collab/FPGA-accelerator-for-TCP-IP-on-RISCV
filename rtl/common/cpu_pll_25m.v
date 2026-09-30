// V40 formal PLL: 50 MHz board clock -> 25 MHz CPU/MMIO clock.
module cpu_pll_25m (
    input  wire inclk0,
    input  wire pll_reset,
    output wire clk_out,
    output wire locked
);

    wire [1:0] inclk_bus;
    wire [5:0] pll_clk;

    assign inclk_bus = {1'b0, inclk0};
    assign clk_out = pll_clk[0];

    altpll #(
        .intended_device_family("Cyclone IV E"),
        .operation_mode("NORMAL"),
        .pll_type("AUTO"),
        .compensate_clock("CLK0"),
        .inclk0_input_frequency(20000),
        .clk0_multiply_by(1),
        .clk0_divide_by(2),
        .clk0_duty_cycle(50),
        .clk0_phase_shift("0"),
        .port_inclk0("PORT_USED"),
        .port_inclk1("PORT_UNUSED"),
        .port_clk0("PORT_USED"),
        .port_clk1("PORT_UNUSED"),
        .port_clk2("PORT_UNUSED"),
        .port_clk3("PORT_UNUSED"),
        .port_clk4("PORT_UNUSED"),
        .port_clk5("PORT_UNUSED"),
        .port_areset("PORT_USED"),
        .port_locked("PORT_USED"),
        .port_clkena0("PORT_UNUSED"),
        .port_clkena1("PORT_UNUSED"),
        .port_clkena2("PORT_UNUSED"),
        .port_clkena3("PORT_UNUSED"),
        .port_clkena4("PORT_UNUSED"),
        .port_clkena5("PORT_UNUSED"),
        .port_pfdena("PORT_UNUSED"),
        .port_pllena("PORT_UNUSED"),
        .lpm_type("altpll"),
        .lpm_hint("CBX_MODULE_PREFIX=cpu_pll_25m")
    ) u_altpll (
        .inclk(inclk_bus),
        .areset(pll_reset),
        .clk(pll_clk),
        .locked(locked),
        .clkena(6'b111111),
        .pfdena(1'b1),
        .pllena(1'b1)
    );

endmodule
