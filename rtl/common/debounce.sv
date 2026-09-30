module debounce #(
    parameter integer WIDTH = 1,
    parameter integer STABLE_CYCLES = 125000,
    parameter [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b1}}
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [WIDTH-1:0] noisy_in,
    output wire [WIDTH-1:0] clean_out
);

    localparam integer COUNT_LIMIT = (STABLE_CYCLES < 1) ? 1 : STABLE_CYCLES;
    localparam integer COUNT_WIDTH = (COUNT_LIMIT <= 1) ? 1 : $clog2(COUNT_LIMIT);

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : g_debounce_bit
            reg candidate;
            reg clean_bit;
            reg [COUNT_WIDTH-1:0] stable_count;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    candidate <= RESET_VALUE[i];
                    clean_bit <= RESET_VALUE[i];
                    stable_count <= {COUNT_WIDTH{1'b0}};
                end else if (noisy_in[i] != candidate) begin
                    candidate <= noisy_in[i];
                    stable_count <= {COUNT_WIDTH{1'b0}};
                end else if (stable_count == COUNT_LIMIT - 1) begin
                    clean_bit <= candidate;
                end else begin
                    stable_count <= stable_count + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                end
            end

            assign clean_out[i] = clean_bit;
        end
    endgenerate

endmodule
