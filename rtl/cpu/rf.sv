module RF(
    input         clk,
    input         rst_n,
    input         RegWrite,
    input  [4:0]  ra1,
    input  [4:0]  ra2,
    input  [4:0]  hold_ra1,
    input  [4:0]  hold_ra2,
    input  [4:0]  wa,
    input  [31:0] wd,
    output [31:0] rd1,
    output [31:0] rd2,
    output [31:0] hold_rd1,
    output [31:0] hold_rd2
);
    reg [31:0] regf [31:0];
    initial begin
        for(integer i = 0; i < 32; i = i + 1)
            regf[i] = 0;
    end
    // Asynchronous Read Operations
    assign rd1 = (ra1 == 5'b0) ? 32'b0 : regf[ra1];
    assign rd2 = (ra2 == 5'b0) ? 32'b0 : regf[ra2];
    assign hold_rd1 = (hold_ra1 == 5'b0) ? 32'b0 : regf[hold_ra1];
    assign hold_rd2 = (hold_ra2 == 5'b0) ? 32'b0 : regf[hold_ra2];

    // Write Operation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (integer i = 0; i < 32; i = i + 1)
                regf[i] <= 32'b0;
        end else if (RegWrite && (wa != 0)) begin
            regf[wa] <= wd;
        end
    end

endmodule
