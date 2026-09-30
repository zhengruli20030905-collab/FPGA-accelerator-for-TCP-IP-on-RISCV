`timescale 1ns/1ps

// Simulation-only Avalon-ST/TSE-style frame source. Frames begin at the
// Ethernet destination MAC and exclude preamble, SFD, and FCS. Byte lane 0
// (data[7:0]) is always the earliest byte. A word advances only after a
// valid && ready handshake; all outputs remain stable during backpressure.
module tse_sim_frame_source #(
    parameter integer MAX_FRAME_BYTES = 2048
)(
    input clk,
    input rst_n,
    output reg [31:0] data,
    output reg [1:0] empty,
    output reg valid,
    output reg startofpacket,
    output reg endofpacket,
    input ready
);

    reg [7:0] frame_bytes [0:MAX_FRAME_BYTES-1];
    reg random_valid_gaps;
    reg [31:0] random_state;
    integer i;

    function [31:0] next_random;
        input [31:0] state;
        begin
            // xorshift32: small, deterministic, and portable to the legacy
            // ModelSim version used by this project.
            next_random = state ^ (state << 13);
            next_random = next_random ^ (next_random >> 17);
            next_random = next_random ^ (next_random << 5);
            if (next_random == 32'd0)
                next_random = 32'h1;
        end
    endfunction

    initial begin
        data = 32'd0;
        empty = 2'd0;
        valid = 1'b0;
        startofpacket = 1'b0;
        endofpacket = 1'b0;
        random_valid_gaps = 1'b0;
        random_state = 32'h1;
        for (i = 0; i < MAX_FRAME_BYTES; i = i + 1)
            frame_bytes[i] = 8'd0;
    end

    task configure_random_gaps;
        input integer enable;
        input [31:0] seed;
        begin
            random_valid_gaps = (enable != 0);
            random_state = (seed == 32'd0) ? 32'h1 : seed;
        end
    endtask

    task send_frame;
        input integer frame_len;
        integer offset;
        integer remaining;
        integer gap_cycles;
        reg [31:0] next_word;
        begin
            if ((frame_len <= 0) || (frame_len > MAX_FRAME_BYTES)) begin
                $fatal(1, "RX source length %0d is outside 1..%0d",
                       frame_len, MAX_FRAME_BYTES);
            end

            offset = 0;
            while (offset < frame_len) begin
                if (random_valid_gaps) begin
                    random_state = next_random(random_state);
                    gap_cycles = random_state[1:0];
                    repeat (gap_cycles)
                        @(posedge clk);
                end
                remaining = frame_len - offset;
                next_word = 32'd0;
                next_word[7:0] = frame_bytes[offset];
                if (remaining > 1)
                    next_word[15:8] = frame_bytes[offset + 1];
                if (remaining > 2)
                    next_word[23:16] = frame_bytes[offset + 2];
                if (remaining > 3)
                    next_word[31:24] = frame_bytes[offset + 3];

                @(negedge clk);
                data = next_word;
                valid = 1'b1;
                startofpacket = (offset == 0);
                endofpacket = (remaining <= 4);
                if (remaining >= 4)
                    empty = 2'd0;
                else
                    empty = 4 - remaining;

                @(posedge clk);
                while (!ready)
                    @(posedge clk);

                if (remaining >= 4)
                    offset = offset + 4;
                else
                    offset = frame_len;

                // Random gaps model a source that temporarily has no valid
                // word. Deassert immediately after the completed handshake;
                // otherwise the just-accepted word would be transferred again
                // while the task waits for its next randomized presentation.
                if (random_valid_gaps && (offset < frame_len)) begin
                    @(negedge clk);
                    data = 32'd0;
                    empty = 2'd0;
                    valid = 1'b0;
                    startofpacket = 1'b0;
                    endofpacket = 1'b0;
                end
            end

            @(negedge clk);
            data = 32'd0;
            empty = 2'd0;
            valid = 1'b0;
            startofpacket = 1'b0;
            endofpacket = 1'b0;
        end
    endtask

endmodule
