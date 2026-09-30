`timescale 1ns/1ps
`include "dma_addr_map.svh"

module tb_v40_sgdma_gather_scatter;
    localparam integer TX_BASE = 32'h00001000;
    localparam integer RX_BASE = 32'h00001400;
    localparam integer RING_SIZE = 8;

    logic clk = 0;
    logic rst_n = 0;
    always #20 clk = ~clk;

    logic mem_write, mem_read;
    logic [31:0] addr, din, dout;
    logic tx_available, rx_available;
    logic [15:0] rx_length;
    logic finalize_ready;
    logic descriptor_conflict, payload_conflict, packet_conflict;
    logic job_valid, job_ready, job_direction, job_abort;
    logic [31:0] job_dmem_addr, job_packet_offset, job_length;
    logic job_busy, job_done, job_error;
    logic [31:0] job_error_code, job_bytes_done;
    logic desc_req, desc_write, desc_ready, desc_rvalid;
    logic [31:0] desc_addr, desc_wdata, desc_rdata;
    logic [3:0] desc_byteena;
    logic enabled, overall_busy;
    logic descriptor_lock_valid, payload_lock_valid, packet_lock;
    logic [31:0] descriptor_lock_addr, descriptor_lock_length;
    logic [31:0] payload_lock_addr, payload_lock_length;
    logic packet_direction;
    logic [31:0] packet_length;
    logic packet_commit, packet_cancel, packet_rx_pop, tx_autorun;
    logic csum_start, csum_finish, csum_wait;
    logic [31:0] csum_control;

    logic [31:0] dmem [0:32767];
    logic job_pending;
    integer fail_job_number;
    integer lane;
    integer checks = 0;
    integer job_count = 0;
    integer tx_commits = 0;
    integer rx_pops = 0;
    integer tx_cancels = 0;
    integer rx_drops = 0;
    logic job_dir_log [0:127];
    logic [31:0] job_addr_log [0:127];
    logic [31:0] job_offset_log [0:127];
    logic [31:0] job_length_log [0:127];
    logic [31:0] commit_length_log [0:31];
    logic [31:0] pop_length_log [0:31];

    sgdma_descriptor_engine #(
        .TIMEOUT_CYCLES(64), .DMEM_BYTES(131072), .MAX_RING_SIZE(64)
    ) dut (
        .clk(clk), .rst_n(rst_n), .mem_write(mem_write), .mem_read(mem_read),
        .addr(addr), .din(din), .dout(dout),
        .csum_start(csum_start), .csum_finish(csum_finish),
        .csum_wait(csum_wait), .csum_control(csum_control),
        .csum_complete(1'b0),.csum_error(1'b0),.csum_error_code(8'd0),.csum_flags(16'd0),
        .tx_available(tx_available), .rx_available(rx_available),
        .rx_length(rx_length), .finalize_ready(finalize_ready),
        .descriptor_conflict(descriptor_conflict),
        .payload_conflict(payload_conflict), .packet_conflict(packet_conflict),
        .job_valid(job_valid), .job_ready(job_ready),
        .job_direction(job_direction), .job_dmem_addr(job_dmem_addr),
        .job_packet_offset(job_packet_offset), .job_length(job_length),
        .job_abort(job_abort), .job_busy(job_busy), .job_done(job_done),
        .job_error(job_error), .job_error_code(job_error_code),
        .job_bytes_done(job_bytes_done), .desc_req(desc_req),
        .desc_write(desc_write), .desc_addr(desc_addr),
        .desc_wdata(desc_wdata), .desc_byteena(desc_byteena),
        .desc_ready(desc_ready), .desc_rvalid(desc_rvalid),
        .desc_rdata(desc_rdata), .enabled(enabled),
        .overall_busy(overall_busy),
        .descriptor_lock_valid(descriptor_lock_valid),
        .descriptor_lock_addr(descriptor_lock_addr),
        .descriptor_lock_length(descriptor_lock_length),
        .payload_lock_valid(payload_lock_valid),
        .payload_lock_addr(payload_lock_addr),
        .payload_lock_length(payload_lock_length), .packet_lock(packet_lock),
        .packet_direction(packet_direction), .packet_length(packet_length),
        .packet_commit(packet_commit), .packet_cancel(packet_cancel),
        .packet_rx_pop(packet_rx_pop), .tx_autorun(tx_autorun)
    );

    task automatic check(input logic condition, input string message);
        begin
            checks++;
            if (!condition) $fatal(1, "%s", message);
        end
    endtask

    task automatic mmio_write(input [31:0] a, input [31:0] v);
        begin
            @(negedge clk); addr = a; din = v; mem_write = 1;
            @(posedge clk); @(negedge clk); mem_write = 0; addr = 0; din = 0;
        end
    endtask

    task automatic mmio_read(input [31:0] a, output [31:0] v);
        begin
            @(negedge clk); addr = a; mem_read = 1; #1; v = dout;
            @(negedge clk); mem_read = 0; addr = 0;
        end
    endtask

    task automatic write_segment(
        input logic direction,
        input integer index,
        input integer id,
        input integer length,
        input logic own,
        input logic first,
        input logic last
    );
        integer word_base;
        begin
            word_base = (((direction ? TX_BASE : RX_BASE) >> 2) + index * 4);
            dmem[word_base] = 32'h00004001 + id * 32'h00000100;
            dmem[word_base + 1] = length;
            dmem[word_base + 2] = {28'd0, last, first, direction, own};
            dmem[word_base + 3] = 0;
        end
    endtask

    task automatic configure;
        begin
            mmio_write(`SG_TX_DESC_BASE, TX_BASE);
            mmio_write(`SG_TX_RING_SIZE, RING_SIZE);
            mmio_write(`SG_RX_DESC_BASE, RX_BASE);
            mmio_write(`SG_RX_RING_SIZE, RING_SIZE);
            mmio_write(`SG_CTRL, 8);
            mmio_write(`SG_CTRL, 1);
            check(enabled, "V40 engine did not enable");
        end
    endtask

    task automatic wait_heads(input integer tx_value, input integer rx_value);
        integer guard;
        begin
            guard = 0;
            while ((dut.tx_head != tx_value) || (dut.rx_head != rx_value)) begin
                @(posedge clk);
                guard++;
                if (guard > 30000)
                    $fatal(1, "HEAD timeout TX=%0d/%0d RX=%0d/%0d state=%0d",
                           dut.tx_head, tx_value, dut.rx_head, rx_value, dut.state);
            end
            @(posedge clk);
        end
    endtask

    task automatic reset_dut;
        integer i;
        begin
            mem_write = 0; mem_read = 0; addr = 0; din = 0;
            tx_available = 1; rx_available = 1; rx_length = 16'd60;
            finalize_ready = 1; descriptor_conflict = 0;
            payload_conflict = 0; packet_conflict = 0;
            job_ready = 1; job_busy = 0; job_done = 0; job_error = 0;
            job_error_code = 0; job_bytes_done = 0; job_pending = 0;
            fail_job_number = -1;
            desc_ready = 1; desc_rvalid = 0; desc_rdata = 0;
            job_count = 0; tx_commits = 0; rx_pops = 0;
            tx_cancels = 0; rx_drops = 0;
            for (i = 0; i < 32768; i++) dmem[i] = 0;
            rst_n = 0; repeat (4) @(posedge clk);
            rst_n = 1; repeat (3) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        desc_rvalid <= 0;
        if (desc_req && desc_ready) begin
            if (desc_write) begin
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (desc_byteena[lane])
                        dmem[desc_addr[16:2]][lane*8 +: 8] <=
                            desc_wdata[lane*8 +: 8];
            end else begin
                desc_rdata <= dmem[desc_addr[16:2]];
                desc_rvalid <= 1;
            end
        end

        job_done <= 0;
        job_error <= 0;
        if (job_pending) begin
            job_bytes_done <= job_length;
            if (job_count == fail_job_number) begin
                job_error <= 1;
                job_error_code <= 3;
            end else begin
                job_done <= 1;
                job_error_code <= 0;
            end
            job_pending <= 0;
        end
        if (job_valid && job_ready) begin
            job_dir_log[job_count] <= job_direction;
            job_addr_log[job_count] <= job_dmem_addr;
            job_offset_log[job_count] <= job_packet_offset;
            job_length_log[job_count] <= job_length;
            job_count <= job_count + 1;
            job_pending <= 1;
        end
        if (packet_commit) begin
            commit_length_log[tx_commits] <= packet_length;
            tx_commits <= tx_commits + 1;
        end
        if (packet_rx_pop) begin
            pop_length_log[rx_pops] <= packet_length;
            rx_pops <= rx_pops + 1;
        end
        if (packet_cancel) begin
            if (packet_direction) tx_cancels <= tx_cancels + 1;
            else rx_drops <= rx_drops + 1;
        end
    end

    integer i;
    integer base_jobs;
    reg [31:0] value;
    initial begin
        // Three unaligned TX segments gather into one 60-byte packet.
        reset_dut();
        write_segment(1, 0, 0, 5, 1, 1, 0);
        write_segment(1, 1, 1, 7, 1, 0, 0);
        write_segment(1, 2, 2, 48, 1, 0, 1);
        configure();
        mmio_write(`SG_TX_TAIL, 3);
        wait_heads(3, 0);
        check(job_count == 3, "TX gather did not execute three segments");
        check(job_offset_log[0] == 0 && job_length_log[0] == 5,
              "TX segment 0 offset/length wrong");
        check(job_offset_log[1] == 5 && job_length_log[1] == 7,
              "TX segment 1 offset/length wrong");
        check(job_offset_log[2] == 12 && job_length_log[2] == 48,
              "TX segment 2 offset/length wrong");
        check(tx_commits == 1 && commit_length_log[0] == 60,
              "TX chain did not commit exactly one 60-byte frame");
        check(rx_pops == 0 && tx_cancels == 0, "TX success finalized wrongly");
        for (i = 0; i < 3; i++) begin
            check(!dmem[(TX_BASE>>2)+i*4+2][`SG_DESC_OWN_BIT],
                  "TX chain OWN remained set");
            check(dmem[(TX_BASE>>2)+i*4+3][`SG_DESC_DONE_BIT],
                  "TX chain DONE missing");
        end
        mmio_read(`SG_TX_FRAME_COUNT, value); check(value == 1, "TX frame counter wrong");
        mmio_read(`SG_TX_SEGMENT_COUNT, value); check(value == 3, "TX segment counter wrong");
        mmio_read(`SG_MAX_TX_SEGMENTS, value); check(value == 3, "TX max segment counter wrong");

        // RX scatters 60 bytes as 17 + 19 + 24 and pops the frame once.
        reset_dut(); rx_length = 60;
        write_segment(0, 0, 8, 17, 1, 1, 0);
        write_segment(0, 1, 9, 19, 1, 0, 0);
        write_segment(0, 2, 10, 64, 1, 0, 1);
        configure();
        mmio_write(`SG_RX_TAIL, 3);
        wait_heads(0, 3);
        check(job_count == 3, "RX scatter did not execute three segments");
        check(!job_dir_log[0] && !job_dir_log[1] && !job_dir_log[2],
              "RX scatter direction wrong");
        check(job_offset_log[0] == 0 && job_length_log[0] == 17,
              "RX segment 0 offset/length wrong");
        check(job_offset_log[1] == 17 && job_length_log[1] == 19,
              "RX segment 1 offset/length wrong");
        check(job_offset_log[2] == 36 && job_length_log[2] == 24,
              "RX segment 2 offset/length wrong");
        check(rx_pops == 1 && pop_length_log[0] == 60,
              "RX chain did not pop exactly one 60-byte frame");
        check(tx_commits == 0 && rx_drops == 0, "RX success finalized wrongly");
        check(dmem[(RX_BASE>>2)+3][31:16] == 17 &&
              dmem[(RX_BASE>>2)+7][31:16] == 19 &&
              dmem[(RX_BASE>>2)+11][31:16] == 24,
              "RX actual lengths were not written per segment");
        mmio_read(`SG_RX_FRAME_COUNT, value); check(value == 1, "RX frame counter wrong");
        mmio_read(`SG_RX_SEGMENT_COUNT, value); check(value == 3, "RX segment counter wrong");

        // A short RX frame consumes no payload from unused trailing segments,
        // but all published descriptors are completed before one RX pop.
        reset_dut(); rx_length = 13;
        write_segment(0, 0, 16, 8, 1, 1, 0);
        write_segment(0, 1, 17, 8, 1, 0, 0);
        write_segment(0, 2, 18, 8, 1, 0, 1);
        configure();
        mmio_write(`SG_RX_TAIL, 3);
        wait_heads(0, 3);
        check(job_count == 2, "short RX frame issued an unused payload job");
        check(job_length_log[0] == 8 && job_length_log[1] == 5,
              "short RX frame scatter lengths wrong");
        check(dmem[(RX_BASE>>2)+11][31:16] == 0,
              "unused RX descriptor actual length was not zero");
        check(rx_pops == 1 && pop_length_log[0] == 13,
              "short RX frame did not pop exactly once");

        // Insufficient total RX capacity must drop, never expose a partial frame.
        reset_dut(); rx_length = 40;
        write_segment(0, 0, 24, 8, 1, 1, 0);
        write_segment(0, 1, 25, 8, 1, 0, 0);
        write_segment(0, 2, 26, 8, 1, 0, 1);
        configure();
        mmio_write(`SG_RX_TAIL, 3);
        wait_heads(0, 3);
        check(job_count == 3, "small RX chain payload job count wrong");
        check(rx_pops == 0 && rx_drops == 1,
              "small RX chain exposed a partial frame");
        check(dmem[(RX_BASE>>2)+11][15:8] == `SG_ERR_BUFFER_SMALL,
              "small RX chain status code wrong");
        mmio_read(`SG_RX_DROP_COUNT, value); check(value == 1, "RX drop counter wrong");

        // Advance to physical slot 7, then gather through slot7 -> slot0 -> slot1.
        reset_dut(); configure();
        for (i = 0; i < 7; i++)
            write_segment(1, i, 32+i, 4, 1, 1, 1);
        mmio_write(`SG_TX_TAIL, 7);
        wait_heads(7, 0);
        base_jobs = job_count;
        write_segment(1, 7, 40, 3, 1, 1, 0);
        write_segment(1, 0, 41, 5, 1, 0, 0);
        write_segment(1, 1, 42, 52, 1, 0, 1);
        mmio_write(`SG_TX_TAIL, 10);
        wait_heads(10, 0);
        check(job_count == base_jobs + 3, "wrapped TX chain job count wrong");
        check(job_offset_log[base_jobs] == 0 &&
              job_offset_log[base_jobs+1] == 3 &&
              job_offset_log[base_jobs+2] == 8,
              "wrapped TX chain offsets wrong");
        check(tx_commits == 8 && commit_length_log[7] == 60,
              "wrapped TX chain did not commit one frame");

        // Once a frame wins arbitration, its segments remain contiguous. The
        // other ready ring is considered only after LAST finalizes the frame.
        reset_dut(); rx_length = 32;
        write_segment(1, 0, 48, 8, 1, 1, 0);
        write_segment(1, 1, 49, 52, 1, 0, 1);
        write_segment(0, 0, 56, 12, 1, 1, 0);
        write_segment(0, 1, 57, 20, 1, 0, 1);
        configure();
        mmio_write(`SG_TX_TAIL, 2);
        mmio_write(`SG_RX_TAIL, 2);
        wait_heads(2, 2);
        check(job_count == 4, "simultaneous TX/RX chain job count wrong");
        check(job_dir_log[0] == job_dir_log[1] &&
              job_dir_log[2] == job_dir_log[3] &&
              job_dir_log[0] != job_dir_log[2],
              "arbiter interleaved two in-progress frames");
        check(tx_commits == 1 && rx_pops == 1,
              "simultaneous chains finalized incorrectly");

        // A chain without FIRST is drained through LAST with no packet commit.
        reset_dut();
        write_segment(1, 0, 64, 8, 1, 0, 0);
        write_segment(1, 1, 65, 8, 1, 0, 1);
        configure();
        mmio_write(`SG_TX_TAIL, 2);
        wait_heads(2, 0);
        check(job_count == 0 && tx_commits == 0 && tx_cancels == 0,
              "missing-FIRST chain reached payload/finalize path");
        check(dmem[(TX_BASE>>2)+3][15:8] == `SG_ERR_MISSING_FIRST,
              "missing-FIRST status code wrong");
        check(dmem[(TX_BASE>>2)+7][15:8] == `SG_ERR_CHAIN_ABORTED,
              "missing-FIRST drain status wrong");

        // Single-descriptor compatibility remains FIRST+LAST.
        reset_dut();
        write_segment(1, 0, 68, 60, 1, 1, 1);
        configure(); mmio_write(`SG_TX_TAIL, 1); wait_heads(1, 0);
        check(job_count == 1 && tx_commits == 1 && commit_length_log[0] == 60,
              "single-descriptor compatibility failed");

        // A two-descriptor RX chain is a frame, not two packets.
        reset_dut(); rx_length = 60;
        write_segment(0, 0, 69, 20, 1, 1, 0);
        write_segment(0, 1, 70, 40, 1, 0, 1);
        configure(); mmio_write(`SG_RX_TAIL, 2); wait_heads(0, 2);
        check(job_count == 2 && rx_pops == 1 && pop_length_log[0] == 60,
              "two-segment RX compatibility failed");

        // FIRST is illegal while a frame is active; the partial TX slot is
        // cancelled and the offending LAST terminates the drained chain.
        reset_dut();
        write_segment(1, 0, 71, 8, 1, 1, 0);
        write_segment(1, 1, 72, 52, 1, 1, 1);
        configure(); mmio_write(`SG_TX_TAIL, 2); wait_heads(2, 0);
        check(job_count == 1 && tx_commits == 0 && tx_cancels == 1,
              "duplicate FIRST did not cancel partial TX frame");
        check(dmem[(TX_BASE>>2)+7][15:8] == `SG_ERR_UNEXPECTED_FIRST,
              "duplicate FIRST status code wrong");

        // Publishing FIRST without a reachable LAST is rejected and paused.
        reset_dut();
        write_segment(1, 0, 73, 60, 1, 1, 0);
        configure(); mmio_write(`SG_TX_TAIL, 1); wait_heads(1, 0);
        check(job_count == 0 && tx_commits == 0,
              "missing LAST started a payload job");
        check(dmem[(TX_BASE>>2)+3][15:8] == `SG_ERR_MISSING_LAST,
              "missing LAST status code wrong");
        check(dut.state == 11, "missing LAST did not enter ERROR_PAUSED");

        // TX aggregate length is limited by the 2048-byte packet slot.
        reset_dut();
        write_segment(1, 0, 74, 1200, 1, 1, 0);
        write_segment(1, 1, 75, 900, 1, 0, 1);
        configure(); mmio_write(`SG_TX_TAIL, 2); wait_heads(2, 0);
        check(job_count == 1 && tx_commits == 0 && tx_cancels == 1,
              "oversize TX frame was published");
        check(dmem[(TX_BASE>>2)+7][15:8] == `SG_ERR_FRAME_TOO_LARGE,
              "oversize TX status code wrong");

        // OWN=0 is a descriptor error and may not launch payload DMA.
        reset_dut();
        write_segment(0, 0, 76, 64, 0, 1, 1);
        configure(); mmio_write(`SG_RX_TAIL, 1); wait_heads(0, 1);
        check(job_count == 0 && rx_pops == 0,
              "OWN=0 descriptor launched RX payload");
        check(dmem[(RX_BASE>>2)+3][15:8] == `SG_ERR_OWN,
              "OWN=0 status code wrong");

        // An intermediate payload error cancels the whole TX build and drains
        // the remaining descriptor instead of publishing a partial frame.
        reset_dut();
        write_segment(1, 0, 72, 8, 1, 1, 0);
        write_segment(1, 1, 73, 8, 1, 0, 0);
        write_segment(1, 2, 74, 44, 1, 0, 1);
        configure();
        fail_job_number = 2;
        mmio_write(`SG_TX_TAIL, 3);
        wait_heads(3, 0);
        check(tx_commits == 0 && tx_cancels == 1,
              "middle TX failure published a partial frame");
        check(dmem[(TX_BASE>>2)+11][15:8] == `SG_ERR_CHAIN_ABORTED,
              "middle TX failure did not drain LAST");
        mmio_read(`SG_TX_CANCEL_COUNT, value); check(value == 1, "TX cancel counter wrong");

        mmio_read(`SG_ID, value); check(value == `SG_ID_VALUE, "V40 SG ID wrong");
        mmio_read(`SG_CAPABILITY, value);
        check(value == `SG_CAPABILITY_VALUE, "V40 capability bits wrong");

        $display("V40 SGDMA GATHER/SCATTER PASSED checks=%0d", checks);
        $finish;
    end
endmodule
