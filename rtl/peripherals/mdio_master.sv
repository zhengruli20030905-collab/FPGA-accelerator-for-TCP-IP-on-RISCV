// Clause 22 MDIO master for first board bring-up.
//
// MDIO is treated as open-drain at the top level:
//   assign ENET0_MDIO = mdio_drive_low ? 1'b0 : 1'bz;
//
// This master never drives a high level.  A logical 1 is sent by releasing the
// line and relying on the external pull-up/PHY side.
module mdio_master #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer MDC_HZ = 1_000_000
) (
    input clk,
    input rst_n,
    input start,
    input write_en,
    input [4:0] phy_addr,
    input [4:0] reg_addr,
    input [15:0] wdata,
    input mdio_in,
    output logic [15:0] rdata,
    output logic busy,
    output logic done,
    output logic timeout,
    output logic mdc,
    output mdio_drive_low
);

    localparam integer HALF_DIV_RAW =
        (CLK_HZ + (MDC_HZ * 2) - 1) / (MDC_HZ * 2);
    localparam integer HALF_DIV = (HALF_DIV_RAW < 1) ? 1 : HALF_DIV_RAW;

    reg [31:0] div_count;
    reg [5:0] bit_index;
    reg op_write;
    reg [4:0] phy_latched;
    reg [4:0] reg_latched;
    reg [15:0] wdata_latched;
    reg [15:0] read_shift;
    reg drive_zero;

    function automatic bit bit_value_for_index;
        input [5:0] index;
        begin
            if (index < 6'd32) begin
                bit_value_for_index = 1'b1;                // preamble
            end else if (index == 6'd32) begin
                bit_value_for_index = 1'b0;                // start 0
            end else if (index == 6'd33) begin
                bit_value_for_index = 1'b1;                // start 1
            end else if (index == 6'd34) begin
                bit_value_for_index = op_write ? 1'b0 : 1'b1;
            end else if (index == 6'd35) begin
                bit_value_for_index = op_write ? 1'b1 : 1'b0;
            end else if (index < 6'd41) begin
                bit_value_for_index = phy_latched[6'd40 - index];
            end else if (index < 6'd46) begin
                bit_value_for_index = reg_latched[6'd45 - index];
            end else if (index == 6'd46) begin
                bit_value_for_index = 1'b1;                // turnaround first bit
            end else if (index == 6'd47) begin
                bit_value_for_index = op_write ? 1'b0 : 1'b1;
            end else begin
                bit_value_for_index = wdata_latched[6'd63 - index];
            end
        end
    endfunction

    always @(*) begin
        if (!busy) begin
            drive_zero = 1'b0;
        end else if (!op_write && (bit_index >= 6'd46)) begin
            drive_zero = 1'b0;
        end else begin
            drive_zero = (bit_value_for_index(bit_index) == 1'b0);
        end
    end

    assign mdio_drive_low = drive_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata <= 16'b0;
            busy <= 1'b0;
            done <= 1'b0;
            timeout <= 1'b0;
            mdc <= 1'b0;
            div_count <= 32'b0;
            bit_index <= 6'b0;
            op_write <= 1'b0;
            phy_latched <= 5'b0;
            reg_latched <= 5'b0;
            wdata_latched <= 16'b0;
            read_shift <= 16'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                mdc <= 1'b0;
                div_count <= 32'b0;
                bit_index <= 6'b0;

                if (start) begin
                    busy <= 1'b1;
                    timeout <= 1'b0;
                    op_write <= write_en;
                    phy_latched <= phy_addr;
                    reg_latched <= reg_addr;
                    wdata_latched <= wdata;
                    read_shift <= 16'b0;
                end
            end else begin
                if (div_count == (HALF_DIV - 1)) begin
                    div_count <= 32'b0;

                    if (!mdc) begin
                        mdc <= 1'b1;

                        if (!op_write && (bit_index == 6'd47) && (mdio_in != 1'b0)) begin
                            timeout <= 1'b1;
                        end

                        if (!op_write && (bit_index >= 6'd48)) begin
                            read_shift <= {read_shift[14:0], mdio_in};
                        end
                    end else begin
                        mdc <= 1'b0;

                        if (bit_index == 6'd63) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            rdata <= read_shift;
                        end else begin
                            bit_index <= bit_index + 6'd1;
                        end
                    end
                end else begin
                    div_count <= div_count + 32'd1;
                end
            end
        end
    end

endmodule
