// V34 one-segment transfer engine. Descriptor-chain policy stays in the
// descriptor engine; this block only moves one byte-contiguous segment.
//
// RX (direction=0): packet RAM -> DMEM.
// TX (direction=1): DMEM -> packet RAM.
//
// Source and destination byte addresses may have any low two address bits.
// A beat is limited by the destination word boundary. If those bytes straddle
// two source words, two synchronous reads are combined before one byte-enabled
// destination write. There is still only one outstanding RAM read.
module dma_transfer_engine #(
    parameter integer TIMEOUT_CYCLES = 65536,
    parameter integer DMEM_BYTES = 131072,
    parameter integer PACKET_BYTES = 2048
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        job_valid,
    output logic        job_ready,
    input  logic        job_direction,
    input  logic [31:0] job_dmem_addr,
    input  logic [31:0] job_packet_offset,
    input  logic [31:0] job_length,
    input  logic        job_abort,
    input  logic [1:0]  job_conflict,
    output logic        job_busy,
    output logic        job_done,
    output logic        job_error,
    output logic [31:0] job_error_code,
    output logic [31:0] job_bytes_done,
    output logic        active_direction,
    output logic [31:0] active_dmem_addr,
    output logic [31:0] active_packet_offset,
    output logic [31:0] active_length,
    output logic        csum_beat_valid,
    output logic [31:0] csum_beat_data,
    output logic [3:0]  csum_beat_keep,
    output logic [31:0] csum_frame_offset,
    output logic        csum_direction,
    output logic        dm_req,
    output logic        dm_write,
    output logic [31:0] dm_addr,
    output logic [31:0] dm_wdata,
    output logic [3:0]  dm_byteena,
    input  logic        dm_ready,
    input  logic        dm_rvalid,
    input  logic [31:0] dm_rdata,
    output logic        pkt_req,
    output logic        pkt_write,
    output logic [10:0] pkt_addr,
    output logic [31:0] pkt_wdata,
    input  logic        pkt_ready,
    input  logic        pkt_rvalid,
    input  logic [31:0] pkt_rdata
);
    typedef enum logic [2:0] {
        IDLE, READ0_REQ, READ0_WAIT, READ1_REQ, READ1_WAIT,
        WRITE_REQ, FINISH
    } state_t;

    localparam logic [31:0] ENGINE_ERR_NONE = 0;
    localparam logic [31:0] ENGINE_ERR_CONFIG = 1;
    localparam logic [31:0] ENGINE_ERR_ABORT = 2;
    localparam logic [31:0] ENGINE_ERR_DMEM_CONFLICT = 3;
    localparam logic [31:0] ENGINE_ERR_PACKET_CONFLICT = 4;
    localparam logic [31:0] ENGINE_ERR_TIMEOUT = 5;

    state_t state;
    logic [31:0] current_src_addr, current_dst_addr;
    logic [31:0] read_word0, read_word1, watchdog;
    logic terminal_error;
    logic [31:0] terminal_error_code;

    logic rd_req, wr_req;
    logic [31:0] rd_addr, wr_addr, wr_data;
    logic rd_ready, rd_valid, wr_ready;
    logic [31:0] rd_data;
    logic [2:0] beat_bytes;
    logic [2:0] dst_word_room;
    logic [3:0] source_span;
    logic [63:0] source_window;
    logic [63:0] shifted_source;
    logic [3:0] write_byteena;

    wire [32:0] dmem_end = {1'b0, job_dmem_addr} +
                            {1'b0, job_length};
    wire [32:0] packet_end = {1'b0, job_packet_offset} +
                              {1'b0, job_length};
    wire config_valid = (job_length != 0) &&
                        (job_length <= PACKET_BYTES) &&
                        (dmem_end <= DMEM_BYTES) &&
                        (packet_end <= PACKET_BYTES);
    wire [31:0] remaining = active_length - job_bytes_done;
    wire need_second_source_word = source_span > 4;
    wire timed_out = job_busy && (watchdog == TIMEOUT_CYCLES - 1);
    wire stop_now = job_abort || (job_conflict != 0) || timed_out;

    function automatic [3:0] byte_mask(
        input logic [1:0] byte_offset,
        input logic [2:0] byte_count
    );
        logic [3:0] ones;
        begin
            case (byte_count)
                3'd1: ones = 4'b0001;
                3'd2: ones = 4'b0011;
                3'd3: ones = 4'b0111;
                default: ones = 4'b1111;
            endcase
            byte_mask = (ones << byte_offset);
        end
    endfunction

    always_comb begin
        dst_word_room = 3'd4 - {1'b0, current_dst_addr[1:0]};
        if (remaining < {29'd0, dst_word_room})
            beat_bytes = remaining[2:0];
        else
            beat_bytes = dst_word_room;
        source_span = {2'd0, current_src_addr[1:0]} + beat_bytes;
        source_window = {read_word1, read_word0};
        shifted_source = source_window >>
                         ({4'd0, current_src_addr[1:0]} << 3);
        wr_data = shifted_source[31:0] <<
                  ({4'd0, current_dst_addr[1:0]} << 3);
        write_byteena = byte_mask(current_dst_addr[1:0], beat_bytes);
    end

    assign job_ready = (state == IDLE);
    assign job_busy = (state != IDLE) && (state != FINISH);
    assign job_done = (state == FINISH) && !terminal_error;
    assign job_error = (state == FINISH) && terminal_error;
    assign job_error_code = terminal_error_code;

    always_comb begin
        rd_req = 1'b0;
        wr_req = 1'b0;
        rd_addr = {current_src_addr[31:2], 2'b00};
        if ((state == READ1_REQ) || (state == READ1_WAIT))
            rd_addr = {current_src_addr[31:2], 2'b00} + 32'd4;
        wr_addr = {current_dst_addr[31:2], 2'b00};
        if ((state == READ0_REQ) || (state == READ1_REQ))
            rd_req = 1'b1;
        if (state == WRITE_REQ)
            wr_req = 1'b1;
    end

    assign dm_req = job_busy && !stop_now &&
                    (active_direction ? rd_req : wr_req);
    assign dm_write = !active_direction && wr_req;
    assign dm_addr = active_direction ? rd_addr : wr_addr;
    assign dm_wdata = wr_data;
    assign dm_byteena = write_byteena;

    assign pkt_req = job_busy && !stop_now &&
                     (active_direction ? wr_req : rd_req);
    assign pkt_write = active_direction && wr_req;
    assign pkt_addr = active_direction ? wr_addr[10:0] : rd_addr[10:0];
    assign pkt_wdata = wr_data;

    assign rd_ready = active_direction ? dm_ready : pkt_ready;
    assign rd_valid = active_direction ? dm_rvalid : pkt_rvalid;
    assign rd_data = active_direction ? dm_rdata : pkt_rdata;
    assign wr_ready = active_direction ? pkt_ready : dm_ready;

    // Compact logical bytes, exactly once at the destination write handshake.
    // Unaligned source reads can overlap; they must NOT feed the checksum.
    assign csum_beat_valid = job_busy && !stop_now && wr_req && wr_ready;
    assign csum_beat_data = shifted_source[31:0];
    assign csum_beat_keep = byte_mask(2'd0, beat_bytes);
    assign csum_frame_offset = active_packet_offset + job_bytes_done;
    assign csum_direction = active_direction;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            active_direction <= 0;
            active_dmem_addr <= 0;
            active_packet_offset <= 0;
            active_length <= 0;
            current_src_addr <= 0;
            current_dst_addr <= 0;
            read_word0 <= 0;
            read_word1 <= 0;
            job_bytes_done <= 0;
            watchdog <= 0;
            terminal_error <= 0;
            terminal_error_code <= ENGINE_ERR_NONE;
        end else begin
            case (state)
                IDLE: begin
                    watchdog <= 0;
                    if (job_valid) begin
                        active_direction <= job_direction;
                        active_dmem_addr <= job_dmem_addr;
                        active_packet_offset <= job_packet_offset;
                        active_length <= job_length;
                        job_bytes_done <= 0;
                        read_word0 <= 0;
                        read_word1 <= 0;
                        terminal_error <= !config_valid;
                        terminal_error_code <= config_valid ?
                            ENGINE_ERR_NONE : ENGINE_ERR_CONFIG;
                        if (config_valid) begin
                            if (job_direction) begin
                                current_src_addr <= job_dmem_addr;
                                current_dst_addr <= job_packet_offset;
                            end else begin
                                current_src_addr <= job_packet_offset;
                                current_dst_addr <= job_dmem_addr;
                            end
                            state <= READ0_REQ;
                        end else begin
                            state <= FINISH;
                        end
                    end
                end

                FINISH: begin
                    state <= IDLE;
                    watchdog <= 0;
                end

                default: begin
                    if (stop_now) begin
                        terminal_error <= 1;
                        terminal_error_code <= job_abort ? ENGINE_ERR_ABORT :
                            job_conflict[0] ? ENGINE_ERR_DMEM_CONFLICT :
                            job_conflict[1] ? ENGINE_ERR_PACKET_CONFLICT :
                                              ENGINE_ERR_TIMEOUT;
                        watchdog <= 0;
                        state <= FINISH;
                    end else begin
                        watchdog <= watchdog + 1'b1;
                        case (state)
                            READ0_REQ: if (rd_req && rd_ready) begin
                                state <= READ0_WAIT;
                                watchdog <= 0;
                            end

                            READ0_WAIT: if (rd_valid) begin
                                read_word0 <= rd_data;
                                state <= need_second_source_word ?
                                         READ1_REQ : WRITE_REQ;
                                watchdog <= 0;
                            end

                            READ1_REQ: if (rd_req && rd_ready) begin
                                state <= READ1_WAIT;
                                watchdog <= 0;
                            end

                            READ1_WAIT: if (rd_valid) begin
                                read_word1 <= rd_data;
                                state <= WRITE_REQ;
                                watchdog <= 0;
                            end

                            WRITE_REQ: if (wr_req && wr_ready) begin
                                job_bytes_done <= job_bytes_done + beat_bytes;
                                watchdog <= 0;
                                if (remaining <= {29'd0, beat_bytes}) begin
                                    terminal_error <= 0;
                                    terminal_error_code <= ENGINE_ERR_NONE;
                                    state <= FINISH;
                                end else begin
                                    current_src_addr <= current_src_addr +
                                                        beat_bytes;
                                    current_dst_addr <= current_dst_addr +
                                                        beat_bytes;
                                    read_word0 <= 0;
                                    read_word1 <= 0;
                                    state <= READ0_REQ;
                                end
                            end

                            default: begin
                                terminal_error <= 1;
                                terminal_error_code <= ENGINE_ERR_TIMEOUT;
                                state <= FINISH;
                            end
                        endcase
                    end
                end
            endcase
        end
    end

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (rst_n && (state == WRITE_REQ)) begin
            if ((beat_bytes == 0) ||
                ({1'b0, current_dst_addr[1:0]} + beat_bytes > 4))
                $fatal(1, "V34 DMA generated an invalid destination beat");
            if (write_byteena == 0)
                $fatal(1, "V34 DMA generated an empty byte enable");
        end
    end
    // synthesis translate_on
endmodule
