`include "dma_addr_map.svh"

// V34 ready-aware dual-ring frame scheduler. A frame may span one or more
// descriptors. TX and RX retain independent monotonic HEAD/TAIL counters while
// sharing this FSM, one byte-accurate segment engine, and one DMEM Port B.
module sgdma_descriptor_engine #(
    parameter integer TIMEOUT_CYCLES = 65536,
    parameter integer DMEM_BYTES = 131072,
    parameter integer MAX_RING_SIZE = 64
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem_write,
    input  logic        mem_read,
    input  logic [31:0] addr,
    input  logic [31:0] din,
    output logic [31:0] dout,

    input  logic        tx_available,
    input  logic        rx_available,
    input  logic [15:0] rx_length,
    input  logic        finalize_ready,
    input  logic        descriptor_conflict,
    input  logic        payload_conflict,
    input  logic        packet_conflict,

    output logic        csum_start,
    output logic        csum_finish,
    output logic        csum_wait,
    output logic [31:0] csum_control,
    input  logic        csum_complete,
    input  logic        csum_error,
    input  logic [7:0]  csum_error_code,
    input  logic [15:0] csum_flags,

    output logic        job_valid,
    input  logic        job_ready,
    output logic        job_direction,
    output logic [31:0] job_dmem_addr,
    output logic [31:0] job_packet_offset,
    output logic [31:0] job_length,
    output logic        job_abort,
    input  logic        job_busy,
    input  logic        job_done,
    input  logic        job_error,
    input  logic [31:0] job_error_code,
    input  logic [31:0] job_bytes_done,

    output logic        desc_req,
    output logic        desc_write,
    output logic [31:0] desc_addr,
    output logic [31:0] desc_wdata,
    output logic [3:0]  desc_byteena,
    input  logic        desc_ready,
    input  logic        desc_rvalid,
    input  logic [31:0] desc_rdata,

    output logic        enabled,
    output logic        overall_busy,
    output logic        descriptor_lock_valid,
    output logic [31:0] descriptor_lock_addr,
    output logic [31:0] descriptor_lock_length,
    output logic        payload_lock_valid,
    output logic [31:0] payload_lock_addr,
    output logic [31:0] payload_lock_length,
    output logic        packet_lock,
    output logic        packet_direction,
    output logic [31:0] packet_length,
    output logic        packet_commit,
    output logic        packet_cancel,
    output logic        packet_rx_pop,
    output logic        tx_autorun
);
    typedef enum logic [3:0] {
        SG_DISABLED, SG_WAIT_WORK, SG_FETCH_REQ, SG_FETCH_WAIT,
        SG_VALIDATE, SG_WAIT_TX, SG_WAIT_RX, SG_JOB_START,
        SG_JOB_WAIT, SG_STATUS_WRITE, SG_OWN_CLEAR, SG_ERROR_PAUSED,
        SG_CSUM_WAIT
    } sg_state_t;

    sg_state_t state;
    logic [31:0] tx_desc_base, tx_ring_size, tx_head, tx_tail;
    logic [31:0] rx_desc_base, rx_ring_size, rx_head, rx_tail;
    logic selected_ring;
    logic last_grant;
    logic [1:0] fetch_word;
    logic [31:0] desc_buffer, desc_length, desc_control, desc_status;
    logic [31:0] current_desc_addr;
    logic [31:0] desc_watchdog;
    logic error_sticky, aborted_sticky, pause_after_completion;
    logic descriptor_job_conflict_pending;
    logic [7:0] global_error;
    logic [15:0] actual_length;
    logic frame_owned;
    logic chain_active, drain_chain, terminal_after_current;
    logic segment_last_short;
    logic recovery_cancel_pulse;
    logic [31:0] frame_offset, frame_total_length, frame_remaining;
    logic [15:0] frame_rx_length;
    logic [31:0] frame_segment_count;
    logic csum_enabled, csum_checked;

    logic [31:0] tx_desc_done, tx_byte_count, tx_error_count;
    logic [31:0] rx_desc_done, rx_byte_count, rx_error_count;
    logic [31:0] busy_cycles, idle_cycles, wait_tx_cycles, wait_rx_cycles;
    logic [31:0] fetch_cycles, writeback_cycles;
    logic [31:0] tx_tail_writes, rx_tail_writes;
    logic [31:0] tx_grants, rx_grants, both_ready_cycles;
    logic [1:0] last_error_ring;
    logic [31:0] last_error_desc;
    logic [31:0] tx_frame_count, rx_frame_count;
    logic [31:0] tx_segment_count, rx_segment_count;
    logic [31:0] chain_error_count, tx_cancel_count, rx_drop_count;
    logic [31:0] max_tx_segments, max_rx_segments;

    wire tx_size_valid = (tx_ring_size >= 4) &&
        (tx_ring_size <= MAX_RING_SIZE) &&
        ((tx_ring_size & (tx_ring_size - 1'b1)) == 0);
    wire rx_size_valid = (rx_ring_size >= 4) &&
        (rx_ring_size <= MAX_RING_SIZE) &&
        ((rx_ring_size & (rx_ring_size - 1'b1)) == 0);
    wire [32:0] tx_ring_end = {1'b0, tx_desc_base} +
                              ({1'b0, tx_ring_size} << 4);
    wire [32:0] rx_ring_end = {1'b0, rx_desc_base} +
                              ({1'b0, rx_ring_size} << 4);
    wire rings_overlap = ({1'b0, tx_desc_base} < rx_ring_end) &&
                         ({1'b0, rx_desc_base} < tx_ring_end);
    wire tx_config_valid = (tx_desc_base[3:0] == 0) && tx_size_valid &&
                           (tx_ring_end <= DMEM_BYTES);
    wire rx_config_valid = (rx_desc_base[3:0] == 0) && rx_size_valid &&
                           (rx_ring_end <= DMEM_BYTES);
    wire ring_config_valid = tx_config_valid && rx_config_valid &&
                             !rings_overlap;
    wire [31:0] tx_pending = tx_tail - tx_head;
    wire [31:0] rx_pending = rx_tail - rx_head;
    wire [31:0] tx_free_entries = tx_ring_size - tx_pending;
    wire [31:0] rx_free_entries = rx_ring_size - rx_pending;
    wire [31:0] tx_tail_delta = din - tx_tail;
    wire [31:0] rx_tail_delta = din - rx_tail;
    wire tx_tail_write_valid = enabled && tx_size_valid &&
        (tx_tail_delta <= tx_free_entries) &&
        ((din - tx_head) <= tx_ring_size);
    wire rx_tail_write_valid = enabled && rx_size_valid &&
        (rx_tail_delta <= rx_free_entries) &&
        ((din - rx_head) <= rx_ring_size);
    wire tx_eligible = enabled && (tx_pending != 0) && tx_available;
    wire rx_eligible = enabled && (rx_pending != 0) && rx_available;
    wire select_tx_next = tx_eligible &&
        (!rx_eligible || (last_grant == 1'b0));
    wire select_rx_next = rx_eligible &&
        (!tx_eligible || (last_grant == 1'b1));

    wire control_owned = desc_control[`SG_DESC_OWN_BIT];
    wire control_direction = desc_control[`SG_DESC_DIR_BIT];
    wire control_first = desc_control[`SG_DESC_FIRST_BIT];
    wire control_last = desc_control[`SG_DESC_LAST_BIT];
    wire [32:0] buffer_end = {1'b0, desc_buffer} + {1'b0, desc_length};
    wire buffer_overlaps_ring =
        (({1'b0, desc_buffer} < tx_ring_end) &&
         (buffer_end > {1'b0, tx_desc_base})) ||
        (({1'b0, desc_buffer} < rx_ring_end) &&
         (buffer_end > {1'b0, rx_desc_base}));
    wire common_desc_valid = control_owned && (desc_length != 0) &&
        (desc_length <= 2048) && (buffer_end <= DMEM_BYTES) &&
        !buffer_overlaps_ring;
    wire current_ring_has_next = selected_ring ?
        ((tx_head + 1'b1) != tx_tail) : ((rx_head + 1'b1) != rx_tail);
    wire [31:0] selected_ring_size = selected_ring ?
        tx_ring_size : rx_ring_size;
    wire segment_limit_hit = (frame_segment_count + 1'b1) >=
                             selected_ring_size;
    wire [31:0] rx_current_remaining = chain_active ?
        frame_remaining : {16'd0, rx_length};
    wire [31:0] rx_segment_length =
        (desc_length < rx_current_remaining) ? desc_length :
                                               rx_current_remaining;
    wire rx_last_too_small = control_last &&
                             (desc_length < rx_current_remaining);
    wire [31:0] next_desc_addr = selected_ring ?
        (tx_desc_base + (((tx_head + 1'b1) &
                          (tx_ring_size - 1'b1)) << 4)) :
        (rx_desc_base + (((rx_head + 1'b1) &
                          (rx_ring_size - 1'b1)) << 4));

    wire abort_cmd = mem_write && (addr == `SG_CTRL) &&
                     din[`SG_CTRL_ABORT_BIT];
    wire clear_cmd = mem_write && (addr == `SG_CTRL) &&
                     din[`SG_CTRL_CLEAR_STATUS_BIT];
    wire reset_ring_cmd = mem_write && (addr == `SG_CTRL) &&
                          din[`SG_CTRL_RESET_RING_BIT];
    wire active_state = (state != SG_DISABLED) &&
                        (state != SG_WAIT_WORK) &&
                        (state != SG_ERROR_PAUSED);
    wire descriptor_timed_out = active_state &&
        ((state == SG_FETCH_REQ) || (state == SG_FETCH_WAIT) ||
         (state == SG_STATUS_WRITE) || (state == SG_OWN_CLEAR)) &&
        (desc_watchdog == TIMEOUT_CYCLES - 1);
    wire success_completion = !desc_status[`SG_DESC_ERROR_BIT];
    wire need_checksum = control_last && success_completion &&
                         !drain_chain && csum_enabled && !csum_checked;
    assign csum_control = desc_control;
    assign csum_start = !abort_cmd && !descriptor_conflict &&
        (((state == SG_WAIT_TX) && tx_available) ||
         ((state == SG_WAIT_RX) && rx_available)) && |desc_control[7:5];
    assign csum_finish = (state == SG_STATUS_WRITE) && need_checksum && !abort_cmd;
    assign csum_wait = state == SG_CSUM_WAIT;
    wire final_success_pending = control_last && success_completion &&
                                 !drain_chain && !terminal_after_current;
    wire final_error_pending = (control_last || terminal_after_current) &&
                               (drain_chain || !success_completion);
    wire own_clear_can_issue = !final_success_pending || finalize_ready;
    wire own_clear_fire = (state == SG_OWN_CLEAR) && own_clear_can_issue &&
                          desc_req && desc_ready && !abort_cmd;
    wire frame_finalize_success = own_clear_fire && final_success_pending;
    wire frame_finalize_error = own_clear_fire && final_error_pending;

    function automatic [31:0] make_status(
        input [15:0] length_value,
        input [7:0] error_value,
        input [6:0] flag_value
    );
        begin
            make_status = {length_value, error_value, 1'b0, flag_value};
        end
    endfunction

    task automatic set_descriptor_error(
        input [7:0] code,
        input [6:0] flags,
        input [15:0] length_value
    );
        begin
            desc_status <= make_status(length_value, code,
                                       flags | 7'b0000010);
            global_error <= code;
            last_error_ring <= selected_ring ?
                               `SG_ERROR_RING_TX : `SG_ERROR_RING_RX;
            last_error_desc <= current_desc_addr;
            error_sticky <= 1'b1;
            pause_after_completion <= 1'b1;
        end
    endtask

    // Errors fully attributable to the fetched descriptor consume only that
    // item.  They are reported in STATUS and the per-ring counters, but must
    // not stall an otherwise runnable item in the opposite ring.
    task automatic set_item_error(
        input [7:0] code,
        input [6:0] flags,
        input [15:0] length_value
    );
        begin
            desc_status <= make_status(length_value, code,
                                       flags | 7'b0000010);
            global_error <= code;
            last_error_ring <= selected_ring ?
                               `SG_ERROR_RING_TX : `SG_ERROR_RING_RX;
            last_error_desc <= current_desc_addr;
            error_sticky <= 1'b1;
            pause_after_completion <= 1'b0;
        end
    endtask

    assign overall_busy = active_state;
    assign tx_autorun = enabled;
    assign job_valid = (state == SG_JOB_START);
    assign job_abort = abort_cmd || descriptor_conflict;
    assign packet_lock = frame_owned || recovery_cancel_pulse;
    assign packet_direction = selected_ring;
    assign packet_length = selected_ring ?
        (frame_total_length + {16'd0, actual_length}) :
        {16'd0, frame_rx_length};
    assign packet_commit = frame_finalize_success && selected_ring;
    assign packet_rx_pop = frame_finalize_success && !selected_ring;
    // dma_cancel means TX discard when direction=1 and RX drop when direction=0.
    assign packet_cancel = (frame_finalize_error && frame_owned) ||
                           recovery_cancel_pulse;

    assign descriptor_lock_length = 32'd16;

    always_comb begin
        desc_req = 0;
        desc_write = 0;
        desc_addr = current_desc_addr + ({30'd0, fetch_word} << 2);
        desc_wdata = 0;
        desc_byteena = 4'b1111;
        case (state)
            SG_FETCH_REQ: begin
                desc_req = 1;
                desc_write = 0;
            end
            SG_STATUS_WRITE: begin
                desc_req = !need_checksum;
                desc_write = 1;
                desc_addr = current_desc_addr + 12;
                desc_wdata = desc_status;
            end
            SG_OWN_CLEAR: begin
                desc_req = own_clear_can_issue && !abort_cmd;
                desc_write = 1;
                desc_addr = current_desc_addr + 8;
                desc_wdata = desc_control & 32'hffff_fffe;
            end
            default: begin
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= SG_DISABLED;
            enabled <= 0;
            tx_desc_base <= 0;
            tx_ring_size <= 0;
            tx_head <= 0;
            tx_tail <= 0;
            rx_desc_base <= 0;
            rx_ring_size <= 0;
            rx_head <= 0;
            rx_tail <= 0;
            selected_ring <= 0;
            last_grant <= 0;
            fetch_word <= 0;
            desc_buffer <= 0;
            desc_length <= 0;
            desc_control <= 0;
            desc_status <= 0;
            current_desc_addr <= 0;
            desc_watchdog <= 0;
            error_sticky <= 0;
            aborted_sticky <= 0;
            pause_after_completion <= 0;
            descriptor_job_conflict_pending <= 0;
            global_error <= `SG_ERR_NONE;
            actual_length <= 0;
            frame_owned <= 0;
            chain_active <= 0;
            drain_chain <= 0;
            terminal_after_current <= 0;
            segment_last_short <= 0;
            recovery_cancel_pulse <= 0;
            frame_offset <= 0;
            frame_total_length <= 0;
            frame_remaining <= 0;
            frame_rx_length <= 0;
            frame_segment_count <= 0;
            csum_enabled <= 0;
            csum_checked <= 0;
            descriptor_lock_valid <= 0;
            descriptor_lock_addr <= 0;
            payload_lock_valid <= 0;
            payload_lock_addr <= 0;
            payload_lock_length <= 0;
            job_direction <= 0;
            job_dmem_addr <= 0;
            job_packet_offset <= 0;
            job_length <= 0;
            tx_desc_done <= 0;
            tx_byte_count <= 0;
            tx_error_count <= 0;
            rx_desc_done <= 0;
            rx_byte_count <= 0;
            rx_error_count <= 0;
            busy_cycles <= 0;
            idle_cycles <= 0;
            wait_tx_cycles <= 0;
            wait_rx_cycles <= 0;
            fetch_cycles <= 0;
            writeback_cycles <= 0;
            tx_tail_writes <= 0;
            rx_tail_writes <= 0;
            tx_grants <= 0;
            rx_grants <= 0;
            both_ready_cycles <= 0;
            last_error_ring <= `SG_ERROR_RING_NONE;
            last_error_desc <= 0;
            tx_frame_count <= 0;
            rx_frame_count <= 0;
            tx_segment_count <= 0;
            rx_segment_count <= 0;
            chain_error_count <= 0;
            tx_cancel_count <= 0;
            rx_drop_count <= 0;
            max_tx_segments <= 0;
            max_rx_segments <= 0;
        end else begin
            if(csum_start) begin
                csum_enabled <= 1;
                csum_checked <= 0;
            end
            recovery_cancel_pulse <= 0;
            if (active_state) busy_cycles <= busy_cycles + 1'b1;
            else idle_cycles <= idle_cycles + 1'b1;
            if ((state == SG_WAIT_WORK) && (tx_pending != 0) && !tx_available)
                wait_tx_cycles <= wait_tx_cycles + 1'b1;
            if ((state == SG_WAIT_WORK) && (rx_pending != 0) && !rx_available)
                wait_rx_cycles <= wait_rx_cycles + 1'b1;
            if ((state == SG_WAIT_WORK) && tx_eligible && rx_eligible)
                both_ready_cycles <= both_ready_cycles + 1'b1;
            if ((state == SG_FETCH_REQ) || (state == SG_FETCH_WAIT))
                fetch_cycles <= fetch_cycles + 1'b1;
            if ((state == SG_STATUS_WRITE) || (state == SG_OWN_CLEAR))
                writeback_cycles <= writeback_cycles + 1'b1;

            if (clear_cmd) begin
                error_sticky <= 0;
                aborted_sticky <= 0;
                global_error <= `SG_ERR_NONE;
                last_error_ring <= `SG_ERROR_RING_NONE;
                last_error_desc <= 0;
                if (state == SG_ERROR_PAUSED) begin
                    if (frame_owned) begin
                        recovery_cancel_pulse <= 1;
                        chain_error_count <= chain_error_count + 1'b1;
                        if (selected_ring)
                            tx_cancel_count <= tx_cancel_count + 1'b1;
                        else
                            rx_drop_count <= rx_drop_count + 1'b1;
                    end
                    chain_active <= 0;
                    drain_chain <= 0;
                    terminal_after_current <= 0;
                    frame_owned <= 0;
                    payload_lock_valid <= 0;
                    descriptor_lock_valid <= 0;
                    state <= enabled ? SG_WAIT_WORK : SG_DISABLED;
                end
            end

            if (((state == SG_JOB_START) || (state == SG_JOB_WAIT)) &&
                descriptor_conflict)
                descriptor_job_conflict_pending <= 1'b1;

            if (mem_write && (addr == `SG_TX_DESC_BASE) && !enabled)
                tx_desc_base <= din;
            if (mem_write && (addr == `SG_TX_RING_SIZE) && !enabled)
                tx_ring_size <= din;
            if (mem_write && (addr == `SG_RX_DESC_BASE) && !enabled)
                rx_desc_base <= din;
            if (mem_write && (addr == `SG_RX_RING_SIZE) && !enabled)
                rx_ring_size <= din;

            if (reset_ring_cmd && !enabled && (state == SG_DISABLED)) begin
                tx_head <= 0;
                tx_tail <= 0;
                rx_head <= 0;
                rx_tail <= 0;
                last_grant <= 0;
                error_sticky <= 0;
                aborted_sticky <= 0;
                global_error <= `SG_ERR_NONE;
                last_error_ring <= `SG_ERROR_RING_NONE;
                last_error_desc <= 0;
                chain_active <= 0;
                drain_chain <= 0;
                terminal_after_current <= 0;
                frame_owned <= 0;
                frame_offset <= 0;
                frame_total_length <= 0;
                frame_remaining <= 0;
                frame_segment_count <= 0;
            end

            if (mem_write && (addr == `SG_TX_TAIL)) begin
                tx_tail_writes <= tx_tail_writes + 1'b1;
                if (tx_tail_write_valid) begin
                    tx_tail <= din;
                end else begin
                    error_sticky <= 1;
                    global_error <= `SG_ERR_BAD_TAIL;
                    last_error_ring <= `SG_ERROR_RING_TX;
                    last_error_desc <= tx_head;
                end
            end

            if (mem_write && (addr == `SG_RX_TAIL)) begin
                rx_tail_writes <= rx_tail_writes + 1'b1;
                if (rx_tail_write_valid) begin
                    rx_tail <= din;
                end else begin
                    error_sticky <= 1;
                    global_error <= `SG_ERR_BAD_TAIL;
                    last_error_ring <= `SG_ERROR_RING_RX;
                    last_error_desc <= rx_head;
                end
            end

            if (mem_write && (addr == `SG_CTRL) && !din[`SG_CTRL_ABORT_BIT] &&
                !din[`SG_CTRL_CLEAR_STATUS_BIT] &&
                !din[`SG_CTRL_RESET_RING_BIT]) begin
                if (din[`SG_CTRL_ENABLE_BIT] && !enabled) begin
                    if (ring_config_valid) begin
                        enabled <= 1;
                        state <= SG_WAIT_WORK;
                    end else begin
                        error_sticky <= 1;
                        if ((tx_desc_base[3:0] != 0) ||
                            (rx_desc_base[3:0] != 0))
                            global_error <= `SG_ERR_BAD_BASE;
                        else if (rings_overlap)
                            global_error <= `SG_ERR_OVERLAP;
                        else
                            global_error <= `SG_ERR_BAD_RING_SIZE;
                        last_error_ring <= rings_overlap ?
                            `SG_ERROR_RING_NONE : (!tx_config_valid ?
                            `SG_ERROR_RING_TX : `SG_ERROR_RING_RX);
                        state <= SG_ERROR_PAUSED;
                    end
                end else if (!din[`SG_CTRL_ENABLE_BIT] && enabled &&
                             (state == SG_WAIT_WORK) &&
                             (tx_head == tx_tail) && (rx_head == rx_tail)) begin
                    enabled <= 0;
                    state <= SG_DISABLED;
                end
            end

            if (descriptor_timed_out) begin
                error_sticky <= 1;
                global_error <= `SG_ERR_DESC_TIMEOUT;
                last_error_ring <= selected_ring ?
                    `SG_ERROR_RING_TX : `SG_ERROR_RING_RX;
                last_error_desc <= current_desc_addr;
                /* Keep frame ownership while paused. CLEAR emits exactly one
                   cancel/drop pulse before restarting at the current HEAD. */
                payload_lock_valid <= 0;
                descriptor_lock_valid <= 0;
                state <= SG_ERROR_PAUSED;
                desc_watchdog <= 0;
            end else if (abort_cmd && active_state &&
                         (state != SG_JOB_WAIT)) begin
                actual_length <= 0;
                desc_status <= make_status(0, `SG_ERR_ABORTED,
                                           7'b0000110);
                global_error <= `SG_ERR_ABORTED;
                error_sticky <= 1;
                aborted_sticky <= 1;
                drain_chain <= 1;
                terminal_after_current <= control_last ||
                                          !current_ring_has_next;
                pause_after_completion <= !control_last &&
                                          !current_ring_has_next;
                chain_error_count <= chain_error_count + 1'b1;
                state <= SG_STATUS_WRITE;
            end else begin
                case (state)
                    SG_DISABLED: desc_watchdog <= 0;

                    SG_WAIT_WORK: begin
                        csum_enabled <= 0;
                        csum_checked <= 0;
                        desc_watchdog <= 0;
                        frame_owned <= 0;
                        chain_active <= 0;
                        drain_chain <= 0;
                        terminal_after_current <= 0;
                        segment_last_short <= 0;
                        frame_offset <= 0;
                        frame_total_length <= 0;
                        frame_remaining <= 0;
                        frame_rx_length <= 0;
                        frame_segment_count <= 0;
                        payload_lock_valid <= 0;
                        descriptor_lock_valid <= 0;
                        if (select_tx_next || select_rx_next) begin
                            selected_ring <= select_tx_next;
                            job_direction <= select_tx_next;
                            current_desc_addr <= select_tx_next ?
                                (tx_desc_base +
                                 ((tx_head & (tx_ring_size - 1'b1)) << 4)) :
                                (rx_desc_base +
                                 ((rx_head & (rx_ring_size - 1'b1)) << 4));
                            descriptor_lock_addr <= select_tx_next ?
                                (tx_desc_base +
                                 ((tx_head & (tx_ring_size - 1'b1)) << 4)) :
                                (rx_desc_base +
                                 ((rx_head & (rx_ring_size - 1'b1)) << 4));
                            descriptor_lock_valid <= 1;
                            fetch_word <= 0;
                            desc_buffer <= 0;
                            desc_length <= 0;
                            desc_control <= 0;
                            desc_status <= 0;
                            actual_length <= 0;
                            pause_after_completion <= 0;
                            descriptor_job_conflict_pending <= 0;
                            if (select_tx_next)
                                tx_grants <= tx_grants + 1'b1;
                            else
                                rx_grants <= rx_grants + 1'b1;
                            state <= SG_FETCH_REQ;
                        end
                    end

                    SG_FETCH_REQ: begin
                        desc_watchdog <= desc_watchdog + 1'b1;
                        if (descriptor_conflict) begin
                            error_sticky <= 1;
                            global_error <= `SG_ERR_DESC_CONFLICT;
                            descriptor_lock_valid <= 0;
                            state <= SG_ERROR_PAUSED;
                        end else if (desc_req && desc_ready) begin
                            desc_watchdog <= 0;
                            state <= SG_FETCH_WAIT;
                        end
                    end

                    SG_FETCH_WAIT: begin
                        desc_watchdog <= desc_watchdog + 1'b1;
                        if (descriptor_conflict) begin
                            error_sticky <= 1;
                            global_error <= `SG_ERR_DESC_CONFLICT;
                            descriptor_lock_valid <= 0;
                            state <= SG_ERROR_PAUSED;
                        end else if (desc_rvalid) begin
                            case (fetch_word)
                                0: desc_buffer <= desc_rdata;
                                1: desc_length <= desc_rdata;
                                2: desc_control <= desc_rdata;
                                3: desc_status <= desc_rdata;
                            endcase
                            desc_watchdog <= 0;
                            if (fetch_word == 3) state <= SG_VALIDATE;
                            else begin
                                fetch_word <= fetch_word + 1'b1;
                                state <= SG_FETCH_REQ;
                            end
                        end
                    end

                    SG_VALIDATE: begin
                        actual_length <= 0;
                        terminal_after_current <= 0;
                        segment_last_short <= 0;
                        if (drain_chain) begin
                            set_item_error(`SG_ERR_CHAIN_ABORTED,
                                           7'b0000110, 0);
                            if (control_last)
                                terminal_after_current <= 1;
                            else if (!current_ring_has_next ||
                                     segment_limit_hit) begin
                                terminal_after_current <= 1;
                                pause_after_completion <= 1;
                                global_error <= !current_ring_has_next ?
                                    `SG_ERR_MISSING_LAST :
                                    `SG_ERR_CHAIN_TOO_LONG;
                            end
                            state <= SG_STATUS_WRITE;
                        end else if (!control_owned) begin
                            set_item_error(`SG_ERR_OWN, 7'b0100000, 0);
                            drain_chain <= !control_last;
                            terminal_after_current <= control_last ||
                                                      !current_ring_has_next;
                            pause_after_completion <= !control_last &&
                                                      !current_ring_has_next;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end else if (!chain_active && !control_first) begin
                            set_item_error(`SG_ERR_MISSING_FIRST,
                                           7'b0100000, 0);
                            drain_chain <= !control_last;
                            terminal_after_current <= control_last ||
                                                      !current_ring_has_next;
                            pause_after_completion <= !control_last &&
                                                      !current_ring_has_next;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end else if (chain_active && control_first) begin
                            set_item_error(`SG_ERR_UNEXPECTED_FIRST,
                                           7'b0100000, 0);
                            drain_chain <= !control_last;
                            terminal_after_current <= control_last ||
                                                      !current_ring_has_next;
                            pause_after_completion <= !control_last &&
                                                      !current_ring_has_next;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end else if (!control_first && |desc_control[17:5]) begin
                            set_item_error(`SG_ERR_CSUM_CONFIG,7'b0100000,0);
                            drain_chain <= !control_last;
                            terminal_after_current <= control_last || !current_ring_has_next;
                            pause_after_completion <= !control_last && !current_ring_has_next;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end else if (control_direction != selected_ring) begin
                            set_item_error(`SG_ERR_DIRECTION,
                                           7'b0100000, 0);
                            drain_chain <= !control_last;
                            terminal_after_current <= control_last ||
                                                      !current_ring_has_next;
                            pause_after_completion <= !control_last &&
                                                      !current_ring_has_next;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end else if (buffer_end > DMEM_BYTES) begin
                            set_item_error(`SG_ERR_BAD_BUFFER,
                                           7'b0100000, 0);
                            drain_chain <= !control_last;
                            terminal_after_current <= control_last ||
                                                      !current_ring_has_next;
                            pause_after_completion <= !control_last &&
                                                      !current_ring_has_next;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end else if ((desc_length == 0) ||
                                     (desc_length > 2048)) begin
                            set_item_error(`SG_ERR_BAD_LENGTH,
                                           7'b0100000, 0);
                            drain_chain <= !control_last;
                            terminal_after_current <= control_last ||
                                                      !current_ring_has_next;
                            pause_after_completion <= !control_last &&
                                                      !current_ring_has_next;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end else if (buffer_overlaps_ring) begin
                            set_item_error(`SG_ERR_OVERLAP,
                                           7'b0100000, 0);
                            drain_chain <= !control_last;
                            terminal_after_current <= control_last ||
                                                      !current_ring_has_next;
                            pause_after_completion <= !control_last &&
                                                      !current_ring_has_next;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end else if (!control_last &&
                                     (!current_ring_has_next ||
                                      segment_limit_hit)) begin
                            set_descriptor_error(!current_ring_has_next ?
                                `SG_ERR_MISSING_LAST :
                                `SG_ERR_CHAIN_TOO_LONG,
                                7'b0100000, 0);
                            drain_chain <= 1;
                            terminal_after_current <= 1;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end else if (selected_ring) begin
                            if ((frame_total_length + desc_length) > 2048) begin
                                set_item_error(`SG_ERR_FRAME_TOO_LARGE,
                                               7'b0100000, 0);
                                drain_chain <= !control_last;
                                terminal_after_current <= control_last;
                                chain_error_count <= chain_error_count + 1'b1;
                                state <= SG_STATUS_WRITE;
                            end else begin
                                job_dmem_addr <= desc_buffer;
                                job_packet_offset <= frame_offset;
                                job_length <= desc_length;
                                actual_length <= desc_length[15:0];
                                if (!chain_active) begin
                                    state <= SG_WAIT_TX;
                                end else begin
                                    payload_lock_valid <= 1;
                                    payload_lock_addr <= desc_buffer;
                                    payload_lock_length <= desc_length;
                                    state <= SG_JOB_START;
                                end
                            end
                        end else begin
                            job_dmem_addr <= desc_buffer;
                            job_packet_offset <= frame_offset;
                            if (!chain_active) begin
                                state <= SG_WAIT_RX;
                            end else if (frame_remaining == 0) begin
                                actual_length <= 0;
                                desc_status <= make_status(0, `SG_ERR_NONE,
                                                           7'b0000001);
                                state <= SG_STATUS_WRITE;
                            end else begin
                                job_length <= rx_segment_length;
                                segment_last_short <= rx_last_too_small;
                                payload_lock_valid <= 1;
                                payload_lock_addr <= desc_buffer;
                                payload_lock_length <= rx_segment_length;
                                state <= SG_JOB_START;
                            end
                        end
                    end

                    SG_WAIT_TX: begin
                        if (abort_cmd) begin
                            set_descriptor_error(`SG_ERR_ABORTED, 7'b0000110, 0);
                            aborted_sticky <= 1;
                            state <= SG_STATUS_WRITE;
                        end else if (tx_available) begin
                            frame_owned <= 1;
                            chain_active <= 1;
                            payload_lock_valid <= 1;
                            payload_lock_addr <= desc_buffer;
                            payload_lock_length <= desc_length;
                            state <= SG_JOB_START;
                        end
                    end

                    SG_WAIT_RX: begin
                        if (abort_cmd) begin
                            set_descriptor_error(`SG_ERR_ABORTED, 7'b0000110, 0);
                            aborted_sticky <= 1;
                            state <= SG_STATUS_WRITE;
                        end else if (rx_available) begin
                            frame_owned <= 1;
                            chain_active <= 1;
                            frame_rx_length <= rx_length;
                            frame_remaining <= {16'd0, rx_length};
                            job_length <= rx_segment_length;
                            segment_last_short <= rx_last_too_small;
                            payload_lock_valid <= 1;
                            payload_lock_addr <= desc_buffer;
                            payload_lock_length <= rx_segment_length;
                            state <= SG_JOB_START;
                        end
                    end

                    SG_JOB_START: begin
                        if (job_ready) state <= SG_JOB_WAIT;
                    end

                    SG_JOB_WAIT: begin
                        if (job_done) begin
                            actual_length <= job_bytes_done[15:0];
                            if (segment_last_short) begin
                                set_item_error(`SG_ERR_BUFFER_SMALL,
                                               7'b1000010,
                                               job_bytes_done[15:0]);
                                drain_chain <= 1;
                                chain_error_count <=
                                    chain_error_count + 1'b1;
                            end else begin
                                desc_status <= make_status(
                                    job_bytes_done[15:0], `SG_ERR_NONE,
                                    7'b0000001);
                            end
                            state <= SG_STATUS_WRITE;
                        end else if (job_error) begin
                            if (descriptor_job_conflict_pending ||
                                descriptor_conflict) begin
                                set_descriptor_error(`SG_ERR_DESC_CONFLICT,
                                                     7'b0010010,
                                                     job_bytes_done[15:0]);
                            end else if (abort_cmd || (job_error_code == 2)) begin
                                set_descriptor_error(`SG_ERR_ABORTED,
                                                     7'b0000110,
                                                     job_bytes_done[15:0]);
                                aborted_sticky <= 1;
                            end else if (payload_conflict ||
                                         (job_error_code == 3)) begin
                                set_descriptor_error(`SG_ERR_PAYLOAD_CONFLICT,
                                                     7'b0010010,
                                                     job_bytes_done[15:0]);
                            end else if (packet_conflict ||
                                         (job_error_code == 4)) begin
                                set_descriptor_error(`SG_ERR_PACKET_CONFLICT,
                                                     7'b0010010,
                                                     job_bytes_done[15:0]);
                            end else begin
                                set_descriptor_error(`SG_ERR_PAYLOAD_TIMEOUT,
                                                     7'b0001010,
                                                     job_bytes_done[15:0]);
                            end
                            drain_chain <= 1;
                            chain_error_count <= chain_error_count + 1'b1;
                            state <= SG_STATUS_WRITE;
                        end
                    end

                    SG_STATUS_WRITE: begin
                        desc_watchdog <= desc_watchdog + 1'b1;
                        if (need_checksum) begin
                            state <= SG_CSUM_WAIT;
                            desc_watchdog <= 0;
                        end else if (desc_req && desc_ready) begin
                            desc_watchdog <= 0;
                            state <= SG_OWN_CLEAR;
                        end
                    end

                    SG_CSUM_WAIT: begin
                        desc_watchdog <= desc_watchdog + 1'b1;
                        if(descriptor_conflict || payload_conflict || packet_conflict ||
                           desc_watchdog == TIMEOUT_CYCLES-1) begin
                            set_item_error(`SG_ERR_CSUM_PATCH,
                                (desc_watchdog == TIMEOUT_CYCLES-1) ? 7'b0001010 : 7'b0010010,
                                actual_length);
                            csum_checked <= 1;
                            desc_watchdog <= 0;
                            state <= SG_STATUS_WRITE;
                        end else if(csum_complete) begin
                            desc_status <= {actual_length, csum_flags | (csum_error ? 16'h0003 : 16'h0001)};
                            if(csum_error) begin
                                global_error <= csum_error_code;
                                error_sticky <= 1;
                                last_error_ring <= selected_ring ? `SG_ERROR_RING_TX : `SG_ERROR_RING_RX;
                                last_error_desc <= current_desc_addr;
                                pause_after_completion <= 0;
                            end
                            csum_checked <= 1;
                            desc_watchdog <= 0;
                            state <= SG_STATUS_WRITE;
                        end
                    end

                    SG_OWN_CLEAR: begin
                        desc_watchdog <= desc_watchdog + 1'b1;
                        if (own_clear_fire) begin
                            desc_watchdog <= 0;
                            if (selected_ring) begin
                                tx_head <= tx_head + 1'b1;
                                tx_desc_done <= tx_desc_done + 1'b1;
                                tx_segment_count <= tx_segment_count + 1'b1;
                                if (success_completion)
                                    tx_byte_count <= tx_byte_count + actual_length;
                                else
                                    tx_error_count <= tx_error_count + 1'b1;
                            end else begin
                                rx_head <= rx_head + 1'b1;
                                rx_desc_done <= rx_desc_done + 1'b1;
                                rx_segment_count <= rx_segment_count + 1'b1;
                                if (success_completion)
                                    rx_byte_count <= rx_byte_count + actual_length;
                                else
                                    rx_error_count <= rx_error_count + 1'b1;
                            end
                            payload_lock_valid <= 0;
                            descriptor_job_conflict_pending <= 0;
                            frame_segment_count <= frame_segment_count + 1'b1;

                            if (frame_finalize_success) begin
                                last_grant <= selected_ring;
                                if (selected_ring) begin
                                    tx_frame_count <= tx_frame_count + 1'b1;
                                    if ((frame_segment_count + 1'b1) >
                                        max_tx_segments)
                                        max_tx_segments <=
                                            frame_segment_count + 1'b1;
                                end else begin
                                    rx_frame_count <= rx_frame_count + 1'b1;
                                    if ((frame_segment_count + 1'b1) >
                                        max_rx_segments)
                                        max_rx_segments <=
                                            frame_segment_count + 1'b1;
                                end
                                frame_owned <= 0;
                                chain_active <= 0;
                                drain_chain <= 0;
                                terminal_after_current <= 0;
                                descriptor_lock_valid <= 0;
                                state <= SG_WAIT_WORK;
                            end else if (frame_finalize_error) begin
                                last_grant <= selected_ring;
                                if (frame_owned && selected_ring)
                                    tx_cancel_count <= tx_cancel_count + 1'b1;
                                if (frame_owned && !selected_ring)
                                    rx_drop_count <= rx_drop_count + 1'b1;
                                frame_owned <= 0;
                                chain_active <= 0;
                                drain_chain <= 0;
                                terminal_after_current <= 0;
                                descriptor_lock_valid <= 0;
                                if (pause_after_completion)
                                    state <= SG_ERROR_PAUSED;
                                else
                                    state <= SG_WAIT_WORK;
                            end else begin
                                if (success_completion && !drain_chain) begin
                                    frame_offset <= frame_offset +
                                                    {16'd0, actual_length};
                                    frame_total_length <= frame_total_length +
                                                          {16'd0, actual_length};
                                    if (!selected_ring)
                                        frame_remaining <= frame_remaining -
                                                           {16'd0, actual_length};
                                end
                                current_desc_addr <= next_desc_addr;
                                descriptor_lock_addr <= next_desc_addr;
                                descriptor_lock_valid <= 1;
                                fetch_word <= 0;
                                desc_buffer <= 0;
                                desc_length <= 0;
                                desc_control <= 0;
                                desc_status <= 0;
                                actual_length <= 0;
                                terminal_after_current <= 0;
                                segment_last_short <= 0;
                                state <= SG_FETCH_REQ;
                            end
                        end
                    end

                    SG_ERROR_PAUSED: begin
                        desc_watchdog <= 0;
                        frame_owned <= 0;
                        payload_lock_valid <= 0;
                        descriptor_lock_valid <= 0;
                    end

                    default: begin
                        global_error <= `SG_ERR_INTERNAL;
                        error_sticky <= 1;
                        state <= SG_ERROR_PAUSED;
                    end
                endcase
            end
        end
    end

    always_comb begin
        dout = 0;
        if (mem_read) begin
            case (addr)
                `SG_ID: dout = `SG_ID_VALUE;
                `SG_CTRL: dout = {31'd0, enabled};
                `SG_STATUS: dout = {24'd0, enabled, aborted_sticky,
                    error_sticky,
                    ((rx_pending != 0) && !rx_available),
                    ((tx_pending != 0) && !tx_available),
                    state == SG_WAIT_WORK, !active_state, active_state};
                `SG_ERROR: dout = {24'd0, global_error};
                `SG_ARB_STATE: dout = {29'd0, last_grant,
                    selected_ring, tx_eligible && rx_eligible};
                `SG_LAST_ERROR_RING: dout = {30'd0, last_error_ring};
                `SG_LAST_ERROR_DESC: dout = last_error_desc;
                `SG_TX_DESC_BASE: dout = tx_desc_base;
                `SG_TX_RING_SIZE: dout = tx_ring_size;
                `SG_TX_HEAD: dout = tx_head;
                `SG_TX_TAIL: dout = tx_tail;
                `SG_TX_DESC_DONE: dout = tx_desc_done;
                `SG_TX_BYTES: dout = tx_byte_count;
                `SG_TX_ERRORS: dout = tx_error_count;
                `SG_TX_TAIL_WRITES: dout = tx_tail_writes;
                `SG_RX_DESC_BASE: dout = rx_desc_base;
                `SG_RX_RING_SIZE: dout = rx_ring_size;
                `SG_RX_HEAD: dout = rx_head;
                `SG_RX_TAIL: dout = rx_tail;
                `SG_RX_DESC_DONE: dout = rx_desc_done;
                `SG_RX_BYTES: dout = rx_byte_count;
                `SG_RX_ERRORS: dout = rx_error_count;
                `SG_RX_TAIL_WRITES: dout = rx_tail_writes;
                `SG_BUSY_CYCLES: dout = busy_cycles;
                `SG_IDLE_CYCLES: dout = idle_cycles;
                `SG_WAIT_TX_CYCLES: dout = wait_tx_cycles;
                `SG_WAIT_RX_CYCLES: dout = wait_rx_cycles;
                `SG_DESC_FETCH_CYCLES: dout = fetch_cycles;
                `SG_DESC_WRITEBACK_CYCLES: dout = writeback_cycles;
                `SG_TX_GRANTS: dout = tx_grants;
                `SG_RX_GRANTS: dout = rx_grants;
                `SG_BOTH_READY_CYCLES: dout = both_ready_cycles;
                `SG_STATE: dout = {28'd0, state};
                `SG_CAPABILITY: dout = `SG_CAPABILITY_VALUE;
                `SG_TX_FRAME_COUNT: dout = tx_frame_count;
                `SG_RX_FRAME_COUNT: dout = rx_frame_count;
                `SG_TX_SEGMENT_COUNT: dout = tx_segment_count;
                `SG_RX_SEGMENT_COUNT: dout = rx_segment_count;
                `SG_CHAIN_ERROR_COUNT: dout = chain_error_count;
                `SG_TX_CANCEL_COUNT: dout = tx_cancel_count;
                `SG_RX_DROP_COUNT: dout = rx_drop_count;
                `SG_MAX_TX_SEGMENTS: dout = max_tx_segments;
                `SG_MAX_RX_SEGMENTS: dout = max_rx_segments;
                default: dout = 0;
            endcase
        end
    end

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if(rst_n && csum_start && !control_first) $fatal(1,"Checksum start without FIRST");
        if(rst_n && csum_finish && !control_last) $fatal(1,"Checksum finish without LAST");
        if(rst_n && csum_wait && !packet_lock) $fatal(1,"Checksum lost frame lock");
        if(rst_n && frame_finalize_success && csum_enabled && !csum_checked)
            $fatal(1,"Frame finalized before checksum completion");
        if (rst_n && enabled && (tx_pending > tx_ring_size))
            $fatal(1, "SGDMA TX pending exceeds configured ring size");
        if (rst_n && enabled && (rx_pending > rx_ring_size))
            $fatal(1, "SGDMA RX pending exceeds configured ring size");
        if (rst_n && ((state == SG_WAIT_TX) || (state == SG_WAIT_RX) ||
                      (state == SG_WAIT_WORK)) && desc_req)
            $fatal(1, "normal resource wait unexpectedly owns DMEM Port B");
        if (rst_n && own_clear_fire && final_success_pending &&
            !(packet_commit || packet_rx_pop))
            $fatal(1, "successful OWN clear lacks atomic frame finalize");
        if (rst_n && (packet_commit || packet_rx_pop) && !control_last)
            $fatal(1, "non-LAST descriptor finalized a frame");
        if (rst_n && packet_commit && packet_rx_pop)
            $fatal(1, "TX commit and RX pop asserted together");
        if (rst_n && chain_active && (job_direction != selected_ring))
            $fatal(1, "descriptor chain changed direction");
    end
    // synthesis translate_on

    wire unused_job_busy = job_busy;
    wire unused_common_desc_valid = common_desc_valid;
endmodule
