`include "tse_addr_map.svh"

// One-clock simple dual-port packet RAM.  The byte-enabled form is split into
// byte banks so Quartus can infer embedded memory for partial DMA writes.
module tse_packet_ram #(
    parameter integer DATA_WIDTH = 32,
    parameter integer DEPTH = 512,
    parameter integer ADDR_WIDTH = $clog2(DEPTH),
    parameter integer BYTE_ENABLE = 0
) (
    input clk,
    input write_en,
    input [ADDR_WIDTH-1:0] write_addr,
    input [DATA_WIDTH-1:0] write_data,
    input [DATA_WIDTH/8-1:0] write_byteena,
    input read_en,
    input [ADDR_WIDTH-1:0] read_addr,
    output logic [DATA_WIDTH-1:0] read_data
);
    (* ramstyle = "M9K, no_rw_check" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    genvar lane;
    genvar word_index;
    generate
        if (BYTE_ENABLE) begin : g_bytes
            for (lane = 0; lane < DATA_WIDTH/8; lane = lane + 1) begin : g_lane
                (* ramstyle = "M9K, no_rw_check" *) logic [7:0] bank [0:DEPTH-1];
                always_ff @(posedge clk) begin
                    if (write_en && write_byteena[lane])
                        bank[write_addr] <= write_data[lane*8 +: 8];
                    if (read_en)
                        read_data[lane*8 +: 8] <= bank[read_addr];
                end
                // synthesis translate_off
                for (word_index = 0; word_index < DEPTH; word_index = word_index + 1) begin : g_view
                    assign mem[word_index][lane*8 +: 8] = bank[word_index];
                end
                // synthesis translate_on
            end
        end else begin : g_words
            always_ff @(posedge clk) begin
                if (write_en)
                    mem[write_addr] <= write_data;
                if (read_en)
                    read_data <= mem[read_addr];
            end
        end
    endgenerate
endmodule

// V30 synchronous multi-frame TX/RX packet FIFO and Avalon-ST adapter.
//
// The historical module name is retained for board/MMIO/firmware compatibility.
// V29 stored one frame per direction; V30 stores FRAME_FIFO_DEPTH complete
// frames.  Frame pointers and word pointers are deliberately independent:
//
//   physical RAM word = frame_pointer * TXRX_MAX_WORDS + word_offset
//
// With the defaults, frame_pointer is 2 bits (slot 0..3), word_offset is
// 9 bits (word 0..511), and each TX/RX RAM contains 2048 words.  This is a
// one-clock FIFO, not an asynchronous FIFO, SGDMA, interrupt block or TSE IP.
module tse_stream_fifo_stub #(
    parameter integer TXRX_MAX_BYTES = 2048,
    parameter integer TXRX_MAX_WORDS = TXRX_MAX_BYTES / 4,
    parameter integer FRAME_FIFO_DEPTH = 4,
    parameter integer DMA_ENABLE = 0
)(
    input clk,
    input rst_n,

    input mem_write,
    input mem_read,
    input [31:0] addr,
    input [31:0] din,
    output logic [31:0] dout,

    output tx_fifo_empty,
    output tx_fifo_full,
    output rx_fifo_empty,
    output rx_fifo_full,

    output logic [31:0] tx_st_data,
    output logic [1:0] tx_st_empty,
    output logic tx_st_valid,
    output logic tx_st_startofpacket,
    output logic tx_st_endofpacket,
    input tx_st_ready,

    input [31:0] rx_st_data,
    input [1:0] rx_st_empty,
    input rx_st_valid,
    input rx_st_startofpacket,
    input rx_st_endofpacket,
    output logic rx_st_ready,

    input dma_lock,
    input dma_direction,
    input dma_commit,
    input dma_cancel,
    input dma_rx_pop,
    input dma_tx_autorun,
    input dma_mode_active,
    input [31:0] dma_length,
    input dma_req,
    input dma_write,
    input [10:0] dma_addr,
    input [31:0] dma_wdata,
    input [3:0] dma_byteena,
    output dma_ready,
    output logic dma_rvalid,
    output [31:0] dma_rdata,
    output dma_rx_available,
    output [15:0] dma_rx_length,
    output dma_tx_available,
    output dma_conflict
);
    localparam [31:0] STREAM_CTRL_ADDR       = `TSE_MMIO_STREAM_CTRL_ADDR;
    localparam [31:0] STREAM_STATUS_ADDR     = `TSE_MMIO_STREAM_STATUS_ADDR;
    localparam [31:0] TX_DATA_ADDR           = `TSE_MMIO_TX_DATA_ADDR;
    localparam [31:0] TX_LEN_ADDR            = `TSE_MMIO_TX_LEN_ADDR;
    localparam [31:0] TX_CMD_ADDR            = `TSE_MMIO_TX_CMD_ADDR;
    localparam [31:0] TX_STATUS_ADDR         = `TSE_MMIO_TX_STATUS_ADDR;
    localparam [31:0] TX_COUNT_ADDR          = `TSE_MMIO_TX_COUNT_ADDR;
    localparam [31:0] TX_DEBUG_WORDS_ADDR    = `TSE_MMIO_TX_DEBUG_WORDS_ADDR;
    localparam [31:0] TX_DEBUG_LAST_ADDR     = `TSE_MMIO_TX_DEBUG_LAST_ADDR;
    localparam [31:0] RX_DATA_ADDR           = `TSE_MMIO_RX_DATA_ADDR;
    localparam [31:0] RX_LEN_ADDR            = `TSE_MMIO_RX_LEN_ADDR;
    localparam [31:0] RX_CMD_ADDR            = `TSE_MMIO_RX_CMD_ADDR;
    localparam [31:0] RX_STATUS_ADDR         = `TSE_MMIO_RX_STATUS_ADDR;
    localparam [31:0] RX_COUNT_ADDR          = `TSE_MMIO_RX_COUNT_ADDR;
    localparam [31:0] RX_DEBUG_WORDS_ADDR    = `TSE_MMIO_RX_DEBUG_WORDS_ADDR;
    localparam [31:0] RX_DEBUG_LAST_ADDR     = `TSE_MMIO_RX_DEBUG_LAST_ADDR;
    localparam [31:0] RX_DROP_COUNT_ADDR     = `TSE_MMIO_RX_DROP_COUNT_ADDR;
    localparam [31:0] RX_ERROR_COUNT_ADDR    = `TSE_MMIO_RX_ERROR_COUNT_ADDR;

    localparam integer WORD_COUNT_W = $clog2(TXRX_MAX_WORDS + 1);
    localparam integer WORD_ADDR_W = $clog2(TXRX_MAX_WORDS);
    localparam integer FRAME_PTR_W = (FRAME_FIFO_DEPTH <= 2) ? 1 : $clog2(FRAME_FIFO_DEPTH);
    localparam integer FRAME_COUNT_W = $clog2(FRAME_FIFO_DEPTH + 1);
    localparam integer TOTAL_WORDS = FRAME_FIFO_DEPTH * TXRX_MAX_WORDS;
    localparam integer RAM_ADDR_W = $clog2(TOTAL_WORDS);
    localparam logic [WORD_COUNT_W-1:0] MAX_WORD_COUNT = TXRX_MAX_WORDS[WORD_COUNT_W-1:0];

    typedef enum logic [1:0] {
        TX_IDLE = 2'd0, TX_SEND = 2'd1, TX_DONE = 2'd2, TX_ERROR = 2'd3
    } tx_state_t;
    typedef enum logic [1:0] {
        RX_WAIT_SOP = 2'd0, RX_CAPTURE = 2'd1, RX_DROP = 2'd2
    } rx_state_t;

    function automatic [WORD_COUNT_W-1:0] words_for_len(input [15:0] len);
        reg [16:0] rounded_len;
        begin
            rounded_len = {1'b0, len} + 17'd3;
            words_for_len = rounded_len[WORD_COUNT_W+1:2];
        end
    endfunction

    function automatic [1:0] empty_for_len(input [15:0] len);
        begin
            case (len[1:0])
                2'd0: empty_for_len = 2'd0;
                2'd1: empty_for_len = 2'd3;
                2'd2: empty_for_len = 2'd2;
                default: empty_for_len = 2'd1;
            endcase
        end
    endfunction

    function automatic length_is_valid(input [15:0] len);
        begin
            length_is_valid = (len != 0) && (len <= TXRX_MAX_BYTES);
        end
    endfunction

    function automatic [FRAME_PTR_W-1:0] next_frame_ptr(
        input [FRAME_PTR_W-1:0] ptr
    );
        begin
            if (ptr == FRAME_FIFO_DEPTH - 1)
                next_frame_ptr = 0;
            else
                next_frame_ptr = ptr + 1'b1;
        end
    endfunction

    function automatic [RAM_ADDR_W-1:0] frame_word_addr(
        input [FRAME_PTR_W-1:0] frame,
        input [WORD_ADDR_W-1:0] word_offset
    );
        integer address_value;
        begin
            address_value = frame * TXRX_MAX_WORDS + word_offset;
            frame_word_addr = address_value[RAM_ADDR_W-1:0];
        end
    endfunction

    // Frame-level FIFO state.  Count disambiguates full from empty when the
    // circular pointers are equal.  Lifetime tx_count/rx_count remain separate.
    logic [FRAME_PTR_W-1:0] tx_wptr, tx_rptr, rx_wptr, rx_rptr;
    logic [FRAME_COUNT_W-1:0] tx_fifo_count, rx_fifo_count;
    logic [15:0] tx_slot_len [0:FRAME_FIFO_DEPTH-1];
    logic [WORD_COUNT_W-1:0] tx_slot_words [0:FRAME_FIFO_DEPTH-1];
    logic [15:0] rx_slot_len [0:FRAME_FIFO_DEPTH-1];
    logic [WORD_COUNT_W-1:0] rx_slot_words [0:FRAME_FIFO_DEPTH-1];
    logic [31:0] rx_slot_last [0:FRAME_FIFO_DEPTH-1];
    logic rx_slot_loopback [0:FRAME_FIFO_DEPTH-1];

    assign tx_fifo_empty = (tx_fifo_count == 0);
    assign tx_fifo_full = (tx_fifo_count == FRAME_FIFO_DEPTH);
    assign rx_fifo_empty = (rx_fifo_count == 0);
    assign rx_fifo_full = (rx_fifo_count == FRAME_FIFO_DEPTH);

    // Compatibility observation names used by the v29 regressions.
    wire rx_ready = !rx_fifo_empty;
    wire [15:0] rx_len = rx_ready ? rx_slot_len[rx_rptr] : 16'd0;
    wire [WORD_COUNT_W-1:0] rx_word_count =
        rx_ready ? rx_slot_words[rx_rptr] : {WORD_COUNT_W{1'b0}};
    wire rx_loopback_frame = rx_ready && rx_slot_loopback[rx_rptr];
    wire rx_length_ok = rx_ready;
    wire [31:0] rx_debug_last = rx_ready ? rx_slot_last[rx_rptr] : 0;

    tx_state_t tx_state, tx_next_state;
    logic [WORD_COUNT_W-1:0] tx_write_ptr, tx_word_index, tx_total_words;
    logic [15:0] tx_len, tx_active_len;
    logic [1:0] tx_last_empty;
    logic tx_pio_build_active, tx_done, tx_error, tx_length_ok, tx_overflow;
    logic tx_loopback_en, tx_loopback_done, tx_loopback_capture_ok;
    logic [31:0] tx_count, tx_debug_last;
    logic tx_ram_word_valid;

    rx_state_t rx_state;
    logic [WORD_COUNT_W-1:0] rx_write_ptr, rx_read_ptr;
    logic rx_read_pending, rx_data_ready, rx_read_done;
    logic [31:0] rx_data_hold;
    logic rx_overflow, rx_protocol_error, rx_drop_seen;
    logic [31:0] rx_count, rx_drop_count, rx_error_count;

    wire tx_busy = (tx_state == TX_SEND);
    wire tx_stream_active = tx_busy;
    wire rx_capture_active = (rx_state == RX_CAPTURE);
    wire rx_drop_active = (rx_state == RX_DROP);
    wire packet_locked = DMA_ENABLE && dma_lock;
    logic packet_locked_q;
    wire cpu_write_allowed = mem_write && !packet_locked && !dma_mode_active;

    assign dma_conflict = (packet_locked || dma_mode_active) &&
                          (mem_write || (mem_read && addr == RX_DATA_ADDR));
    assign dma_rx_available = rx_ready && !rx_read_pending && !rx_data_ready;
    assign dma_rx_length = rx_len;
    assign dma_tx_available = !tx_fifo_full && !tx_pio_build_active;
    assign dma_ready = packet_locked && rst_n && !dma_conflict &&
                       (dma_direction ? !tx_fifo_full : rx_ready);
    wire dma_fire = dma_req && dma_ready;

    wire tx_final_word = (tx_total_words != 0) &&
                         (tx_word_index == tx_total_words - 1'b1);
    wire tx_fire = tx_st_valid && tx_st_ready;
    wire rx_fire = rx_st_valid && rx_st_ready;
    wire [2:0] rx_last_valid_bytes = 3'd4 - {1'b0, rx_st_empty};
    wire rx_non_eop_empty_error = !rx_st_endofpacket && (rx_st_empty != 0);

    wire tx_clear_request = cpu_write_allowed &&
        (((addr == STREAM_CTRL_ADDR) && din[0]) ||
         ((addr == TX_CMD_ADDR) && din[1]));
    wire rx_flush_request = cpu_write_allowed &&
        (addr == STREAM_CTRL_ADDR) && din[1];
    wire rx_pop_request = cpu_write_allowed &&
        (addr == RX_CMD_ADDR) && din[0] && rx_ready;
    wire tx_start_request = cpu_write_allowed &&
        (addr == TX_CMD_ADDR) && !din[1] && din[0];
    wire tx_auto_start_request = dma_tx_autorun && !tx_fifo_empty &&
                                 (tx_state != TX_SEND);
    wire tx_launch_request = tx_start_request || tx_auto_start_request;

    wire tx_pio_frame_valid = tx_pio_build_active && !tx_fifo_full &&
        length_is_valid(tx_len) && (words_for_len(tx_len) <= tx_write_ptr) &&
        !tx_overflow;
    wire tx_queued_frame_valid = !tx_fifo_empty;
    wire tx_start_can_send = tx_pio_build_active ?
        tx_pio_frame_valid : tx_queued_frame_valid;
    wire [15:0] tx_start_len = tx_queued_frame_valid ?
        tx_slot_len[tx_rptr] : tx_len;
    wire [WORD_COUNT_W-1:0] tx_start_words = tx_queued_frame_valid ?
        tx_slot_words[tx_rptr] : words_for_len(tx_len);

    // A complete-frame pointer advances exactly once on these events.
    wire tx_dma_push = packet_locked && dma_direction && dma_commit &&
        !dma_cancel && !tx_fifo_full && length_is_valid(dma_length[15:0]);
    wire tx_pio_push = tx_start_request && tx_pio_frame_valid;
    wire tx_frame_push = tx_dma_push || tx_pio_push;
    wire tx_frame_pop = tx_fire && tx_final_word;

    wire rx_external_one_word_push = rx_fire && !rx_non_eop_empty_error &&
        (rx_state == RX_WAIT_SOP) && rx_st_startofpacket && rx_st_endofpacket;
    wire rx_external_multi_push = rx_fire && !rx_non_eop_empty_error &&
        (rx_state == RX_CAPTURE) && !rx_st_startofpacket &&
        rx_st_endofpacket && (rx_write_ptr < MAX_WORD_COUNT);
    wire rx_external_push = rx_external_one_word_push || rx_external_multi_push;
    wire [15:0] rx_external_len = rx_external_one_word_push ?
        {13'd0, rx_last_valid_bytes} :
        (({{(16-WORD_COUNT_W){1'b0}}, rx_write_ptr} << 2) +
         {13'd0, rx_last_valid_bytes});
    wire [WORD_COUNT_W-1:0] rx_external_words = rx_external_one_word_push ?
        {{(WORD_COUNT_W-1){1'b0}}, 1'b1} : rx_write_ptr + 1'b1;
    wire rx_loopback_push = tx_frame_pop && tx_loopback_en &&
        tx_loopback_capture_ok;
    wire rx_frame_push = rx_external_push || rx_loopback_push;
    wire rx_dma_pop = dma_rx_pop && packet_locked && !dma_direction && rx_ready;
    // In V34 dma_cancel is direction-qualified: TX discards an unpublished
    // build slot, while RX consumes one bad frame so it cannot block the FIFO.
    wire rx_dma_drop = dma_cancel && packet_locked && !dma_direction && rx_ready;
    wire rx_frame_pop = rx_pop_request || rx_dma_pop || rx_dma_drop;

    wire tx_prefetch_request =
        (tx_launch_request && (tx_state != TX_SEND) && tx_start_can_send) ||
        (tx_fire && !tx_final_word);
    wire rx_fetch_request = cpu_write_allowed && (addr == RX_CMD_ADDR) &&
        din[2] && !rx_read_pending && !rx_data_ready && rx_ready &&
        (rx_read_ptr < rx_word_count);

    // Flattened RAM ports: {slot, word} conceptually, multiplication is kept
    // explicit so a future non-power-of-two depth is still unambiguous.
    wire tx_ram_write_en = (dma_fire && dma_write) ||
        (cpu_write_allowed && (addr == TX_DATA_ADDR) &&
         (tx_state != TX_SEND) && !tx_fifo_full &&
         (tx_write_ptr < MAX_WORD_COUNT));
    wire [RAM_ADDR_W-1:0] tx_ram_write_addr = frame_word_addr(
        tx_wptr,
        packet_locked ? dma_addr[WORD_ADDR_W+1:2] :
                        tx_write_ptr[WORD_ADDR_W-1:0]
    );
    wire tx_ram_read_en = tx_prefetch_request;
    logic [RAM_ADDR_W-1:0] tx_ram_read_addr;
    wire [31:0] tx_ram_read_data;
    always_comb begin
        if (tx_launch_request)
            tx_ram_read_addr = frame_word_addr(tx_rptr, 0);
        else
            tx_ram_read_addr = frame_word_addr(
                tx_rptr, tx_word_index[WORD_ADDR_W-1:0] + 1'b1
            );
    end

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (rst_n && (tx_fifo_count > FRAME_FIFO_DEPTH))
            $fatal(1, "TX FIFO count exceeded depth");
        if (rst_n && (rx_fifo_count > FRAME_FIFO_DEPTH))
            $fatal(1, "RX FIFO count exceeded depth");
        if (rst_n && dma_mode_active && tx_start_request)
            $fatal(1, "CPU TX START accepted while SGDMA owns FIFO");
    end
    // synthesis translate_on

    wire rx_ram_read_en = rx_fetch_request || (dma_fire && !dma_write);
    wire [RAM_ADDR_W-1:0] rx_ram_read_addr = frame_word_addr(
        rx_rptr,
        packet_locked ? dma_addr[WORD_ADDR_W+1:2] :
                        rx_read_ptr[WORD_ADDR_W-1:0]
    );
    wire [31:0] rx_ram_read_data;
    assign dma_rdata = rx_ram_read_data;

    logic rx_ram_write_en;
    logic [RAM_ADDR_W-1:0] rx_ram_write_addr;
    logic [31:0] rx_ram_write_data;
    always_comb begin
        rx_ram_write_en = 1'b0;
        rx_ram_write_addr = 0;
        rx_ram_write_data = 0;
        if (tx_fire && tx_loopback_en && tx_loopback_capture_ok) begin
            rx_ram_write_en = 1'b1;
            rx_ram_write_addr = frame_word_addr(
                rx_wptr, tx_word_index[WORD_ADDR_W-1:0]
            );
            rx_ram_write_data = tx_ram_read_data;
        end else if (rx_fire && !rx_non_eop_empty_error) begin
            case (rx_state)
                RX_WAIT_SOP: begin
                    if (rx_st_startofpacket) begin
                        rx_ram_write_en = 1'b1;
                        rx_ram_write_addr = frame_word_addr(rx_wptr, 0);
                        rx_ram_write_data = rx_st_data;
                    end
                end
                RX_CAPTURE: begin
                    if (!rx_st_startofpacket &&
                        (rx_write_ptr < MAX_WORD_COUNT)) begin
                        rx_ram_write_en = 1'b1;
                        rx_ram_write_addr = frame_word_addr(
                            rx_wptr, rx_write_ptr[WORD_ADDR_W-1:0]
                        );
                        rx_ram_write_data = rx_st_data;
                    end
                end
                default: begin
                end
            endcase
        end
    end

    tse_packet_ram #(
        .DATA_WIDTH(32), .DEPTH(TOTAL_WORDS), .ADDR_WIDTH(RAM_ADDR_W),
        .BYTE_ENABLE(1)
    ) u_tx_packet_ram (
        .clk(clk), .write_en(tx_ram_write_en), .write_addr(tx_ram_write_addr),
        .write_data(packet_locked ? dma_wdata : din),
        .write_byteena(packet_locked ? dma_byteena : 4'b1111),
        .read_en(tx_ram_read_en), .read_addr(tx_ram_read_addr),
        .read_data(tx_ram_read_data)
    );

    tse_packet_ram #(
        .DATA_WIDTH(32), .DEPTH(TOTAL_WORDS), .ADDR_WIDTH(RAM_ADDR_W)
    ) u_rx_packet_ram (
        .clk(clk), .write_en(rx_ram_write_en), .write_addr(rx_ram_write_addr),
        .write_data(rx_ram_write_data), .write_byteena(4'b1111),
        .read_en(rx_ram_read_en), .read_addr(rx_ram_read_addr),
        .read_data(rx_ram_read_data)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_rvalid <= 1'b0;
            packet_locked_q <= 1'b0;
        end else begin
            dma_rvalid <= dma_fire && !dma_write;
            packet_locked_q <= packet_locked;
        end
    end

    always_comb begin
        tx_next_state = tx_state;
        case (tx_state)
            TX_SEND:  if (tx_frame_pop) tx_next_state = TX_DONE;
            TX_DONE:  tx_next_state = TX_IDLE;
            TX_ERROR: tx_next_state = TX_IDLE;
            default:  tx_next_state = TX_IDLE;
        endcase
        if (tx_clear_request)
            tx_next_state = TX_IDLE;
        else if (tx_launch_request && (tx_state != TX_SEND))
            tx_next_state = tx_start_can_send ? TX_SEND : TX_ERROR;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_wptr <= 0; tx_rptr <= 0; tx_fifo_count <= 0;
            rx_wptr <= 0; rx_rptr <= 0; rx_fifo_count <= 0;
            tx_state <= TX_IDLE;
            tx_write_ptr <= 0; tx_word_index <= 0; tx_total_words <= 0;
            tx_len <= 0; tx_active_len <= 0; tx_last_empty <= 0;
            tx_pio_build_active <= 0; tx_done <= 0; tx_error <= 0;
            tx_length_ok <= 0; tx_overflow <= 0;
            tx_loopback_en <= 0; tx_loopback_done <= 0;
            tx_loopback_capture_ok <= 0; tx_count <= 0;
            tx_debug_last <= 0; tx_ram_word_valid <= 0;
            rx_state <= RX_WAIT_SOP; rx_write_ptr <= 0; rx_read_ptr <= 0;
            rx_read_pending <= 0; rx_data_ready <= 0; rx_data_hold <= 0;
            rx_read_done <= 0; rx_overflow <= 0; rx_protocol_error <= 0;
            rx_drop_seen <= 0; rx_count <= 0; rx_drop_count <= 0;
            rx_error_count <= 0;
        end else begin
            tx_state <= tx_next_state;

            // TX frame queue: push/pop update count once per complete frame.
            if (tx_clear_request) begin
                tx_wptr <= 0;
                tx_rptr <= 0;
                tx_fifo_count <= 0;
            end else begin
                case ({tx_frame_push, tx_frame_pop})
                    2'b10: tx_fifo_count <= tx_fifo_count + 1'b1;
                    2'b01: tx_fifo_count <= tx_fifo_count - 1'b1;
                    default: tx_fifo_count <= tx_fifo_count;
                endcase
                if (tx_frame_push) tx_wptr <= next_frame_ptr(tx_wptr);
                if (tx_frame_pop) tx_rptr <= next_frame_ptr(tx_rptr);
            end
            if (tx_dma_push) begin
                tx_slot_len[tx_wptr] <= dma_length[15:0];
                tx_slot_words[tx_wptr] <= words_for_len(dma_length[15:0]);
            end else if (tx_pio_push) begin
                tx_slot_len[tx_wptr] <= tx_len;
                tx_slot_words[tx_wptr] <= words_for_len(tx_len);
            end

            // RX frame queue: STREAM_CTRL flushes all; RX_CMD.CLEAR pops one.
            if (rx_flush_request) begin
                rx_wptr <= 0;
                rx_rptr <= 0;
                rx_fifo_count <= 0;
            end else begin
                case ({rx_frame_push, rx_frame_pop})
                    2'b10: rx_fifo_count <= rx_fifo_count + 1'b1;
                    2'b01: rx_fifo_count <= rx_fifo_count - 1'b1;
                    default: rx_fifo_count <= rx_fifo_count;
                endcase
                if (rx_frame_push) rx_wptr <= next_frame_ptr(rx_wptr);
                if (rx_frame_pop) rx_rptr <= next_frame_ptr(rx_rptr);
            end
            if (rx_external_push) begin
                rx_slot_len[rx_wptr] <= rx_external_len;
                rx_slot_words[rx_wptr] <= rx_external_words;
                rx_slot_last[rx_wptr] <= rx_st_data;
                rx_slot_loopback[rx_wptr] <= 1'b0;
            end else if (rx_loopback_push) begin
                rx_slot_len[rx_wptr] <= tx_active_len;
                rx_slot_words[rx_wptr] <= tx_total_words;
                rx_slot_last[rx_wptr] <= tx_ram_read_data;
                rx_slot_loopback[rx_wptr] <= 1'b1;
            end

            if (tx_clear_request)
                tx_ram_word_valid <= 1'b0;
            else if (tx_prefetch_request)
                tx_ram_word_valid <= 1'b1;
            else if (tx_frame_pop)
                tx_ram_word_valid <= 1'b0;

            // One-cycle synchronous PIO RX read pipeline.
            if (rx_read_pending) begin
                rx_data_hold <= rx_ram_read_data;
                rx_data_ready <= 1'b1;
                rx_read_pending <= 1'b0;
                if (rx_read_ptr == rx_word_count - 1'b1)
                    rx_read_done <= 1'b1;
                rx_read_ptr <= rx_read_ptr + 1'b1;
            end
            if (mem_read && !packet_locked &&
                (addr == RX_DATA_ADDR) && rx_data_ready)
                rx_data_ready <= 1'b0;

            if (cpu_write_allowed) begin
                case (addr)
                    STREAM_CTRL_ADDR: begin
                        if (din[0]) begin
                            tx_write_ptr <= 0; tx_word_index <= 0;
                            tx_total_words <= 0; tx_len <= 0;
                            tx_active_len <= 0; tx_last_empty <= 0;
                            tx_pio_build_active <= 0; tx_done <= 0;
                            tx_error <= 0; tx_length_ok <= 0;
                            tx_overflow <= 0; tx_loopback_en <= 0;
                            tx_loopback_done <= 0;
                            tx_loopback_capture_ok <= 0;
                            tx_ram_word_valid <= 0;
                        end
                        if (din[1]) begin
                            rx_state <= RX_WAIT_SOP; rx_write_ptr <= 0;
                            rx_read_ptr <= 0; rx_read_pending <= 0;
                            rx_data_ready <= 0; rx_data_hold <= 0;
                            rx_read_done <= 0; rx_overflow <= 0;
                            rx_protocol_error <= 0; rx_drop_seen <= 0;
                        end
                    end
                    TX_DATA_ADDR: begin
                        if ((tx_state == TX_SEND) || tx_fifo_full) begin
                            tx_error <= 1'b1;
                        end else if (tx_write_ptr < MAX_WORD_COUNT) begin
                            tx_write_ptr <= tx_write_ptr + 1'b1;
                            tx_pio_build_active <= 1'b1;
                            tx_debug_last <= din;
                        end else begin
                            tx_overflow <= 1'b1;
                        end
                    end
                    TX_LEN_ADDR: tx_len <= din[15:0];
                    TX_CMD_ADDR: begin
                        if (din[1]) begin
                            tx_write_ptr <= 0; tx_word_index <= 0;
                            tx_total_words <= 0; tx_len <= 0;
                            tx_active_len <= 0; tx_last_empty <= 0;
                            tx_pio_build_active <= 0; tx_done <= 0;
                            tx_error <= 0; tx_length_ok <= 0;
                            tx_overflow <= 0; tx_loopback_en <= 0;
                            tx_loopback_done <= 0;
                            tx_loopback_capture_ok <= 0;
                            tx_ram_word_valid <= 0;
                        end else if (din[0] && (tx_state != TX_SEND)) begin
                            tx_done <= 1'b0;
                            tx_error <= !tx_start_can_send;
                            tx_loopback_done <= 1'b0;
                            tx_loopback_en <= din[2];
                            tx_loopback_capture_ok <= din[2] &&
                                !rx_fifo_full && !rx_capture_active &&
                                !rx_drop_active && !rx_fire;
                            tx_length_ok <= tx_start_can_send;
                            if (tx_start_can_send) begin
                                tx_word_index <= 0;
                                tx_total_words <= tx_start_words;
                                tx_active_len <= tx_start_len;
                                tx_last_empty <= empty_for_len(tx_start_len);
                                if (tx_pio_build_active) begin
                                    tx_pio_build_active <= 1'b0;
                                    tx_write_ptr <= 0;
                                end
                            end
                        end
                    end
                    RX_CMD_ADDR: begin
                        if (din[0]) begin
                            rx_read_ptr <= 0; rx_read_pending <= 0;
                            rx_data_ready <= 0; rx_data_hold <= 0;
                            rx_read_done <= 0; rx_overflow <= 0;
                            rx_protocol_error <= 0; rx_drop_seen <= 0;
                        end
                        if (din[1]) begin
                            rx_read_ptr <= 0; rx_read_pending <= 0;
                            rx_data_ready <= 0; rx_read_done <= 0;
                        end
                        if (din[2] && rx_fetch_request) begin
                            rx_read_pending <= 1'b1;
                            rx_data_ready <= 1'b0;
                        end
                    end
                    default: begin
                    end
                endcase
            end

            // SGDMA owns only committed queue entries. Autorun never publishes
            // a PIO staging buffer and never requires CPU TX_CMD.START.
            if (tx_auto_start_request && tx_start_can_send &&
                (tx_state != TX_SEND)) begin
                tx_done <= 1'b0;
                tx_error <= 1'b0;
                tx_loopback_done <= 1'b0;
                tx_loopback_en <= 1'b0;
                tx_loopback_capture_ok <= 1'b0;
                tx_length_ok <= 1'b1;
                tx_word_index <= 0;
                tx_total_words <= tx_start_words;
                tx_active_len <= tx_start_len;
                tx_last_empty <= empty_for_len(tx_start_len);
            end

            // DMA writes the tail slot but COMMIT alone publishes the frame.
            // CANCEL resets staging without moving tx_wptr or tx_fifo_count.
            if (packet_locked && dma_direction) begin
                if (!packet_locked_q || dma_cancel) begin
                    tx_write_ptr <= 0; tx_len <= 0;
                    tx_pio_build_active <= 0;
                    tx_overflow <= 0;
                end else begin
                    if (dma_fire && dma_write) begin
                        tx_write_ptr <=
                            {{(WORD_COUNT_W-WORD_ADDR_W){1'b0}},
                             dma_addr[WORD_ADDR_W+1:2]} + 1'b1;
                        tx_debug_last <= dma_wdata;
                    end
                    if (dma_commit) begin
                        tx_write_ptr <= words_for_len(dma_length[15:0]);
                        tx_len <= dma_length[15:0];
                        tx_length_ok <= length_is_valid(dma_length[15:0]);
                    end
                end
            end

            // External RX data is invisible until a legal complete EOP.
            if (rx_fire) begin
                if ((rx_state != RX_DROP) && rx_non_eop_empty_error) begin
                    rx_protocol_error <= 1'b1; rx_drop_seen <= 1'b1;
                    rx_drop_count <= rx_drop_count + 1'b1;
                    rx_error_count <= rx_error_count + 1'b1;
                    rx_write_ptr <= 0; rx_state <= RX_DROP;
                end else begin
                    case (rx_state)
                        RX_DROP: begin
                            if (rx_st_endofpacket) rx_state <= RX_WAIT_SOP;
                        end
                        RX_WAIT_SOP: begin
                            if (!rx_st_startofpacket) begin
                                rx_protocol_error <= 1'b1;
                                rx_drop_seen <= 1'b1;
                                rx_drop_count <= rx_drop_count + 1'b1;
                                rx_error_count <= rx_error_count + 1'b1;
                                if (!rx_st_endofpacket) rx_state <= RX_DROP;
                            end else if (rx_st_endofpacket) begin
                                rx_write_ptr <= 0;
                                rx_state <= RX_WAIT_SOP;
                            end else begin
                                rx_write_ptr <= 1;
                                rx_state <= RX_CAPTURE;
                            end
                        end
                        RX_CAPTURE: begin
                            if (rx_st_startofpacket) begin
                                rx_protocol_error <= 1'b1;
                                rx_drop_seen <= 1'b1;
                                rx_drop_count <= rx_drop_count + 1'b1;
                                rx_error_count <= rx_error_count + 1'b1;
                                rx_write_ptr <= 0;
                                rx_state <= rx_st_endofpacket ?
                                            RX_WAIT_SOP : RX_DROP;
                            end else if (rx_write_ptr < MAX_WORD_COUNT) begin
                                if (rx_st_endofpacket) begin
                                    rx_write_ptr <= 0;
                                    rx_state <= RX_WAIT_SOP;
                                end else begin
                                    rx_write_ptr <= rx_write_ptr + 1'b1;
                                end
                            end else begin
                                rx_overflow <= 1'b1;
                                rx_protocol_error <= 1'b1;
                                rx_drop_seen <= 1'b1;
                                rx_drop_count <= rx_drop_count + 1'b1;
                                rx_error_count <= rx_error_count + 1'b1;
                                rx_write_ptr <= 0;
                                rx_state <= rx_st_endofpacket ?
                                            RX_WAIT_SOP : RX_DROP;
                            end
                        end
                        default: rx_state <= RX_WAIT_SOP;
                    endcase
                end
            end

            if (rx_frame_push)
                rx_count <= rx_count + 1'b1;
            if (rx_dma_drop)
                rx_drop_count <= rx_drop_count + 1'b1;
            if (rx_frame_pop) begin
                rx_read_ptr <= 0; rx_read_pending <= 0;
                rx_data_ready <= 0; rx_data_hold <= 0;
                rx_read_done <= 0;
            end

            if (tx_fire && !tx_clear_request) begin
                if (tx_final_word) begin
                    tx_done <= 1'b1;
                    tx_count <= tx_count + 1'b1;
                    if (tx_loopback_capture_ok) begin
                        tx_loopback_done <= 1'b1;
                    end else if (tx_loopback_en) begin
                        rx_overflow <= 1'b1;
                        rx_drop_seen <= 1'b1;
                        rx_drop_count <= rx_drop_count + 1'b1;
                    end
                end else begin
                    tx_word_index <= tx_word_index + 1'b1;
                end
            end
        end
    end

    always_comb begin
        tx_st_valid = (tx_state == TX_SEND) && tx_ram_word_valid;
        tx_st_data = tx_st_valid ? tx_ram_read_data : 0;
        tx_st_startofpacket = tx_st_valid && (tx_word_index == 0);
        tx_st_endofpacket = tx_st_valid && tx_final_word;
        tx_st_empty = (tx_st_valid && tx_final_word) ? tx_last_empty : 2'd0;

        // Backpressure occurs at a frame boundary only when all four slots are
        // occupied.  RX_DROP remains ready so a rejected frame drains to EOP.
        rx_st_ready = rst_n &&
            ((rx_state == RX_DROP) || !rx_fifo_full) &&
            !(tx_stream_active && tx_loopback_en && tx_loopback_capture_ok);
    end

    always_comb begin
        dout = 0;
        if (mem_read) begin
            case (addr)
                STREAM_CTRL_ADDR: dout = 0;
                STREAM_STATUS_ADDR:
                    dout = {24'd0, 2'd0, tx_loopback_done, tx_stream_active,
                            rx_fifo_full, rx_fifo_empty,
                            tx_fifo_full, tx_fifo_empty};
                TX_LEN_ADDR: dout = {16'd0, tx_len};
                TX_STATUS_ADDR:
                    dout = {25'd0, tx_loopback_done, tx_stream_active,
                            tx_overflow, tx_length_ok, tx_error,
                            tx_done, tx_busy};
                TX_COUNT_ADDR: dout = tx_count;
                TX_DEBUG_WORDS_ADDR:
                    dout = {{(32-WORD_COUNT_W){1'b0}}, tx_write_ptr};
                TX_DEBUG_LAST_ADDR: dout = tx_debug_last;
                RX_DATA_ADDR: if (rx_data_ready && !packet_locked)
                                  dout = rx_data_hold;
                RX_LEN_ADDR: dout = {16'd0, rx_len};
                RX_STATUS_ADDR:
                    dout = {21'd0, rx_read_pending, rx_data_ready,
                            rx_drop_seen, rx_protocol_error,
                            rx_capture_active, rx_read_done, rx_loopback_frame,
                            rx_length_ok, rx_overflow, !rx_ready, rx_ready};
                RX_COUNT_ADDR: dout = rx_count;
                RX_DEBUG_WORDS_ADDR:
                    dout = {{(32-WORD_COUNT_W){1'b0}}, rx_word_count};
                RX_DEBUG_LAST_ADDR: dout = rx_debug_last;
                RX_DROP_COUNT_ADDR: dout = rx_drop_count;
                RX_ERROR_COUNT_ADDR: dout = rx_error_count;
                default: dout = 0;
            endcase
        end
    end
endmodule
