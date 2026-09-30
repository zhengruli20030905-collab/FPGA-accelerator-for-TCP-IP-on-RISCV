`timescale 1ns/1ps

module tb_v40_soc_network;
`ifdef V31_SGDMA_SIM
    integer v31_mode=0;
    integer v40_checksum_mode=0;
    integer v31_profile=1;
    integer v31_test_mode=0;
    integer v40_tcp_rx_sink=0;
    integer cpu_tx_start_writes=0;
    integer v31_max_pending=0;
    integer v40_prepost_only=0;
    integer v40_initial_rx_pending=0;
    reg [17:0] v31_switches;
    initial begin
        if ($value$plusargs("SGDMA_MODE=%d",v31_mode)) begin end
        if ($value$plusargs("CHECKSUM_MODE=%d",v40_checksum_mode)) begin end
        if ($value$plusargs("PROFILE=%d",v31_profile)) begin end
        if ($value$plusargs("TEST_MODE=%d",v31_test_mode)) begin end
        if ($value$plusargs("TCP_RX_SINK=%d",v40_tcp_rx_sink)) begin end
        if ($value$plusargs("RX_PREPOST_ONLY=%d",v40_prepost_only)) begin end
        v31_switches=(v40_tcp_rx_sink << 6) | (v40_checksum_mode << 5) |
                     (v31_test_mode << 3) | (v31_profile << 1) | v31_mode;
        force uut.u_Mem_stage.dm.board_sw_i = v31_switches;
    end

`endif
    localparam integer MAX_WAIT_CYCLES = 5000000;
`ifdef V27_SYNC_IMEM_SIM
    localparam [31:0] FW_READY_MARKER = 32'hC027B00B;
`elsif V26_TCP_ECHO_SIM
    localparam [31:0] FW_READY_MARKER = 32'hC026B00B;
`else
    localparam [31:0] FW_READY_MARKER = 32'hC025B00B;
`endif
    localparam [31:0] LOCAL_IP = 32'hc0a80132;

    reg clk;
    reg rst_n;
    wire halted;

`ifdef V31_SGDMA_SIM
    // SGDMA TX must be launched by hardware autorun.  A CPU TX_CMD.START
    // write in SGDMA mode would hide a missing autorun implementation.
    always @(posedge clk) begin
        integer pending_now;
        if (rst_n && uut.u_Mem_stage.dm.tse_mem_write &&
            (uut.u_Mem_stage.dm.addr == 32'h1000_3058) &&
            uut.u_Mem_stage.dm.din[0])
            cpu_tx_start_writes <= cpu_tx_start_writes + 1;
        if (rst_n && (v31_mode != 0)) begin
            pending_now =
                (uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_tail -
                 uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_head) +
                (uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail -
                 uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_head);
            if (pending_now > v31_max_pending)
                v31_max_pending <= pending_now;
        end
    end
`endif

    wire [31:0] rx_data;
    wire [1:0] rx_empty;
    wire rx_valid;
    wire rx_sop;
    wire rx_eop;
    wire rx_ready;

    wire [31:0] tx_data;
    wire [1:0] tx_empty;
    wire tx_valid;
    wire tx_sop;
    wire tx_eop;
    reg tx_ready;

    localparam integer MAX_FRAME_BYTES = 2048;
    reg [7:0] tx_bytes [0:MAX_FRAME_BYTES-1];
    reg [7:0] expected_bytes [0:MAX_FRAME_BYTES-1];
    reg [7:0] peer_mac [0:5];
    reg tx_in_frame;
    integer tx_byte_count;
    integer tx_last_len;
    integer tx_frame_count;
    integer expected_len;
    integer input_len;
    integer seed;
    integer i;
    integer round;
    reg [31:0] data_rng;
    reg [31:0] ready_rng;
    reg [31:0] peer_ip;

    reg rx_was_stalled;
    reg [31:0] held_rx_data;
    reg [1:0] held_rx_empty;
    reg held_rx_sop;
    reg held_rx_eop;
    reg tx_was_stalled;
    reg [31:0] held_tx_data;
    reg [1:0] held_tx_empty;
    reg held_tx_sop;
    reg held_tx_eop;
    integer wire_trace_fd;
    reg [4095:0] wire_trace_path;
    initial begin
        wire_trace_fd=0;
        if($value$plusargs("WIRE_TRACE=%s",wire_trace_path)) begin
            wire_trace_fd=$fopen(wire_trace_path,"w");
            if(!wire_trace_fd)$fatal(1,"cannot open wire trace");
        end
    end
    integer csum_calls_addr,csum_bytes_addr,csum_ticks_addr,sink_addr;
    integer tx_stats_addr;
    longint unsigned cycle_count=0,perf_cycle,perf_bytes,perf_ticks,perf_calls;
    integer perf_tx_count;
    always @(posedge clk)cycle_count<=cycle_count+1;
    initial begin
        if(!$value$plusargs("CSUM_CALLS_ADDR=%h",csum_calls_addr))csum_calls_addr=0;
        if(!$value$plusargs("CSUM_BYTES_ADDR=%h",csum_bytes_addr))csum_bytes_addr=0;
        if(!$value$plusargs("CSUM_TICKS_ADDR=%h",csum_ticks_addr))csum_ticks_addr=0;
        if(!$value$plusargs("SINK_ADDR=%h",sink_addr))sink_addr=0;
        if(!$value$plusargs("TX_STATS_ADDR=%h",tx_stats_addr))tx_stats_addr=0;
    end
    function automatic [63:0] mem64(input integer a);
        return {uut.u_Mem_stage.dm.u_data_ram.dm[(a>>2)+1],uut.u_Mem_stage.dm.u_data_ram.dm[a>>2]};
    endfunction
    task perf_begin;
        begin
            perf_cycle=cycle_count;perf_bytes=mem64(csum_bytes_addr);perf_ticks=mem64(csum_ticks_addr);
            perf_calls=uut.u_Mem_stage.dm.u_data_ram.dm[csum_calls_addr>>2];perf_tx_count=tx_frame_count;
        end
    endtask
    task perf_end(input string name,input integer payload,input integer packets);
        reg [63:0] bytes_delta;
        begin
            bytes_delta=mem64(csum_bytes_addr)-perf_bytes;
            $display("V40 PERF name=%s payload=%0d packets=%0d cycles=%0d scan_calls=%0d scan_bytes=%0d scan_ticks=%0d",name,payload,packets,cycle_count-perf_cycle,
                uut.u_Mem_stage.dm.u_data_ram.dm[csum_calls_addr>>2]-perf_calls,bytes_delta,mem64(csum_ticks_addr)-perf_ticks);
            if(v31_mode && v40_checksum_mode && bytes_delta!=0)
                $fatal(1,"supported UDP/TCP hardware offload still scans payload in software");
        end
    endtask

    rv32i_cpu uut (
        .clk(clk), .rst_n(rst_n), .halted(halted),
        .sim_tse_rx_data(rx_data), .sim_tse_rx_empty(rx_empty),
        .sim_tse_rx_valid(rx_valid),
        .sim_tse_rx_startofpacket(rx_sop),
        .sim_tse_rx_endofpacket(rx_eop),
        .sim_tse_rx_ready(rx_ready),
        .sim_tse_tx_data(tx_data), .sim_tse_tx_empty(tx_empty),
        .sim_tse_tx_valid(tx_valid),
        .sim_tse_tx_startofpacket(tx_sop),
        .sim_tse_tx_endofpacket(tx_eop),
        .sim_tse_tx_ready(tx_ready)
    );

    tse_sim_frame_source u_source (
        .clk(clk), .rst_n(rst_n),
        .data(rx_data), .empty(rx_empty), .valid(rx_valid),
        .startofpacket(rx_sop), .endofpacket(rx_eop), .ready(rx_ready)
    );

    function [31:0] next_random;
        input [31:0] state;
        begin
            next_random = state ^ (state << 13);
            next_random = next_random ^ (next_random >> 17);
            next_random = next_random ^ (next_random << 5);
            if (next_random == 32'd0)
                next_random = 32'h1;
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #20 clk = ~clk; // Formal v40 25 MHz CPU/MMIO clock.
    end

    // Reproducible random TX backpressure. The source must hold all stream
    // fields until valid && ready, which is checked independently below.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_rng <= 32'h1;
            tx_ready <= 1'b0;
        end else begin
            ready_rng <= next_random(ready_rng);
            tx_ready <= ready_rng[0] | ready_rng[3];
        end
    end

    always @(posedge clk or negedge rst_n) begin : stream_stability
        if (!rst_n) begin
            rx_was_stalled <= 1'b0;
            tx_was_stalled <= 1'b0;
            held_rx_data <= 32'd0;
            held_rx_empty <= 2'd0;
            held_rx_sop <= 1'b0;
            held_rx_eop <= 1'b0;
            held_tx_data <= 32'd0;
            held_tx_empty <= 2'd0;
            held_tx_sop <= 1'b0;
            held_tx_eop <= 1'b0;
        end else begin
            if (rx_was_stalled &&
                ((rx_data !== held_rx_data) || (rx_empty !== held_rx_empty) ||
                 (rx_sop !== held_rx_sop) || (rx_eop !== held_rx_eop) ||
                 !rx_valid))
                $fatal(1, "SEED=%0d RX source changed while valid && !ready", seed);
            if (tx_was_stalled &&
                ((tx_data !== held_tx_data) || (tx_empty !== held_tx_empty) ||
                 (tx_sop !== held_tx_sop) || (tx_eop !== held_tx_eop) ||
                 !tx_valid))
                $fatal(1, "SEED=%0d TX source changed while valid && !ready", seed);

            rx_was_stalled <= rx_valid && !rx_ready;
            held_rx_data <= rx_data;
            held_rx_empty <= rx_empty;
            held_rx_sop <= rx_sop;
            held_rx_eop <= rx_eop;
            tx_was_stalled <= tx_valid && !tx_ready;
            held_tx_data <= tx_data;
            held_tx_empty <= tx_empty;
            held_tx_sop <= tx_sop;
            held_tx_eop <= tx_eop;
        end
    end

    always @(posedge clk or negedge rst_n) begin : tx_monitor
        integer valid_bytes;
        integer lane;
        if (!rst_n) begin
            tx_in_frame = 1'b0;
            tx_byte_count = 0;
            tx_last_len = 0;
            tx_frame_count = 0;
        end else if (tx_valid && tx_ready) begin
            if (tx_sop) begin
                if (tx_in_frame)
                    $fatal(1, "SEED=%0d TX duplicate SOP", seed);
                tx_in_frame = 1'b1;
                tx_byte_count = 0;
            end else if (!tx_in_frame) begin
                $fatal(1, "SEED=%0d TX word without SOP", seed);
            end
            if (!tx_eop && (tx_empty != 0))
                $fatal(1, "SEED=%0d TX non-EOP empty=%0d", seed, tx_empty);
            valid_bytes = tx_eop ? (4 - tx_empty) : 4;
            if ((valid_bytes < 1) || (valid_bytes > 4) ||
                ((tx_byte_count + valid_bytes) > MAX_FRAME_BYTES))
                $fatal(1, "SEED=%0d TX invalid length/empty", seed);
            for (lane = 0; lane < valid_bytes; lane = lane + 1)
                tx_bytes[tx_byte_count + lane] = tx_data >> (lane * 8);
            tx_byte_count = tx_byte_count + valid_bytes;
            if (tx_eop) begin
                if (!tx_in_frame)
                    $fatal(1, "SEED=%0d TX EOP outside frame", seed);
                tx_in_frame = 1'b0;
                tx_last_len = tx_byte_count;
                tx_frame_count = tx_frame_count + 1;
                if(wire_trace_fd)begin
                    for(integer trace_byte=0;trace_byte<tx_byte_count;trace_byte++)
                        $fwrite(wire_trace_fd,"%02x",tx_bytes[trace_byte]);
                    $fwrite(wire_trace_fd,"\n");$fflush(wire_trace_fd);
                end
            end
        end
    end

    function [15:0] source_checksum;
        input integer start_index;
        input integer byte_len;
        integer pos;
        integer sum;
        begin
            sum = 0;
            pos = 0;
            while ((pos + 1) < byte_len) begin
                sum = sum + (u_source.frame_bytes[start_index + pos] << 8) +
                      u_source.frame_bytes[start_index + pos + 1];
                pos = pos + 2;
            end
            if (pos < byte_len)
                sum = sum + (u_source.frame_bytes[start_index + pos] << 8);
            while ((sum >> 16) != 0)
                sum = (sum & 16'hffff) + (sum >> 16);
            source_checksum = (~sum) & 16'hffff;
        end
    endfunction

    function [15:0] expected_checksum;
        input integer start_index;
        input integer byte_len;
        integer pos;
        integer sum;
        begin
            sum = 0;
            pos = 0;
            while ((pos + 1) < byte_len) begin
                sum = sum + (expected_bytes[start_index + pos] << 8) +
                      expected_bytes[start_index + pos + 1];
                pos = pos + 2;
            end
            if (pos < byte_len)
                sum = sum + (expected_bytes[start_index + pos] << 8);
            while ((sum >> 16) != 0)
                sum = (sum & 16'hffff) + (sum >> 16);
            expected_checksum = (~sum) & 16'hffff;
        end
    endfunction

    function [15:0] tx_be16;
        input integer index;
        begin
            tx_be16 = (tx_bytes[index] << 8) | tx_bytes[index + 1];
        end
    endfunction

    function [31:0] tx_be32;
        input integer index;
        begin
            tx_be32 = (tx_bytes[index] << 24) |
                      (tx_bytes[index + 1] << 16) |
                      (tx_bytes[index + 2] << 8) |
                       tx_bytes[index + 3];
        end
    endfunction

    function [15:0] tx_checksum;
        input integer start_index;
        input integer byte_len;
        integer pos;
        integer sum;
        begin
            sum = 0;
            for (pos = 0; (pos + 1) < byte_len; pos = pos + 2)
                sum = sum + (tx_bytes[start_index + pos] << 8) +
                      tx_bytes[start_index + pos + 1];
            if (pos < byte_len)
                sum = sum + (tx_bytes[start_index + pos] << 8);
            while (sum > 16'hffff)
                sum = (sum & 16'hffff) + (sum >> 16);
            tx_checksum = (~sum) & 16'hffff;
        end
    endfunction

    function integer tx_udp_checksum_valid;
        input integer udp_len;
        integer pos;
        integer sum;
        begin
            sum = 0;
            for (pos = 26; pos < 34; pos = pos + 2)
                sum = sum + (tx_bytes[pos] << 8) + tx_bytes[pos + 1];
            sum = sum + 16'h0011 + udp_len;
            for (pos = 0; (pos + 1) < udp_len; pos = pos + 2)
                sum = sum + (tx_bytes[34 + pos] << 8) +
                      tx_bytes[34 + pos + 1];
            if (pos < udp_len)
                sum = sum + (tx_bytes[34 + pos] << 8);
            while (sum > 16'hffff)
                sum = (sum & 16'hffff) + (sum >> 16);
            tx_udp_checksum_valid = ((sum & 16'hffff) == 16'hffff);
        end
    endfunction

    function [15:0] source_tcp_checksum;
        input integer tcp_len;
        integer pos;
        integer sum;
        begin
            sum = 0;
            for (pos = 26; pos < 34; pos = pos + 2)
                sum = sum + (u_source.frame_bytes[pos] << 8) +
                      u_source.frame_bytes[pos + 1];
            sum = sum + u_source.frame_bytes[23] + tcp_len;
            for (pos = 0; (pos + 1) < tcp_len; pos = pos + 2)
                sum = sum + (u_source.frame_bytes[34 + pos] << 8) +
                      u_source.frame_bytes[34 + pos + 1];
            if (pos < tcp_len)
                sum = sum + (u_source.frame_bytes[34 + pos] << 8);
            while (sum > 16'hffff)
                sum = (sum & 16'hffff) + (sum >> 16);
            source_tcp_checksum = (~sum) & 16'hffff;
        end
    endfunction

    function integer tx_tcp_checksum_valid;
        input integer tcp_len;
        integer pos;
        integer sum;
        begin
            sum = 0;
            for (pos = 26; pos < 34; pos = pos + 2)
                sum = sum + (tx_bytes[pos] << 8) + tx_bytes[pos + 1];
            sum = sum + 16'h0006 + tcp_len;
            for (pos = 0; (pos + 1) < tcp_len; pos = pos + 2)
                sum = sum + (tx_bytes[34 + pos] << 8) +
                      tx_bytes[34 + pos + 1];
            if (pos < tcp_len)
                sum = sum + (tx_bytes[34 + pos] << 8);
            while (sum > 16'hffff)
                sum = (sum & 16'hffff) + (sum >> 16);
            tx_tcp_checksum_valid = ((sum & 16'hffff) == 16'hffff);
        end
    endfunction

    task source_be16;
        input integer index;
        input [15:0] value;
        begin
            u_source.frame_bytes[index] = value[15:8];
            u_source.frame_bytes[index + 1] = value[7:0];
        end
    endtask

    task source_be32;
        input integer index;
        input [31:0] value;
        begin
            u_source.frame_bytes[index] = value[31:24];
            u_source.frame_bytes[index + 1] = value[23:16];
            u_source.frame_bytes[index + 2] = value[15:8];
            u_source.frame_bytes[index + 3] = value[7:0];
        end
    endtask

    task expected_be16;
        input integer index;
        input [15:0] value;
        begin
            expected_bytes[index] = value[15:8];
            expected_bytes[index + 1] = value[7:0];
        end
    endtask

    task expected_be32;
        input integer index;
        input [31:0] value;
        begin
            expected_bytes[index] = value[31:24];
            expected_bytes[index + 1] = value[23:16];
            expected_bytes[index + 2] = value[15:8];
            expected_bytes[index + 3] = value[7:0];
        end
    endtask

    task clear_source;
        begin
            for (i = 0; i < MAX_FRAME_BYTES; i = i + 1)
                u_source.frame_bytes[i] = 8'd0;
        end
    endtask

    task randomize_peer;
        begin
            for (i = 0; i < 6; i = i + 1) begin
                data_rng = next_random(data_rng);
                peer_mac[i] = data_rng[7:0];
            end
            peer_mac[0] = (peer_mac[0] | 8'h02) & 8'hfe;
            data_rng = next_random(data_rng);
            peer_ip = 32'hc0a80100 | (8'd2 + (data_rng[7:0] % 8'd248));
            if (peer_ip == LOCAL_IP)
                peer_ip = 32'hc0a8010a;
        end
    endtask

    task put_eth_header;
        input integer broadcast;
        begin
            for (i = 0; i < 6; i = i + 1) begin
                u_source.frame_bytes[i] = broadcast ? 8'hff :
                    ((i == 0) ? 8'h02 :
                     (i == 1) ? 8'h12 :
                     (i == 2) ? 8'h34 :
                     (i == 3) ? 8'h56 :
                     (i == 4) ? 8'h78 : 8'h9a);
                u_source.frame_bytes[6 + i] = peer_mac[i];
            end
        end
    endtask

    task build_ipv4_header;
        input [7:0] protocol;
        input [15:0] total_len;
        input [15:0] identification;
        reg [15:0] checksum;
        begin
            source_be16(12, 16'h0800);
            u_source.frame_bytes[14] = 8'h45;
            u_source.frame_bytes[15] = 8'h00;
            source_be16(16, total_len);
            source_be16(18, identification);
            source_be16(20, 16'h4000);
            u_source.frame_bytes[22] = 8'h40;
            u_source.frame_bytes[23] = protocol;
            source_be16(24, 16'h0000);
            source_be32(26, peer_ip);
            source_be32(30, LOCAL_IP);
            checksum = source_checksum(14, 20);
            source_be16(24, checksum);
        end
    endtask

    task copy_source_to_expected;
        input integer len;
        begin
            for (i = 0; i < MAX_FRAME_BYTES; i = i + 1)
                expected_bytes[i] = (i < len) ? u_source.frame_bytes[i] : 8'd0;
        end
    endtask

    task swap_expected;
        input integer a;
        input integer b;
        input integer len;
        reg [7:0] temp;
        begin
            for (i = 0; i < len; i = i + 1) begin
                temp = expected_bytes[a + i];
                expected_bytes[a + i] = expected_bytes[b + i];
                expected_bytes[b + i] = temp;
            end
        end
    endtask

    task build_arp;
        begin
            clear_source();
            put_eth_header(1);
            source_be16(12, 16'h0806);
            source_be16(14, 16'h0001);
            source_be16(16, 16'h0800);
            u_source.frame_bytes[18] = 8'h06;
            u_source.frame_bytes[19] = 8'h04;
            source_be16(20, 16'h0001);
            for (i = 0; i < 6; i = i + 1)
                u_source.frame_bytes[22 + i] = peer_mac[i];
            source_be32(28, peer_ip);
            source_be32(38, LOCAL_IP);
            input_len = 60;
            copy_source_to_expected(input_len);
            for (i = 0; i < 6; i = i + 1) begin
                expected_bytes[i] = peer_mac[i];
                expected_bytes[6 + i] = (i == 0) ? 8'h02 :
                    (i == 1) ? 8'h12 : (i == 2) ? 8'h34 :
                    (i == 3) ? 8'h56 : (i == 4) ? 8'h78 : 8'h9a;
                expected_bytes[22 + i] = expected_bytes[6 + i];
                expected_bytes[32 + i] = peer_mac[i];
            end
            expected_be16(20, 16'h0002);
            expected_be32(28, LOCAL_IP);
            expected_be32(38, peer_ip);
            expected_len = 60;
        end
    endtask

    task build_icmp;
        input integer payload_len;
        reg [15:0] checksum;
        reg [15:0] identification;
        reg [15:0] identifier;
        reg [15:0] seq_value;
        integer logical_len;
        begin
            clear_source();
            put_eth_header(0);
            data_rng = next_random(data_rng); identification = data_rng[15:0];
            build_ipv4_header(8'h01, 28 + payload_len, identification);
            u_source.frame_bytes[34] = 8'h08;
            u_source.frame_bytes[35] = 8'h00;
            source_be16(36, 16'h0000);
            data_rng = next_random(data_rng); identifier = data_rng[15:0];
            data_rng = next_random(data_rng); seq_value = data_rng[15:0];
            source_be16(38, identifier);
            source_be16(40, seq_value);
            for (i = 0; i < payload_len; i = i + 1) begin
                data_rng = next_random(data_rng);
                u_source.frame_bytes[42 + i] = data_rng[7:0];
            end
            checksum = source_checksum(34, 8 + payload_len);
            source_be16(36, checksum);
            logical_len = 42 + payload_len;
            input_len = (logical_len < 60) ? 60 : logical_len;
            copy_source_to_expected(input_len);
            swap_expected(0, 6, 6);
            swap_expected(26, 30, 4);
            expected_bytes[34] = 8'h00;
            expected_be16(36, 16'h0000);
            expected_be16(36, expected_checksum(34, 8 + payload_len));
            expected_be16(24, 16'h0000);
            expected_be16(24, expected_checksum(14, 20));
            expected_len = (logical_len < 60) ? 60 : logical_len;
            for (i = logical_len; i < expected_len; i = i + 1)
                expected_bytes[i] = 8'd0;
        end
    endtask

    task build_udp;
        input integer payload_len;
        reg [15:0] identification;
        reg [15:0] source_port;
        reg [15:0] udp_checksum;
        integer logical_len;
        begin
            clear_source();
            put_eth_header(0);
            data_rng = next_random(data_rng); identification = data_rng[15:0];
            build_ipv4_header(8'h11, 28 + payload_len, identification);
            data_rng = next_random(data_rng);
            source_port = 16'h4000 | data_rng[13:0];
            if (source_port == 16'd1234)
                source_port = 16'h9c40;
            source_be16(34, source_port);
            source_be16(36, 16'd1234);
            source_be16(38, 8 + payload_len);
            source_be16(40, 16'h0000);
            for (i = 0; i < payload_len; i = i + 1) begin
                data_rng = next_random(data_rng);
                u_source.frame_bytes[42 + i] = data_rng[7:0];
            end
            logical_len = 42 + payload_len;
            udp_checksum=source_tcp_checksum(8+payload_len);
            source_be16(40,udp_checksum==0 ? 16'hffff : udp_checksum);
            input_len = (logical_len < 60) ? 60 : logical_len;
            copy_source_to_expected(input_len);
            swap_expected(0, 6, 6);
            swap_expected(26, 30, 4);
            swap_expected(34, 36, 2);
            expected_be16(40, 16'h0000);
            expected_be16(24, 16'h0000);
            expected_be16(24, expected_checksum(14, 20));
            expected_len = (logical_len < 60) ? 60 : logical_len;
            for (i = logical_len; i < expected_len; i = i + 1)
                expected_bytes[i] = 8'd0;
        end
    endtask

    task build_tcp;
        input [15:0] source_port;
        input [31:0] sequence_number;
        input [31:0] acknowledgement_number;
        input [7:0] flags;
        input integer payload_len;
        reg [15:0] identification;
        reg [15:0] checksum;
        integer logical_len;
        begin
            clear_source();
            put_eth_header(0);
            data_rng = next_random(data_rng);
            identification = data_rng[15:0];
            build_ipv4_header(8'h06, 40 + payload_len, identification);
            source_be16(34, source_port);
            source_be16(36, 16'd5001);
            source_be32(38, sequence_number);
            source_be32(42, acknowledgement_number);
            u_source.frame_bytes[46] = 8'h50;
            u_source.frame_bytes[47] = flags;
            source_be16(48, 16'h2000);
            source_be16(50, 16'h0000);
            source_be16(52, 16'h0000);
            for (i = 0; i < payload_len; i = i + 1)
                u_source.frame_bytes[54 + i] = 8'h41 + (i % 26);
            checksum = source_tcp_checksum(20 + payload_len);
            source_be16(50, checksum);
            logical_len = 54 + payload_len;
            input_len = (logical_len < 60) ? 60 : logical_len;
        end
    endtask

    task build_tcp_source_command;
        input [15:0] source_port;
        input [31:0] sequence_number;
        input [31:0] acknowledgement_number;
        input integer start_command;
        integer command_length;
        reg [15:0] checksum;
        begin
            command_length = start_command ? 8 : 10;
            build_tcp(source_port, sequence_number, acknowledgement_number,
                      8'h18, command_length);
            u_source.frame_bytes[54] = "V";
            u_source.frame_bytes[55] = "4";
            u_source.frame_bytes[56] = "0";
            u_source.frame_bytes[57] = "T";
            u_source.frame_bytes[58] = "C";
            u_source.frame_bytes[59] = "P";
            if (start_command) begin
                u_source.frame_bytes[60] = "G";
                u_source.frame_bytes[61] = "O";
            end else begin
                u_source.frame_bytes[60] = "S";
                u_source.frame_bytes[61] = "T";
                u_source.frame_bytes[62] = "O";
                u_source.frame_bytes[63] = "P";
            end
            source_be16(50, 16'h0000);
            checksum = source_tcp_checksum(20 + command_length);
            source_be16(50, checksum);
        end
    endtask

    // Keep the synthetic peer receive window deliberately smaller than one
    // application chunk.  The DUT may still queue all eight zero-copy TX
    // buffers in lwIP, but only one wire segment can be outstanding here.
    // This lets the simple frame monitor validate every byte and also tests
    // that a TX pool slot is retained across partial ACKs.
    task limit_tcp_source_window;
        input [15:0] advertised_window;
        integer tcp_length;
        reg [15:0] checksum;
        begin
            tcp_length = ((u_source.frame_bytes[16] << 8) |
                          u_source.frame_bytes[17]) - 20;
            source_be16(48, advertised_window);
            source_be16(50, 16'h0000);
            checksum = source_tcp_checksum(tcp_length);
            source_be16(50, checksum);
        end
    endtask

    function [7:0] expected_v40_tcp_byte;
        input integer stream_offset;
        integer chunk_index;
        integer chunk_offset;
        reg [31:0] sequence_value;
        begin
            chunk_index = stream_offset / 1460;
            chunk_offset = stream_offset % 1460;
            sequence_value = chunk_index;
            case (chunk_offset)
                0: expected_v40_tcp_byte = "V";
                1: expected_v40_tcp_byte = "4";
                2: expected_v40_tcp_byte = "0";
                3: expected_v40_tcp_byte = "C";
                4,8: expected_v40_tcp_byte = sequence_value[7:0];
                5,9: expected_v40_tcp_byte = sequence_value[15:8];
                6,10: expected_v40_tcp_byte = sequence_value[23:16];
                7,11: expected_v40_tcp_byte = sequence_value[31:24];
                default: expected_v40_tcp_byte =
                    (sequence_value + chunk_offset * 31 + 7) & 8'hff;
            endcase
        end
    endfunction

    function integer tx_is_peer_tcp;
        input [15:0] peer_port;
        begin
            tx_is_peer_tcp = (tx_be16(12) == 16'h0800) &&
                             (tx_bytes[23] == 8'h06) &&
                             (tx_be16(34) == 16'd5001) &&
                             (tx_be16(36) == peer_port);
        end
    endfunction

    task wait_for_peer_tcp_frame;
        input [15:0] peer_port;
        integer observed_count;
        integer cycles;
        begin
            observed_count = tx_frame_count;
            cycles = 0;
            while (cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                #1;
                if (tx_frame_count != observed_count) begin
                    observed_count = tx_frame_count;
                    if (tx_is_peer_tcp(peer_port))
                        cycles = MAX_WAIT_CYCLES;
                end
                if (!tx_is_peer_tcp(peer_port))
                    cycles = cycles + 1;
            end
            if (!tx_is_peer_tcp(peer_port))
                $fatal(1, "SEED=%0d timeout waiting for TCP port 5001 frame", seed);
        end
    endtask

    task wait_for_peer_tcp_data;
        input [15:0] peer_port;
        output integer data_length;
        integer observed_count;
        integer cycles;
        begin
            observed_count = tx_frame_count;
            data_length = 0;
            cycles = 0;
            while (data_length == 0 && cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                #1;
                if (tx_frame_count != observed_count) begin
                    observed_count = tx_frame_count;
                    if (tx_is_peer_tcp(peer_port) && tx_be16(16) > 40)
                        data_length = tx_be16(16) - 40;
                end
                cycles = cycles + 1;
            end
            if (data_length == 0)
                $fatal(1, "SEED=%0d timeout waiting for V40 TCP source data", seed);
        end
    endtask

    task run_v40_tcp_source_flow;
        reg [15:0] peer_port;
        reg [31:0] peer_isn;
        reg [31:0] peer_next;
        reg [31:0] server_isn;
        reg [31:0] server_next;
        integer data_length;
        integer total_data;
        integer byte_index;
        integer old_rx_count;
        begin
            randomize_peer();
            peer_port = 16'h9c42;
            peer_isn = 32'h55667788;

            build_arp();
            send_positive_and_check(1);
            build_tcp(peer_port, peer_isn, 32'd0, 8'h02, 0);
            limit_tcp_source_window(16'd536);
            u_source.send_frame(input_len);
            wait_for_peer_tcp_frame(peer_port);
            if (((tx_bytes[47] & 8'h12) != 8'h12) ||
                !tx_tcp_checksum_valid(tx_be16(16) - 20))
                $fatal(1, "SEED=%0d invalid V40 TCP source SYN/ACK", seed);
            server_isn = tx_be32(38);
            server_next = server_isn + 1;
            peer_next = peer_isn + 1;

            build_tcp(peer_port, peer_next, server_next, 8'h10, 0);
            limit_tcp_source_window(16'd536);
            send_tcp_without_reply(peer_port);

            build_tcp_source_command(peer_port, peer_next, server_next, 1);
            limit_tcp_source_window(16'd536);
            old_rx_count = uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count;
            u_source.send_frame(input_len);
            wait_for_input_consumed(old_rx_count);
            peer_next = peer_next + 8;

            total_data = 0;
            while (total_data < (12 * 1460)) begin
                wait_for_peer_tcp_data(peer_port, data_length);
                if (tx_be32(38) != server_next ||
                    !tx_tcp_checksum_valid(tx_be16(16) - 20))
                    $fatal(1, "SEED=%0d invalid V40 TCP source segment seq=%08x expected=%08x ip_len=%0d data_len=%0d checksum_ok=%0d",
                           seed, tx_be32(38), server_next, tx_be16(16),
                           data_length, tx_tcp_checksum_valid(tx_be16(16) - 20));
                for (byte_index = 0; byte_index < data_length; byte_index = byte_index + 1) begin
                    if (tx_bytes[54 + byte_index] !==
                        expected_v40_tcp_byte(total_data + byte_index))
                        $fatal(1, "SEED=%0d V40 TCP source payload mismatch stream_offset=%0d",
                               seed, total_data + byte_index);
                end
                total_data = total_data + data_length;
                server_next = server_next + data_length;
                build_tcp(peer_port, peer_next, server_next, 8'h10, 0);
                limit_tcp_source_window(16'd536);
                u_source.send_frame(input_len);
            end

            build_tcp_source_command(peer_port, peer_next, server_next, 0);
            limit_tcp_source_window(16'd536);
            old_rx_count = uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count;
            u_source.send_frame(input_len);
            wait_for_input_consumed(old_rx_count);
            peer_next = peer_next + 10;
            repeat (30000) @(posedge clk);
            $display("PASS: SEED=%0d V40 TCP realtime pool ACK lifetime bytes=%0d",
                     seed, total_data);
        end
    endtask

    task send_tcp_without_reply;
        input [15:0] peer_port;
        integer observed_count;
        integer old_rx_count;
        integer cycles;
        begin
            observed_count = tx_frame_count;
            old_rx_count = uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count;
            u_source.send_frame(input_len);
            cycles = 0;
            while ((uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count !=
                    (old_rx_count + 1)) && (cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (cycles >= MAX_WAIT_CYCLES)
                $fatal(1, "SEED=%0d TCP no-reply RX timeout", seed);
            while (uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_ready)
                @(posedge clk);
            cycles = 0;
            while (cycles < 5000) begin
                @(posedge clk);
                #1;
                if (tx_frame_count != observed_count) begin
                    observed_count = tx_frame_count;
                    if (tx_is_peer_tcp(peer_port))
                        $fatal(1, "SEED=%0d pure TCP ACK unexpectedly produced TCP TX", seed);
                end
                cycles = cycles + 1;
            end
        end
    endtask

    task run_tcp_echo_flow;
        reg [15:0] peer_port;
        reg [31:0] peer_isn;
        reg [31:0] server_isn;
        integer payload_len;
        integer target_count;
        integer logical_len;
        begin
            randomize_peer();
            peer_port = 16'h9c41;
            peer_isn = 32'h11223344;

            // Establish the peer's IP-to-MAC entry before TCP. Without this
            // ARP exchange lwIP correctly queues SYN/ACK and first requests
            // the peer MAC address, so the test would be waiting on ARP.
            build_arp();
            send_positive_and_check(1);

            build_tcp(peer_port, peer_isn, 32'd0, 8'h02, 0);
            u_source.send_frame(input_len);
            wait_for_peer_tcp_frame(peer_port);
            if ((tx_bytes[23] != 8'h06) || (tx_be16(34) != 16'd5001) ||
                (tx_be16(36) != peer_port) ||
                ((tx_bytes[47] & 8'h12) != 8'h12) ||
                (tx_be32(42) != (peer_isn + 1)) ||
                !tx_tcp_checksum_valid(tx_be16(16) - 20))
                $fatal(1, "SEED=%0d invalid TCP SYN/ACK", seed);
            server_isn = tx_be32(38);

            build_tcp(peer_port, peer_isn + 1, server_isn + 1, 8'h10, 0);
            send_tcp_without_reply(peer_port);

            payload_len = 256;
            build_tcp(peer_port, peer_isn + 1, server_isn + 1, 8'h18,
                      payload_len);
            perf_begin();
            u_source.send_frame(input_len);
            wait_for_peer_tcp_frame(peer_port);
            perf_end("TCP_ECHO",payload_len,1);
            logical_len = tx_be16(16) + 14;
            if ((tx_be16(34) != 16'd5001) || (tx_be16(36) != peer_port) ||
                ((tx_bytes[47] & 8'h10) == 0) ||
                (tx_be32(38) != (server_isn + 1)) ||
                (tx_be32(42) != (peer_isn + 1 + payload_len)) ||
                ((tx_be16(16) - 40) != payload_len) ||
                !tx_tcp_checksum_valid(tx_be16(16) - 20))
                $fatal(1, "SEED=%0d invalid TCP echo frame", seed);
            for (i = 0; i < payload_len; i = i + 1)
                if (tx_bytes[54 + i] !== u_source.frame_bytes[54 + i])
                    $fatal(1, "SEED=%0d TCP echo byte %0d mismatch", seed, i);
            for (i = logical_len; i < tx_last_len; i = i + 1)
                if (tx_bytes[i] !== 8'h00)
                    $fatal(1, "SEED=%0d TCP Ethernet pad is nonzero", seed);

            // ACK only half first.  V40 must keep the original RX pbuf alive
            // because lwIP may still retransmit the unacknowledged half from
            // the no-copy payload pointer.
            build_tcp(peer_port, peer_isn + 1 + payload_len,
                      server_isn + 1 + (payload_len / 2), 8'h10, 0);
            send_tcp_without_reply(peer_port);

            // The second ACK completes the same tcp_write record.  Only this
            // callback is allowed to return the RX pbuf to the pool.
            build_tcp(peer_port, peer_isn + 1 + payload_len,
                      server_isn + 1 + payload_len, 8'h10, 0);
            send_tcp_without_reply(peer_port);

            build_tcp(peer_port, peer_isn + 1 + payload_len,
                      server_isn + 1 + payload_len, 8'h11, 0);
            u_source.send_frame(input_len);
            wait_for_peer_tcp_frame(peer_port);
            if ((tx_be16(34) != 16'd5001) ||
                ((tx_bytes[47] & 8'h11) != 8'h11) ||
                (tx_be32(42) != (peer_isn + 2 + payload_len)) ||
                !tx_tcp_checksum_valid(tx_be16(16) - 20))
                $fatal(1, "SEED=%0d invalid TCP FIN/ACK", seed);

            build_tcp(peer_port, peer_isn + 2 + payload_len,
                      server_isn + 2 + payload_len, 8'h10, 0);
            send_tcp_without_reply(peer_port);
`ifdef V27_SYNC_IMEM_SIM
            $display("V40 LWIP TCP ZERO-COPY PARTIAL-ACK/DATA/FIN ECHO PASSED: SEED=%0d", seed);
`else
            $display("V26 LWIP TCP SYN/DATA/FIN ECHO PASSED: SEED=%0d", seed);
`endif
        end
    endtask

    task run_v40_tcp_sink_flow;
        reg [15:0] peer_port;
        reg [31:0] peer_isn;
        reg [31:0] server_isn;
        integer payload_len;
        integer old_tx_count;
        begin
            randomize_peer();
            peer_port = 16'h9c43;
            peer_isn = 32'h66778899;

            build_arp();
            send_positive_and_check(1);

            build_tcp(peer_port, peer_isn, 32'd0, 8'h02, 0);
            u_source.send_frame(input_len);
            wait_for_peer_tcp_frame(peer_port);
            if (((tx_bytes[47] & 8'h12) != 8'h12) ||
                !tx_tcp_checksum_valid(tx_be16(16) - 20))
                $fatal(1, "SEED=%0d invalid TCP sink SYN/ACK", seed);
            server_isn = tx_be32(38);

            build_tcp(peer_port, peer_isn + 1, server_isn + 1, 8'h10, 0);
            send_tcp_without_reply(peer_port);

            payload_len = 1460;
            build_tcp(peer_port, peer_isn + 1, server_isn + 1, 8'h18,
                      payload_len);
            old_tx_count = tx_frame_count;
            perf_begin();
            u_source.send_frame(input_len);
            wait_for_peer_tcp_frame(peer_port);
            perf_end("TCP_RX_ONLY", payload_len, 1);
            if ((tx_frame_count <= old_tx_count) ||
                (tx_be16(16) != 40) ||
                (tx_be16(34) != 16'd5001) ||
                (tx_be16(36) != peer_port) ||
                ((tx_bytes[47] & 8'h10) == 0) ||
                (tx_be32(38) != (server_isn + 1)) ||
                (tx_be32(42) != (peer_isn + 1 + payload_len)) ||
                !tx_tcp_checksum_valid(20))
                $fatal(1, "SEED=%0d TCP RX-only sink emitted payload or invalid ACK", seed);

            build_tcp(peer_port, peer_isn + 1 + payload_len,
                      server_isn + 1, 8'h11, 0);
            u_source.send_frame(input_len);
            wait_for_peer_tcp_frame(peer_port);
            if ((tx_be16(16) != 40) ||
                ((tx_bytes[47] & 8'h11) != 8'h11) ||
                (tx_be32(42) != (peer_isn + 2 + payload_len)) ||
                !tx_tcp_checksum_valid(20))
                $fatal(1, "SEED=%0d invalid TCP sink FIN/ACK", seed);

            build_tcp(peer_port, peer_isn + 2 + payload_len,
                      server_isn + 2, 8'h10, 0);
            send_tcp_without_reply(peer_port);
            $display("PASS: SEED=%0d V40 TCP RX-only sink consumed %0d bytes without echo payload",
                     seed, payload_len);
        end
    endtask

    task wait_for_firmware_ready;
        integer cycles;
        begin
            cycles = 0;
            while ((uut.u_Mem_stage.dm.u_data_ram.dm[14'h0040] !== FW_READY_MARKER) &&
                   (cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (uut.u_Mem_stage.dm.u_data_ram.dm[14'h0040] !== FW_READY_MARKER)
                $fatal(1, "SEED=%0d timeout waiting for robust firmware", seed);
            repeat (8) @(posedge clk);
        end
    endtask

`ifdef V31_SGDMA_SIM
    task check_v40_initial_rx_prepost;
        integer descriptor_base;
        integer descriptor_index;
        integer prior_index;
        integer descriptor_count;
        integer first_count;
        integer last_count;
        integer frame_capacity;
        reg [31:0] buffer_address;
        reg [31:0] prior_buffer_address;
        reg [31:0] descriptor_capacity;
        reg [31:0] descriptor_control;
        reg [31:0] descriptor_status;
        begin
            if (v31_mode == 0)
                disable check_v40_initial_rx_prepost;
            if (uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_head != 0)
                $fatal(1, "V40 prepost RX_HEAD was not zero before traffic");
            descriptor_count =
                uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail;
            if (descriptor_count != 8)
                $fatal(1, "V40 RX single-pbuf prepost descriptors=%0d expected=8",
                       descriptor_count);
            if (uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail_writes != 1)
                $fatal(1, "V40 initial eight frame chains did not use one TAIL write");
            v40_initial_rx_pending = descriptor_count;

            descriptor_base =
                uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_base;
            if ((descriptor_base[3:0] != 0) || descriptor_base < 0 ||
                descriptor_base >= 32'h0002_0000)
                $fatal(1, "V40 RX descriptor base is invalid: %08x", descriptor_base);
            first_count = 0;
            last_count = 0;
            frame_capacity = 0;
            for (descriptor_index = 0; descriptor_index < descriptor_count;
                 descriptor_index = descriptor_index + 1) begin
                buffer_address = uut.u_Mem_stage.dm.u_data_ram.dm[
                    (descriptor_base >> 2) + descriptor_index*4];
                descriptor_capacity = uut.u_Mem_stage.dm.u_data_ram.dm[
                    (descriptor_base >> 2) + descriptor_index*4 + 1];
                descriptor_control = uut.u_Mem_stage.dm.u_data_ram.dm[
                    (descriptor_base >> 2) + descriptor_index*4 + 2];
                descriptor_status = uut.u_Mem_stage.dm.u_data_ram.dm[
                    (descriptor_base >> 2) + descriptor_index*4 + 3];
                if (buffer_address == 0 ||
                    buffer_address >= 32'h0002_0000)
                    $fatal(1, "V40 RX segment %0d address invalid: %08x",
                           descriptor_index, buffer_address);
                if ((descriptor_capacity == 0) || (descriptor_capacity > 1536))
                    $fatal(1, "V40 RX segment %0d capacity invalid: %0d",
                           descriptor_index, descriptor_capacity);
                if ((descriptor_control & 32'h0000_0003) != 32'h0000_0001)
                    $fatal(1, "V40 RX segment %0d control=%08x expected OWN/RX",
                           descriptor_index, descriptor_control);
                if (descriptor_status != 0)
                    $fatal(1, "V40 RX segment %0d status was not clear", descriptor_index);
                if (descriptor_control[2]) begin
                    if (frame_capacity != 0)
                        $fatal(1, "V40 FIRST appeared before prior LAST");
                    first_count = first_count + 1;
                end else if (frame_capacity == 0) begin
                    $fatal(1, "V40 RX chain started without FIRST");
                end
                frame_capacity = frame_capacity + descriptor_capacity;
                if (descriptor_control[3]) begin
                    if (frame_capacity != 1514)
                        $fatal(1, "V40 RX frame capacity=%0d expected=1514",
                               frame_capacity);
                    frame_capacity = 0;
                    last_count = last_count + 1;
                end
                for (prior_index = 0; prior_index < descriptor_index;
                     prior_index = prior_index + 1) begin
                    prior_buffer_address = uut.u_Mem_stage.dm.u_data_ram.dm[
                        (descriptor_base >> 2) + prior_index*4];
                    if (prior_buffer_address == buffer_address)
                        $fatal(1, "V40 RX descriptors %0d and %0d duplicate buffer %08x",
                               prior_index, descriptor_index, buffer_address);
                end
            end
            if ((first_count != 8) || (last_count != 8) ||
                (frame_capacity != 0))
                $fatal(1, "V40 expected eight complete chains FIRST=%0d LAST=%0d",
                       first_count, last_count);
            $display("PASS: V40 initial RX single-pbuf prepost frames=8 descriptors=%0d tail_writes=1",
                      descriptor_count);
        end
    endtask
`endif

    task wait_for_tx_frame;
        input integer target_count;
        integer cycles;
        begin
            cycles = 0;
            while ((tx_frame_count < target_count) &&
                   (cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (tx_frame_count != target_count) begin
                $display("V40 TX TIMEOUT DIAG pc=%08x ex_addr=%08x mem_pending=%0d mem_rsp_valid=%0d mem_stall=%0d tx_state=%0d tx_count=%0d tx_done=%0d tx_error=%0d tx_write_ptr=%0d generator=%0d generated=%0d retry=%0d error=%0d pio_tx=%0d linkout=%0d drv_frames=%0d drv_errors=%0d drv_timeouts=%0d pool_free=%0d pool_ready=%0d pool_inflight=%0d pool_state_err=%0d",
                         uut.u_IF_Stage.pc,
                         uut.u_Mem_stage.EX_MEM_ALUResult,
                         uut.u_Mem_stage.mem_pending,
                         uut.u_Mem_stage.mem_rsp_valid,
                         uut.u_Mem_stage.mem_stall,
                         uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_state,
                         uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_count,
                         uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_done,
                         uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_error,
                         uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_write_ptr,
                         uut.u_Mem_stage.dm.u_data_ram.dm[32'hee44 >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[32'hee2c >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[32'hee24 >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[32'hee38 >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[32'h7b20 >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[32'hed80 >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(32'hed80 + 8) >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(32'hed80 + 16) >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(32'hed80 + 20) >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(32'h12240 + 8) >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(32'h12240 + 12) >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(32'h12240 + 16) >> 2],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(32'h12240 + 40) >> 2]);
                $fatal(1, "SEED=%0d TX timeout target=%0d actual=%0d",
                       seed, target_count, tx_frame_count);
            end
        end
    endtask

    task dump_input_frame;
        integer dump_index;
        begin
            $write("SEED=%0d INPUT_FRAME len=%0d bytes=", seed, input_len);
            for (dump_index = 0; dump_index < input_len; dump_index = dump_index + 1)
                $write("%02x", u_source.frame_bytes[dump_index]);
            $display("");
        end
    endtask

    task dump_last_tx_frame;
        integer dump_index;
        begin
            $write("SEED=%0d LAST_TX_FRAME len=%0d bytes=", seed, tx_last_len);
            for (dump_index = 0; dump_index < tx_last_len; dump_index = dump_index + 1)
                $write("%02x", tx_bytes[dump_index]);
            $display("");
        end
    endtask

    task send_positive_and_check;
        input integer kind;
        integer target_count;
        integer logical_len;
        integer payload_len;
        begin
            target_count = tx_frame_count + 1;
            if(kind==3)perf_begin();
            u_source.send_frame(input_len);
            wait_for_tx_frame(target_count);
            if(kind==3)perf_end("UDP_ECHO",tx_be16(38)-8,1);
            if (tx_last_len != expected_len) begin
                dump_input_frame();
                $fatal(1, "SEED=%0d kind=%0d reply length expected %0d got %0d",
                       seed, kind, expected_len, tx_last_len);
            end
            if (kind == 1) begin
                for (i = 0; i < expected_len; i = i + 1) begin
                    if (tx_bytes[i] !== expected_bytes[i]) begin
                        dump_input_frame();
                        $fatal(1, "SEED=%0d ARP byte[%0d] expected %02x got %02x",
                               seed, i, expected_bytes[i], tx_bytes[i]);
                    end
                end
            end else begin
                logical_len = tx_be16(16) + 14;
                payload_len = tx_be16(16) - 28;
                for (i = 0; i < 6; i = i + 1) begin
                    if ((tx_bytes[i] !== peer_mac[i]) ||
                        (tx_bytes[6 + i] !== ((i == 0) ? 8'h02 :
                         (i == 1) ? 8'h12 : (i == 2) ? 8'h34 :
                         (i == 3) ? 8'h56 : (i == 4) ? 8'h78 : 8'h9a))) begin
                        dump_input_frame();
                        dump_last_tx_frame();
                        $fatal(1, "SEED=%0d kind=%0d Ethernet MAC mismatch", seed, kind);
                    end
                end
                if ((tx_be16(12) != 16'h0800) || (tx_bytes[14] != 8'h45) ||
                    (tx_be32(26) != LOCAL_IP) || (tx_be32(30) != peer_ip) ||
                    (tx_checksum(14, 20) != 16'h0000))
                    $fatal(1, "SEED=%0d kind=%0d invalid IPv4 reply", seed, kind);

                if (kind == 2) begin
                    if ((tx_bytes[23] != 8'h01) || (tx_bytes[34] != 8'h00) ||
                        (tx_bytes[35] != 8'h00) ||
                        (tx_checksum(34, 8 + payload_len) != 16'h0000))
                        $fatal(1, "SEED=%0d invalid ICMP echo reply", seed);
                    for (i = 38; i < logical_len; i = i + 1)
                        if (tx_bytes[i] !== u_source.frame_bytes[i])
                            $fatal(1, "SEED=%0d ICMP payload byte[%0d] mismatch", seed, i);
                end else begin
                    if ((tx_bytes[23] != 8'h11) ||
                        (tx_be16(34) != 16'd1234) ||
                        (tx_be16(36) != ((u_source.frame_bytes[34] << 8) |
                                        u_source.frame_bytes[35])) ||
                        (tx_be16(38) != (8 + payload_len)) ||
                        !tx_udp_checksum_valid(8 + payload_len))
                        $fatal(1, "SEED=%0d invalid UDP echo reply", seed);
                    for (i = 42; i < logical_len; i = i + 1)
                        if (tx_bytes[i] !== u_source.frame_bytes[i])
                            $fatal(1, "SEED=%0d UDP payload byte[%0d] mismatch", seed, i);
                end
                for (i = logical_len; i < expected_len; i = i + 1)
                    if (tx_bytes[i] !== 8'h00)
                        $fatal(1, "SEED=%0d kind=%0d nonzero Ethernet pad", seed, kind);
            end
        end
    endtask

    task send_negative_and_check;
        input integer case_id;
        integer old_tx_count;
        integer old_rx_count;
        integer cycles;
        begin
            old_tx_count = tx_frame_count;
            old_rx_count = uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count;
            u_source.send_frame(input_len);
            cycles = 0;
            while ((uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count !=
                    (old_rx_count + 1)) && (cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (cycles >= MAX_WAIT_CYCLES) begin
                dump_input_frame();
                $fatal(1, "SEED=%0d negative case %0d RX timeout old=%0d actual=%0d ready=%0b cap=%0b",
                       seed, case_id, old_rx_count,
                       uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count,
                       uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_ready,
                       uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_capture_active);
            end
            cycles = 0;
            while (uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_ready &&
                   (cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (cycles >= MAX_WAIT_CYCLES) begin
                dump_input_frame();
                $fatal(1, "SEED=%0d negative case %0d was not cleared", seed, case_id);
            end
            repeat (2000) @(posedge clk);
            if (tx_frame_count != old_tx_count) begin
                dump_input_frame();
                dump_last_tx_frame();
                $fatal(1, "SEED=%0d negative case %0d produced a reply", seed, case_id);
            end
            if ((uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_drop_count !=
                 ((v31_mode && v40_checksum_mode) ? uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_drop_count : 0)) ||
                (uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_error_count != 0))
                $fatal(1, "SEED=%0d protocol packet incorrectly became stream error", seed);
            $display("PASS: SEED=%0d negative case %0d no reply and RX recovered",
                     seed, case_id);
        end
    endtask

    task run_async_udp_burst;
        localparam integer ASYNC_BURST_FRAMES = 8;
        integer old_tx_count;
        integer old_rx_count;
        integer burst_index;
        integer cycles;
        begin
            // Populate lwIP's ARP cache first; otherwise several UDP sends
            // legitimately collapse behind one unresolved ARP request.
            randomize_peer();
            build_arp();
            send_positive_and_check(1);
            old_tx_count = tx_frame_count;
            old_rx_count =
                uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count;
            for (burst_index = 0; burst_index < ASYNC_BURST_FRAMES;
                 burst_index = burst_index + 1) begin
                build_udp(64 + burst_index);
                u_source.send_frame(input_len);
            end
            cycles = 0;
            while (((tx_frame_count != (old_tx_count + ASYNC_BURST_FRAMES)) ||
                    (uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count !=
                     (old_rx_count + ASYNC_BURST_FRAMES))) &&
                   (cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (cycles >= MAX_WAIT_CYCLES)
                $fatal(1, "SEED=%0d asynchronous UDP burst timed out RX=%0d TX=%0d TX_H/T=%0d/%0d RX_H/T=%0d/%0d SG_STATE=%0d SG_ERR=%0d RX_FIFO=%0d TX_FIFO=%0d",
                       seed,
                       uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count,
                       tx_frame_count,
                       uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_head,
                       uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_tail,
                       uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_head,
                       uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail,
                       uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.state,
                       uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.global_error,
                       uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_fifo_count,
                       uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_fifo_count);
            $display("PASS: SEED=%0d asynchronous eight-frame UDP burst", seed);
        end
    endtask

    task wait_for_input_consumed;
        input integer old_rx_count;
        integer cycles;
        begin
            cycles = 0;
            while ((uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count !=
                    (old_rx_count + 1)) && (cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (cycles >= MAX_WAIT_CYCLES)
                $fatal(1, "SEED=%0d one-way input capture timeout", seed);
            cycles = 0;
            while (uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_ready &&
                   (cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (cycles >= MAX_WAIT_CYCLES)
                $fatal(1, "SEED=%0d one-way input consume timeout", seed);
        end
    endtask

    task build_tx_control;
        input integer start_command;
        integer command_length;
        begin
            command_length = start_command ? 7 : 9;
            build_udp(command_length);
            source_be16(34, 16'd4321);
            source_be16(40, 16'h0000);
            u_source.frame_bytes[42] = "V";
            u_source.frame_bytes[43] = "4";
            u_source.frame_bytes[44] = "0";
            u_source.frame_bytes[45] = "T";
            u_source.frame_bytes[46] = "X";
            if (start_command) begin
                u_source.frame_bytes[47] = "G";
                u_source.frame_bytes[48] = "O";
            end else begin
                u_source.frame_bytes[47] = "S";
                u_source.frame_bytes[48] = "T";
                u_source.frame_bytes[49] = "O";
                u_source.frame_bytes[50] = "P";
            end
        end
    endtask

    task run_v31_one_way_mode;
        integer old_tx_count;
        integer old_rx_count;
        integer target_tx_count;
        integer cycles;
        integer payload_index;
        reg [31:0] generated_sequence;
        begin
            randomize_peer();
            build_arp();
            send_positive_and_check(1);

            if (v40_tcp_rx_sink != 0) begin
                run_v40_tcp_sink_flow();
            end else if (v31_test_mode == 1) begin
                old_tx_count = tx_frame_count;
                old_rx_count =
                    uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count;
                build_udp(1472);
                target_tx_count=uut.u_Mem_stage.dm.u_data_ram.dm[sink_addr>>2];
                perf_begin();
                u_source.send_frame(input_len);
                wait_for_input_consumed(old_rx_count);
                cycles=0;
                while(uut.u_Mem_stage.dm.u_data_ram.dm[sink_addr>>2]==target_tx_count && cycles<MAX_WAIT_CYCLES)begin
                    @(posedge clk);cycles++;
                end
                if(cycles==MAX_WAIT_CYCLES)$fatal(1,"RX sink software completion timeout");
                perf_end("UDP_RX_ONLY",1472,1);
                repeat (10000) @(posedge clk);
                if (tx_frame_count != old_tx_count)
                    $fatal(1, "SEED=%0d RX-only sink emitted UDP reply", seed);
                $display("PASS: SEED=%0d V40 UDP RX-only sink consumed 1472-byte payload without reply",
                         seed);
            end else if (v31_test_mode == 2) begin
                old_rx_count =
                    uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count;
                build_tx_control(1);
                u_source.send_frame(input_len);
                wait_for_input_consumed(old_rx_count);

                target_tx_count = tx_frame_count + 4;
                wait_for_tx_frame(tx_frame_count+1);
                perf_begin();
                cycles = 0;
                while ((tx_frame_count < target_tx_count) &&
                       (cycles < MAX_WAIT_CYCLES)) begin
                    @(posedge clk);
                    cycles = cycles + 1;
                end
                if (cycles >= MAX_WAIT_CYCLES)
                    $fatal(1, "SEED=%0d TX-only generator timeout", seed);
                perf_end("UDP_TX_ONLY",1472,tx_frame_count-perf_tx_count);
                #1;
                if ((tx_last_len != 1514) || (tx_bytes[23] != 8'h11) ||
                    (tx_be16(34) != 16'd1234) ||
                    (tx_be16(36) != 16'd4321) ||
                    (tx_be16(38) != 16'd1480) ||
                    (tx_bytes[42] != "V") || (tx_bytes[43] != "4") ||
                    (tx_bytes[44] != "0") || (tx_bytes[45] != "T") ||
                    (tx_be32(46) != tx_be32(50)) ||
                    !tx_udp_checksum_valid(1480))
                    $fatal(1, "SEED=%0d invalid TX-only generated frame", seed);
                generated_sequence = {tx_bytes[49], tx_bytes[48],
                                      tx_bytes[47], tx_bytes[46]};
                for (payload_index = 12; payload_index < 1472;
                     payload_index = payload_index + 1) begin
                    if (tx_bytes[42 + payload_index] !==
                        ((generated_sequence + payload_index * 31 + 7) & 8'hff))
                        $fatal(1, "SEED=%0d TX realtime payload mismatch offset=%0d",
                               seed, payload_index);
                end

                old_rx_count =
                    uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count;
                build_tx_control(0);
                u_source.send_frame(input_len);
                wait_for_input_consumed(old_rx_count);
                repeat (20000) @(posedge clk);
                $display("PASS: SEED=%0d V40 UDP TX-only realtime pool generated validated 1472-byte payloads",
                         seed);
            end else if (v31_test_mode == 3) begin
                run_v40_tcp_source_flow();
            end else begin
                $fatal(1, "SEED=%0d unsupported one-way TEST_MODE=%0d",
                       seed, v31_test_mode);
            end

            if (halted)
                $fatal(1, "SEED=%0d one-way firmware halted", seed);
            if (uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_drop_count != 0 ||
                uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_error_count != 0)
                $fatal(1, "SEED=%0d one-way stream drop/error", seed);
            if ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_error_count +
                 uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_error_count) != 0)
                $fatal(1, "SEED=%0d one-way SGDMA error", seed);
            if ((v31_mode == 0) &&
                ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_desc_done +
                  uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done) != 0))
                $fatal(1, "SEED=%0d PIO one-way mode used SGDMA", seed);
            if ((v31_mode != 0) &&
                ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_desc_done +
                  uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done) == 0))
                $fatal(1, "SEED=%0d SGDMA one-way mode completed no descriptor", seed);
            if ((v31_mode != 0) && (cpu_tx_start_writes != 0))
                $fatal(1, "SEED=%0d SGDMA one-way mode used CPU TX START", seed);
            if ((v31_mode != 0) &&
                ((v31_test_mode == 2) || (v31_test_mode == 3))) begin
                $display("V40 TX POOL OBSERVED max_inflight=%0d max_ready=%0d producer_max_batch=%0d submit_max_batch=%0d reuse=%0d state_error=%0d generation_error=%0d",
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+7],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+6],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+17],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+23],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+8],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+10],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+11]);
                $display("V40 TX PRODUCER OBSERVED frames=%0d bytes=%0d ticks_hi=%08x ticks_lo=%08x",
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+13],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+14],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+16],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+15]);
                if (((v31_test_mode == 2) &&
                     (uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+7] < 4)) ||
                    ((v31_test_mode == 3) &&
                     (uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+7] < 2)))
                    $fatal(1, "SEED=%0d V40 TX pool did not create multiple inflight slots",
                           seed);
                if ((uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+10] != 0) ||
                    (uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+11] != 0))
                    $fatal(1, "SEED=%0d V40 TX pool ownership/generation error", seed);
                $display("PASS: SEED=%0d V40 TX pool max_inflight=%0d max_ready=%0d producer_max_batch=%0d submit_max_batch=%0d reuse=%0d",
                         seed,
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+7],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+6],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+17],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+23],
                         uut.u_Mem_stage.dm.u_data_ram.dm[(tx_stats_addr>>2)+8]);
            end
            $display("V40 NETWORK MODE PASSED test_mode=%0d io_mode=%0d descriptors=%0d tx=%0d rx=%0d",
                     v31_test_mode, v31_mode,
                      uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_desc_done +
                      uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done,
                      uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_desc_done,
                      uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done);
        end
    endtask

    initial begin
        reg [15:0] checksum;
        integer expected_rx_frames;

        seed = 1801;
        if (!$value$plusargs("SEED=%d", seed))
            seed = 1801;
`ifdef V27_SYNC_IMEM_SIM
        $display("V40 posedge synchronous-memory UDP/TCP network regression SEED=%0d", seed);
`elsif V26_TCP_ECHO_SIM
        $display("V26 lwIP UDP/TCP network regression SEED=%0d", seed);
`else
        $display("V29 SoC network regression SEED=%0d", seed);
`endif
        data_rng = seed ^ 32'h18a55a3c;
        ready_rng = seed ^ 32'hc001d00d;
        rst_n = 1'b0;
        tx_ready = 1'b0;
        for (i = 0; i < MAX_FRAME_BYTES; i = i + 1) begin
            tx_bytes[i] = 8'd0;
            expected_bytes[i] = 8'd0;
        end
        repeat (10) @(posedge clk);
        #1 rst_n = 1'b1;
        u_source.configure_random_gaps(1, seed ^ 32'h5eed1800);
        wait_for_firmware_ready();
`ifdef V31_SGDMA_SIM
        check_v40_initial_rx_prepost();
`endif

        // netif_set_up() emits one gratuitous ARP.  The asynchronous SGDMA
        // driver is allowed to mark firmware ready before that queued frame
        // reaches the stream, so establish a quiet baseline explicitly.
        begin
            integer startup_cycles;
            startup_cycles = 0;
            while ((tx_frame_count < 1) &&
                   (startup_cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                startup_cycles = startup_cycles + 1;
            end
            if (tx_frame_count != 1)
                $fatal(1, "SEED=%0d missing startup gratuitous ARP", seed);
`ifdef V31_SGDMA_SIM
            if ((v31_mode != 0) &&
                ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail -
                  uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_head) !=
                 v40_initial_rx_pending))
                $fatal(1, "V40 waiting RX prepost blocked TX or lost pending descriptors");
`endif
        end

`ifdef V31_SGDMA_SIM
        if ((v31_test_mode != 0) || (v40_tcp_rx_sink != 0)) begin
            run_v31_one_way_mode();
            $finish;
        end
`endif

        // Nine well-formed protocol frames that must be consumed and cleared
        // without a reply. Each is followed later by legal pressure traffic.
        randomize_peer(); build_icmp(16); u_source.frame_bytes[0] = 8'h06;
        send_negative_and_check(1); // non-local destination MAC

        randomize_peer(); build_icmp(17); source_be32(30, 32'hc0a80177);
        source_be16(24, 16'h0000); checksum = source_checksum(14, 20);
        source_be16(24, checksum); send_negative_and_check(2); // non-local IP

        randomize_peer(); build_arp(); source_be16(20, 16'h0002);
        send_negative_and_check(3); // ARP reply

        randomize_peer(); build_arp(); source_be32(38, 32'hc0a80177);
        send_negative_and_check(4); // ARP request for another target

        randomize_peer(); build_udp(19); source_be16(40, 16'h0001);
        send_negative_and_check(5); // invalid nonzero UDP checksum

        randomize_peer(); build_icmp(18); source_be16(12, 16'h88b5);
        send_negative_and_check(6); // unsupported EtherType

        randomize_peer(); build_icmp(19); u_source.frame_bytes[24] = u_source.frame_bytes[24] ^ 8'h01;
        send_negative_and_check(7); // bad IPv4 checksum

        randomize_peer(); build_icmp(20); u_source.frame_bytes[36] = u_source.frame_bytes[36] ^ 8'h01;
        send_negative_and_check(8); // bad ICMP checksum

        randomize_peer(); build_udp(21); source_be16(16, 16'd200);
        source_be16(24, 16'h0000); checksum = source_checksum(14, 20);
        source_be16(24, checksum); send_negative_and_check(9); // malformed IP length

        randomize_peer();build_tcp(16'h9000,32'h12345678,0,8'h02,0);
        u_source.frame_bytes[50]^=8'h01;
        send_negative_and_check(10); // bad TCP checksum, never reaches listener

`ifdef V31_SGDMA_SIM
        if (v31_mode != 0)
            run_async_udp_burst();
`endif

        // Multi-round randomized ARP, ICMP, and UDP pressure. Payload lengths
        // cover padding and several final-word empty values.
        for (round = 0; round < 4; round = round + 1) begin
            randomize_peer();
            build_arp();
            send_positive_and_check(1);
            build_icmp(11 + (round * 17));
            send_positive_and_check(2);
            build_udp(5 + (round * 23));
            send_positive_and_check(3);
            $display("PASS: SEED=%0d randomized round %0d lwIP ARP/ICMP/UDP",
                     seed, round);
        end

        // A 1472-byte UDP payload creates a 1514-byte Ethernet frame. V40 must
        // receive it in one 1536-byte pool pbuf; generic multi-segment SGDMA is
        // still covered by tb_v40_sgdma_gather_scatter.
        build_udp(1472);
        send_positive_and_check(3);
        $display("PASS: SEED=%0d 1514-byte Ethernet frame in one RX pbuf", seed);
        build_udp(64);send_positive_and_check(3);
        build_udp(7);source_be16(40,0);send_positive_and_check(3); // IPv4 UDP NOT_PRESENT

`ifdef V26_TCP_ECHO_SIM
        run_tcp_echo_flow();
`endif

`ifdef V31_SGDMA_SIM
        // The profiling build executes extra counter/UART instructions.  Do
        // not sample the asynchronous RX refill watermark exactly two clocks
        // after the last protocol transaction; wait for the service loop to
        // restore it, but retain a hard timeout and the final equality check.
        if (v31_mode != 0) begin : wait_for_v40_rx_refill
            integer refill_cycles;
            refill_cycles = 0;
            while (((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail -
                     uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_head) !=
                    v40_initial_rx_pending) &&
                   (refill_cycles < MAX_WAIT_CYCLES)) begin
                @(posedge clk);
                refill_cycles = refill_cycles + 1;
            end
            if (refill_cycles >= MAX_WAIT_CYCLES)
                $fatal(1, "V40 RX posted descriptor waterline recovery timeout");
        end
`endif
        repeat (2) @(posedge clk);
        #1;
`ifndef V26_TCP_ECHO_SIM
        expected_rx_frames = 9 + 13;
        if (tx_frame_count != 14)
            $fatal(1, "SEED=%0d expected 1 gratuitous ARP plus 13 replies got %0d",
                   seed, tx_frame_count);
        if (uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count !=
            expected_rx_frames)
            $fatal(1, "SEED=%0d expected RX_COUNT=%0d got %0d", seed,
                   expected_rx_frames,
                   uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count);
        if (uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_count != 14)
            $fatal(1, "SEED=%0d RTL TX_COUNT expected 14 got %0d", seed,
                   uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_count);
`endif
        if ((uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_drop_count !=
             ((v31_mode && v40_checksum_mode) ? 5 : 0)) ||
            (uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_error_count != 0))
            $fatal(1, "SEED=%0d unexpected stream drop/error", seed);
        if (halted)
            $fatal(1, "SEED=%0d robust polling firmware halted unexpectedly", seed);

`ifdef V27_SYNC_IMEM_SIM
        $display("V40 LWIP ARP/ICMP/UDP/TCP PASSED: SEED=%0d RX=%0d TX=%0d DROP=0 ERROR=0",
                 seed,
                 uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count,
                 uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_count);
`elsif V26_TCP_ECHO_SIM
        $display("V26 LWIP ARP/ICMP/UDP/TCP PASSED: SEED=%0d RX=%0d TX=%0d DROP=0 ERROR=0",
                 seed,
                 uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.rx_count,
                 uut.u_Mem_stage.dm.u_tse_mac_wrapper.u_tse_stream_fifo_stub.tx_count);
`else
        $display("V25 LWIP NO_SYS ARP/ICMP/UDP PASSED: SEED=%0d RX=22 TX=14 DROP=0 ERROR=0",
                 seed);
`endif
`ifdef V31_SGDMA_SIM
        if ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_error_count +
             uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_error_count) !=
             ((v31_mode && v40_checksum_mode) ? 5 : 0))
            $fatal(1,"SGDMA descriptor/protocol errors");
`ifndef V34_BASELINE
        if(v31_mode && v40_checksum_mode) begin
            if(uut.u_Mem_stage.dm.u_packet_dma.csum_counters[0]==0 ||
               uut.u_Mem_stage.dm.u_packet_dma.csum_counters[1]==0 ||
               uut.u_Mem_stage.dm.u_packet_dma.csum_counters[11]==0 ||
               uut.u_Mem_stage.dm.u_packet_dma.csum_counters[5]!=1 ||
               uut.u_Mem_stage.dm.u_packet_dma.csum_counters[7]!=2 ||
               uut.u_Mem_stage.dm.u_packet_dma.csum_counters[8]!=1 ||
               uut.u_Mem_stage.dm.u_packet_dma.csum_counters[9]!=1 ||
               uut.u_Mem_stage.dm.u_packet_dma.csum_counters[10]!=1)
                $fatal(1,"V40 checksum good/bad/parse/patch counters incorrect");
            $display("V40 HW CHECKSUM VALIDATED TX=%0d RX=%0d PATCH_BYTES=%0d IP_BAD=1 L4_BAD=2 UNSUPPORTED=1 PARSE=1 UDP_ZERO=1",
                uut.u_Mem_stage.dm.u_packet_dma.csum_counters[0],uut.u_Mem_stage.dm.u_packet_dma.csum_counters[1],
                uut.u_Mem_stage.dm.u_packet_dma.csum_counters[11]);
        end else begin
            for(integer c=0;c<15;c=c+1)
                if(uut.u_Mem_stage.dm.u_packet_dma.csum_counters[c]!=0)
                    $fatal(1,"Software checksum mode used hardware checksum");
        end
`endif
        if ((v31_mode != 0) &&
            ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_desc_done +
              uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done) == 0))
            $fatal(1,"SGDMA mode did not complete descriptors");
        if ((v31_mode == 0) &&
            ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_desc_done +
              uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done) != 0))
            $fatal(1,"PIO unexpectedly used SGDMA");
        if ((v31_mode == 0) &&
            ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_frame_count +
              uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_frame_count +
              uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_segment_count +
              uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_segment_count) != 0))
            $fatal(1,"PIO unexpectedly changed V40 frame/segment counters");
        if ((v31_mode != 0) && (cpu_tx_start_writes != 0))
            $fatal(1,"SGDMA firmware incorrectly wrote TX_CMD.START");
        if ((v31_mode != 0) &&
            (uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_segment_count <
             uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_frame_count))
            $fatal(1,"V40 TX segment count was smaller than TX frame count");
        // Failed checksum/protocol descriptors are completed and counted as
        // segments, but are deliberately not completed frames.  Exclude those
        // injected negative cases when checking the normal one-pbuf RX path.
        if ((v31_mode != 0) &&
            ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_segment_count -
              uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_error_count) !=
             uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_frame_count))
            $fatal(1,"V40 normal RX traffic was not one descriptor per frame");
        if ((v31_mode != 0) &&
            (uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.max_rx_segments != 1))
            $fatal(1,"V40 normal RX traffic did not remain single-segment");
        if ((v31_mode != 0) && (v31_max_pending < 2))
            $fatal(1,"SGDMA firmware never had multiple pending descriptors");
        if ((v31_mode != 0) && (v31_max_pending < v40_initial_rx_pending))
            $fatal(1,"V40 RX prepost never reached its initial descriptor waterline");
        if ((v31_mode != 0) &&
            ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail -
              uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_head) !=
             v40_initial_rx_pending))
            $fatal(1,"V40 RX posted descriptor waterline did not recover");
        if ((v31_mode != 0) &&
            ((uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_tail_writes +
              uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail_writes) >=
             (uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_desc_done +
              uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done)))
            $fatal(1,"SGDMA firmware did not batch any TAIL doorbell");
        $display("V40 PIO/SGDMA ZERO-COPY ARP/ICMP/UDP/TCP PASSED mode=%0d descriptors=%0d tx=%0d rx=%0d cpu_tx_starts=%0d max_pending=%0d tail_writes=%0d",
                 v31_mode,
                 uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_desc_done +
                 uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done,
                 uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_desc_done,
                 uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done,
                 cpu_tx_start_writes, v31_max_pending,
                 uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.tx_tail_writes +
                 uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail_writes);
        if ((v31_mode != 0) && (v40_prepost_only != 0))
            $display("V40 RX ZERO-COPY PREPOST SIMULATION PASSED head=%0d tail=%0d done=%0d tail_writes=%0d max_pending=%0d",
                     uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_head,
                     uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail,
                     uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_desc_done,
                     uut.u_Mem_stage.dm.u_packet_dma.u_sgdma_descriptor_engine.rx_tail_writes,
                     v31_max_pending);
`endif
        $display("V40 CPU PERF cycles=%0d retired=%0d cpi_x1000=%0d load_use=%0d imem_wait=%0d dmem_wait=%0d mmio_wait=%0d branch_flush=%0d trap=%0d hold=%0d",
                 uut.perf_cycle_count,
                 uut.perf_retired_count,
                 (uut.perf_retired_count != 0) ?
                    ((uut.perf_cycle_count * 1000) / uut.perf_retired_count) : 0,
                 uut.perf_load_use_stall_cycles,
                 uut.perf_imem_wait_cycles,
                 uut.perf_dmem_wait_cycles,
                 uut.perf_mmio_wait_cycles,
                 uut.perf_branch_flush_count,
                 uut.perf_trap_count,
                 uut.perf_pipeline_hold_cycles);
        $finish;
    end

endmodule


