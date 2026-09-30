`timescale 1ns/1ps
module tb_v40_dma_transfer_engine;
    logic clk = 0, rst_n = 0;
    always #20 clk = ~clk;

    logic job_valid, job_ready, job_direction, job_abort;
    logic [1:0] job_conflict;
    logic [31:0] job_dmem_addr, job_packet_offset, job_length;
    logic job_busy, job_done, job_error;
    logic [31:0] job_error_code, job_bytes_done;
    logic active_direction;
    wire csum_beat_valid,csum_direction;
    wire [31:0] csum_beat_data,csum_frame_offset;
    wire [3:0] csum_beat_keep;
    logic [31:0] active_dmem_addr, active_packet_offset, active_length;
    logic dm_req, dm_write, dm_ready, dm_rvalid;
    logic [31:0] dm_addr, dm_wdata, dm_rdata;
    logic [3:0] dm_byteena;
    logic pkt_req, pkt_write, pkt_ready, pkt_rvalid;
    logic [10:0] pkt_addr;
    logic [31:0] pkt_wdata, pkt_rdata;
    logic force_dm_stall, force_pkt_stall;
    logic [31:0] dmem [0:32767];
    logic [31:0] packet [0:511];
    integer checks = 0;

    dma_transfer_engine #(.TIMEOUT_CYCLES(16)) dut (.*);

    assign dm_ready = !force_dm_stall;
    assign pkt_ready = !force_pkt_stall;

    integer lane;
    always_ff @(posedge clk) begin
        dm_rvalid <= 0;
        pkt_rvalid <= 0;
        if (dm_req && dm_ready) begin
            if (dm_write) begin
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (dm_byteena[lane])
                        dmem[dm_addr[16:2]][lane*8 +: 8] <=
                            dm_wdata[lane*8 +: 8];
            end else begin
                dm_rdata <= dmem[dm_addr[16:2]];
                dm_rvalid <= 1;
            end
        end
        if (pkt_req && pkt_ready) begin
            if (pkt_write) begin
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (dm_byteena[lane])
                        packet[pkt_addr[10:2]][lane*8 +: 8] <=
                            pkt_wdata[lane*8 +: 8];
            end else begin
                pkt_rdata <= packet[pkt_addr[10:2]];
                pkt_rvalid <= 1;
            end
        end
    end

    task automatic check(input logic condition, input string message);
        begin
            checks++;
            if (!condition) $fatal(1, "%s", message);
        end
    endtask

    function automatic [7:0] pattern(input integer id, input integer offset);
        pattern = (id * 37 + offset * 13 + 8'h5a) & 8'hff;
    endfunction

    task automatic clear_memories;
        integer i;
        begin
            for (i = 0; i < 4096; i++) dmem[i] = 32'ha5a5_a5a5;
            for (i = 0; i < 512; i++) packet[i] = 32'ha5a5_a5a5;
        end
    endtask

    task automatic pulse_job(input logic dir, input [31:0] daddr,
                             input [31:0] poff, input [31:0] len);
        begin
            while (!job_ready) @(posedge clk);
            @(negedge clk);
            job_direction = dir;
            job_dmem_addr = daddr;
            job_packet_offset = poff;
            job_length = len;
            job_valid = 1;
            @(posedge clk);
            @(negedge clk);
            job_valid = 0;
        end
    endtask

    task automatic wait_terminal(input logic expect_error,
                                 input [31:0] expected_code);
        integer guard;
        begin
            guard = 0;
            while (!job_done && !job_error) begin
                @(posedge clk); #1;
                guard++;
                if (guard > 30000) $fatal(1, "engine terminal timeout");
            end
            check(job_error == expect_error, "unexpected terminal result");
            if (expect_error)
                check(job_error_code == expected_code,
                      "unexpected engine error code");
            @(posedge clk); #1;
        end
    endtask

    task automatic set_dmem_byte(input integer byte_address,
                                 input [7:0] value);
        dmem[byte_address >> 2][(byte_address & 3)*8 +: 8] = value;
    endtask

    task automatic set_packet_byte(input integer byte_address,
                                   input [7:0] value);
        packet[byte_address >> 2][(byte_address & 3)*8 +: 8] = value;
    endtask

    function automatic [7:0] get_dmem_byte(input integer byte_address);
        get_dmem_byte = dmem[byte_address >> 2]
                            [(byte_address & 3)*8 +: 8];
    endfunction

    function automatic [7:0] get_packet_byte(input integer byte_address);
        get_packet_byte = packet[byte_address >> 2]
                              [(byte_address & 3)*8 +: 8];
    endfunction

    task automatic run_copy(input logic dir, input integer id,
                            input integer src_offset,
                            input integer dst_offset,
                            input integer len);
        integer i;
        integer daddr;
        integer poff;
        integer dest_start;
        begin
            clear_memories();
            daddr = 32'h00002000 + (dir ? src_offset : dst_offset);
            poff = dir ? dst_offset : src_offset;
            for (i = 0; i < len; i++) begin
                if (dir)
                    set_dmem_byte(daddr + i, pattern(id, i));
                else
                    set_packet_byte(poff + i, pattern(id, i));
            end
            pulse_job(dir, daddr, poff, len);
            wait_terminal(0, 0);
            check(job_bytes_done == len, "wrong byte count");
            dest_start = dir ? poff : daddr;
            for (i = 0; i < len; i++) begin
                if (dir)
                    check(get_packet_byte(dest_start + i) == pattern(id, i),
                          "TX unaligned payload mismatch");
                else
                    check(get_dmem_byte(dest_start + i) == pattern(id, i),
                          "RX unaligned payload mismatch");
            end
            if (dest_start > 0) begin
                if (dir)
                    check(get_packet_byte(dest_start - 1) == 8'ha5,
                          "TX overwrote byte before destination");
                else
                    check(get_dmem_byte(dest_start - 1) == 8'ha5,
                          "RX overwrote byte before destination");
            end
            if (dir && (dest_start + len < 2048))
                check(get_packet_byte(dest_start + len) == 8'ha5,
                      "TX overwrote byte after destination");
            else if (!dir)
                check(get_dmem_byte(dest_start + len) == 8'ha5,
                      "RX overwrote byte after destination");
        end
    endtask

    task automatic reset_dut;
        begin
            job_valid=0; job_direction=0; job_dmem_addr=0;
            job_packet_offset=0; job_length=0; job_abort=0;
            job_conflict=0; force_dm_stall=0; force_pkt_stall=0;
            dm_rvalid=0; pkt_rvalid=0; dm_rdata=0; pkt_rdata=0;
            rst_n=0; repeat(3) @(posedge clk); rst_n=1; @(posedge clk);
        end
    endtask

    integer lengths [0:13];
    integer n, src_off, dst_off, test_id;
    initial begin
        lengths[0]=1; lengths[1]=2; lengths[2]=3; lengths[3]=4;
        lengths[4]=5; lengths[5]=7; lengths[6]=60; lengths[7]=64;
        lengths[8]=511; lengths[9]=512; lengths[10]=513;
        lengths[11]=1472; lengths[12]=1514; lengths[13]=1518;
        reset_dut();
        test_id = 1;
        for (n=0;n<14;n++) begin
            for (src_off=0;src_off<4;src_off++) begin
                for (dst_off=0;dst_off<4;dst_off++) begin
                    run_copy(1, test_id, src_off, dst_off, lengths[n]);
                    test_id++;
                    run_copy(0, test_id, src_off, dst_off, lengths[n]);
                    test_id++;
                end
            end
        end
        run_copy(1, test_id, 3, 0, 2048); test_id++;
        run_copy(0, test_id, 0, 3, 2048); test_id++;

        pulse_job(1, 32'h0001ffff, 0, 2);
        wait_terminal(1, 1);
        pulse_job(1, 32'h2000, 0, 0);
        wait_terminal(1, 1);
        pulse_job(1, 32'h2000, 0, 2049);
        wait_terminal(1, 1);

        force_dm_stall=1;
        pulse_job(1, 32'h2000, 0, 64);
        wait_terminal(1, 5);
        force_dm_stall=0;

        pulse_job(1, 32'h2001, 1, 64);
        repeat(2) @(posedge clk);
        @(negedge clk); job_abort=1; @(posedge clk); #1;
        check(job_error && job_error_code == 2, "abort did not terminate");
        @(negedge clk); job_abort=0; @(posedge clk);

        pulse_job(0, 32'h2002, 3, 64);
        repeat(2) @(posedge clk);
        @(negedge clk); job_conflict=2'b01; @(posedge clk); #1;
        check(job_error && job_error_code == 3,
              "DMEM conflict did not terminate");
        @(negedge clk); job_conflict=0; @(posedge clk);

        pulse_job(1, 32'h2003, 2, 64);
        repeat(2) @(posedge clk);
        @(negedge clk); job_conflict=2'b10; @(posedge clk); #1;
        check(job_error && job_error_code == 4,
              "packet conflict did not terminate");
        @(negedge clk); job_conflict=0; @(posedge clk);

        $display("V40 DMA TRANSFER ENGINE PASSED checks=%0d", checks);
        $finish;
    end
endmodule
