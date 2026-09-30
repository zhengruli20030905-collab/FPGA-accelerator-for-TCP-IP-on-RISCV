// V34 packet SGDMA top. The dual-ring chain scheduler is the only synthesized job
// source. This wrapper only integrates the scheduler, transfer engine and the
// single DMEM Port-B arbiter.
module packet_dma #(
    parameter integer TIMEOUT_CYCLES = 65536
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem_write,
    input  logic        mem_read,
    input  logic [31:0] addr,
    input  logic [31:0] din,
    output logic [31:0] dout,

    input  logic        rx_available,
    input  logic [15:0] rx_length,
    input  logic        tx_available,
    input  logic        descriptor_conflict,
    input  logic        payload_conflict,
    input  logic        packet_conflict,

    output logic        enabled,
    output logic        busy,
    output logic        dmem_access_active,
    output logic        descriptor_lock_valid,
    output logic [31:0] descriptor_lock_addr,
    output logic [31:0] descriptor_lock_length,
    output logic        payload_lock_valid,
    output logic [31:0] payload_lock_addr,
    output logic [31:0] payload_lock_length,
    output logic        packet_lock,
    output logic        direction,
    output logic [31:0] length,
    output logic        commit,
    output logic        cancel,
    output logic        rx_pop,
    output logic        tx_autorun,

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
    output logic [3:0]  pkt_byteena,
    input  logic        pkt_ready,
    input  logic        pkt_rvalid,
    input  logic [31:0] pkt_rdata
);
    logic job_valid, job_ready, job_direction, job_abort;
    logic [31:0] job_dmem_addr, job_packet_offset, job_length;
    logic job_busy, job_done, job_error;
    logic [31:0] job_error_code, job_bytes_done;
    logic active_direction;
    logic [31:0] active_dmem_addr, active_packet_offset, active_length;

    logic desc_req, desc_write, desc_ready, desc_rvalid;
    logic [31:0] desc_addr, desc_wdata, desc_rdata;
    logic [3:0] desc_byteena;
    logic xfer_dm_req, xfer_dm_write, xfer_dm_ready, xfer_dm_rvalid;
    logic [31:0] xfer_dm_addr, xfer_dm_wdata, xfer_dm_rdata;
    logic [3:0] xfer_dm_byteena;
    logic read_owner_desc;
    logic [31:0] scheduler_dout;
    logic xfer_pkt_req, xfer_pkt_write;
    logic [10:0] xfer_pkt_addr;
    logic [31:0] xfer_pkt_wdata;
    logic csum_start, csum_finish, csum_wait, csum_complete;
    logic [31:0] csum_control, csum_beat_data, csum_frame_offset;
    logic [3:0] csum_beat_keep;
    logic csum_beat_valid, csum_direction, csum_result_valid, csum_error;
    logic csum_busy, patch_ip, patch_l4;
    logic [7:0] csum_error_code;
    logic [15:0] csum_result_flags, csum_flags, ip_checksum, l4_checksum;
    logic [10:0] ip_patch_offset, l4_patch_offset, patch_byte_addr;
    logic [2:0] patch_index;
    logic [7:0] patch_byte;
    logic patch_req, patch_selected, patch_required, previous_csum_wait;
    logic [31:0] csum_counters[0:16];
    wire csum_stop = job_abort || descriptor_conflict || payload_conflict || packet_conflict || cancel;
    assign patch_required = patch_index<2 ? patch_ip : patch_l4;
    assign patch_selected = csum_wait && csum_result_valid && direction &&
                            !csum_error && patch_index<4;
    assign patch_req = patch_selected && patch_required && !csum_stop;
    assign patch_byte_addr = (patch_index<2 ? ip_patch_offset : l4_patch_offset)+{10'd0,patch_index[0]};
    assign patch_byte = patch_index<2 ? (patch_index[0] ? ip_checksum[7:0] : ip_checksum[15:8]) :
                                                     (patch_index[0] ? l4_checksum[7:0] : l4_checksum[15:8]);
    assign pkt_req = patch_req || xfer_pkt_req;
    assign pkt_write = patch_selected ? 1'b1 : xfer_pkt_write;
    assign pkt_addr = patch_selected ? {patch_byte_addr[10:2],2'b00} : xfer_pkt_addr;
    assign pkt_wdata = patch_selected ? ({24'd0,patch_byte} << {patch_byte_addr[1:0],3'b000}) : xfer_pkt_wdata;
    assign pkt_byteena = patch_selected ? (4'b0001 << patch_byte_addr[1:0]) : xfer_dm_byteena;
    assign csum_complete = csum_result_valid &&
        (!direction || csum_error || patch_index==4);
    assign csum_flags = csum_result_flags |
        ((direction && !csum_error && (patch_ip||patch_l4) && patch_index==4) ? 16'h2000 : 16'd0);
    always_comb begin
        dout=scheduler_dout;
        if(mem_read && addr>=32'h10004100 && addr<=32'h10004140 && addr[1:0]==0)
            dout=csum_counters[(addr-32'h10004100)>>2];
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            patch_index<=0; previous_csum_wait<=0;
            for(integer ci=0;ci<17;ci=ci+1) csum_counters[ci]<=0;
        end else begin
            previous_csum_wait<=csum_wait;
            // Counter 15 represents software fallback. The v40 policy never
            // falls back after a hardware-checksum job has started, so make
            // the architectural zero explicit on every clock. Assigning it
            // only in the asynchronous-reset branch made Quartus infer a
            // latch even though the intended value was a constant zero.
            csum_counters[15]<=32'd0;
            if(csum_start || csum_finish) patch_index<=0;
            else if(patch_selected && (!patch_required || (patch_req && pkt_ready))) patch_index<=patch_index+1'b1;
            if(csum_busy) csum_counters[13]<=csum_counters[13]+1'b1;
            if(csum_wait) csum_counters[14]<=csum_counters[14]+1'b1;
            if(patch_req && pkt_ready) csum_counters[11]<=csum_counters[11]+1'b1;
            if(previous_csum_wait && !csum_wait && !csum_complete) csum_counters[12]<=csum_counters[12]+1'b1;
            // Counter 15 is software fallback. Current policy is fail-closed
            // for unsupported packets; ARP bypass and SW mode are not fallback.
            // No fallback event exists in this implementation, so it stays 0.
            if(csum_wait && csum_complete && !csum_stop) begin
                csum_counters[16]<={16'd0,csum_flags};
                if(direction) begin
                    csum_counters[0]<=csum_counters[0]+1'b1;
                    if(patch_ip) csum_counters[2]<=csum_counters[2]+1'b1;
                    if(patch_l4) csum_counters[3]<=csum_counters[3]+1'b1;
                end else begin
                    csum_counters[1]<=csum_counters[1]+1'b1;
                    if(csum_flags[8]) csum_counters[4]<=csum_counters[4]+1'b1;
                    if(csum_error_code==27) csum_counters[5]<=csum_counters[5]+1'b1;
                    if(csum_flags[9]) csum_counters[6]<=csum_counters[6]+1'b1;
                    if(csum_error_code==28) csum_counters[7]<=csum_counters[7]+1'b1;
                    if(csum_flags[12]) csum_counters[8]<=csum_counters[8]+1'b1;
                end
                if(csum_flags[11]) csum_counters[9]<=csum_counters[9]+1'b1;
                if(csum_flags[14]) csum_counters[10]<=csum_counters[10]+1'b1;
            end
        end
    end
    internet_checksum_engine u_checksum (
        .clk(clk),.rst_n(rst_n),.frame_start(csum_start),
        .frame_cancel(cancel || commit || rx_pop),.frame_finish(csum_finish),
        .direction(direction),.control(csum_control),.frame_length(length),
        .beat_valid(csum_beat_valid),.beat_data(csum_beat_data),
        .beat_keep(csum_beat_keep),.beat_offset(csum_frame_offset),
        .result_valid(csum_result_valid),.result_error(csum_error),
        .error_code(csum_error_code),.result_flags(csum_result_flags),
        .patch_ip(patch_ip),.patch_l4(patch_l4),
        .ip_patch_offset(ip_patch_offset),.l4_patch_offset(l4_patch_offset),
        .ip_checksum(ip_checksum),.l4_checksum(l4_checksum),.busy(csum_busy)
    );

    wire select_desc = desc_req;
    wire simultaneous_request = desc_req && xfer_dm_req;
    wire dm_fire = dm_req && dm_ready;

    assign dm_req = desc_req || xfer_dm_req;
    assign dm_write = select_desc ? desc_write : xfer_dm_write;
    assign dm_addr = select_desc ? desc_addr : xfer_dm_addr;
    assign dm_wdata = select_desc ? desc_wdata : xfer_dm_wdata;
    assign dm_byteena = select_desc ? desc_byteena : xfer_dm_byteena;
    assign dmem_access_active = dm_req;
    assign desc_ready = dm_ready && select_desc && !simultaneous_request;
    assign xfer_dm_ready = dm_ready && !select_desc && !simultaneous_request;
    assign desc_rvalid = dm_rvalid && read_owner_desc;
    assign xfer_dm_rvalid = dm_rvalid && !read_owner_desc;
    assign desc_rdata = dm_rdata;
    assign xfer_dm_rdata = dm_rdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) read_owner_desc <= 1'b0;
        else if (dm_fire && !dm_write) read_owner_desc <= select_desc;
    end

    sgdma_descriptor_engine #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES))
    u_sgdma_descriptor_engine (
        .clk(clk), .rst_n(rst_n),
        .mem_write(mem_write), .mem_read(mem_read), .addr(addr), .din(din),
        .dout(scheduler_dout),
        .csum_start(csum_start),.csum_finish(csum_finish),.csum_wait(csum_wait),
        .csum_control(csum_control),.csum_complete(csum_complete),
        .csum_error(csum_error),.csum_error_code(csum_error_code),.csum_flags(csum_flags),
        .tx_available(tx_available), .rx_available(rx_available),
        .rx_length(rx_length), .finalize_ready(pkt_ready),
        .descriptor_conflict(descriptor_conflict),
        .payload_conflict(payload_conflict), .packet_conflict(packet_conflict),
        .job_valid(job_valid), .job_ready(job_ready),
        .job_direction(job_direction), .job_dmem_addr(job_dmem_addr),
        .job_packet_offset(job_packet_offset), .job_length(job_length),
        .job_abort(job_abort), .job_busy(job_busy), .job_done(job_done),
        .job_error(job_error), .job_error_code(job_error_code),
        .job_bytes_done(job_bytes_done),
        .desc_req(desc_req), .desc_write(desc_write), .desc_addr(desc_addr),
        .desc_wdata(desc_wdata), .desc_byteena(desc_byteena),
        .desc_ready(desc_ready), .desc_rvalid(desc_rvalid),
        .desc_rdata(desc_rdata),
        .enabled(enabled), .overall_busy(busy),
        .descriptor_lock_valid(descriptor_lock_valid),
        .descriptor_lock_addr(descriptor_lock_addr),
        .descriptor_lock_length(descriptor_lock_length),
        .payload_lock_valid(payload_lock_valid),
        .payload_lock_addr(payload_lock_addr),
        .payload_lock_length(payload_lock_length),
        .packet_lock(packet_lock), .packet_direction(direction),
        .packet_length(length), .packet_commit(commit),
        .packet_cancel(cancel), .packet_rx_pop(rx_pop),
        .tx_autorun(tx_autorun)
    );

    dma_transfer_engine #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES))
    u_dma_transfer_engine (
        .clk(clk), .rst_n(rst_n),
        .job_valid(job_valid), .job_ready(job_ready),
        .job_direction(job_direction), .job_dmem_addr(job_dmem_addr),
        .job_packet_offset(job_packet_offset), .job_length(job_length),
        .job_abort(job_abort),
        .job_conflict({packet_conflict, payload_conflict}),
        .job_busy(job_busy), .job_done(job_done), .job_error(job_error),
        .job_error_code(job_error_code), .job_bytes_done(job_bytes_done),
        .active_direction(active_direction),
        .active_dmem_addr(active_dmem_addr),
        .active_packet_offset(active_packet_offset),
        .active_length(active_length),
        .csum_beat_valid(csum_beat_valid),.csum_beat_data(csum_beat_data),
        .csum_beat_keep(csum_beat_keep),.csum_frame_offset(csum_frame_offset),
        .csum_direction(csum_direction),
        .dm_req(xfer_dm_req), .dm_write(xfer_dm_write),
        .dm_addr(xfer_dm_addr), .dm_wdata(xfer_dm_wdata),
        .dm_byteena(xfer_dm_byteena), .dm_ready(xfer_dm_ready),
        .dm_rvalid(xfer_dm_rvalid), .dm_rdata(xfer_dm_rdata),
        .pkt_req(xfer_pkt_req), .pkt_write(xfer_pkt_write), .pkt_addr(xfer_pkt_addr),
        .pkt_wdata(xfer_pkt_wdata), .pkt_ready(pkt_ready && !patch_selected),
        .pkt_rvalid(pkt_rvalid), .pkt_rdata(pkt_rdata)
    );

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if(rst_n && patch_req && xfer_pkt_req) $fatal(1,"Packet RAM dual owner");
        if(rst_n && patch_req && (!packet_lock || !direction || patch_byte_addr>=length))
            $fatal(1,"Checksum patch out of locked frame");
        if(rst_n && commit && csum_result_valid && (patch_ip||patch_l4) && patch_index!=4)
            $fatal(1,"Commit before checksum patch completion");
        if (rst_n && simultaneous_request)
            $fatal(1, "descriptor and payload requested DMEM simultaneously");
        if (rst_n && desc_rvalid && xfer_dm_rvalid)
            $fatal(1, "DMEM read response routed to two owners");
    end
    // synthesis translate_on

    wire unused_engine_observation = active_direction ^ active_dmem_addr[0] ^
        active_packet_offset[0] ^ active_length[0];
endmodule
