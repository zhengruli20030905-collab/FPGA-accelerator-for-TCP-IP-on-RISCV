// V35 frame-scoped Internet checksum observer. Lane 0 is first on the wire.
// Weighted byte contributions preserve odd-byte pairing across arbitrary
// segment boundaries: even REGION offset contributes byte<<8, odd contributes
// byte. No segment-local padding/fold and no frame payload storage are needed.
module internet_checksum_engine (
    input logic clk, rst_n,
    input logic frame_start, frame_cancel, frame_finish,
    input logic direction,
    input logic [31:0] control, frame_length,
    input logic beat_valid,
    input logic [31:0] beat_data, beat_offset,
    input logic [3:0] beat_keep,
    output logic result_valid, result_error,
    output logic [7:0] error_code,
    output logic [15:0] result_flags,
    output logic patch_ip, patch_l4,
    output logic [10:0] ip_patch_offset, l4_patch_offset,
    output logic [15:0] ip_checksum, l4_checksum,
    output logic busy
);
    localparam [15:0] DONE=16'h0080, IP_OK=16'h0100, L4_OK=16'h0200,
        BAD=16'h0400, UNSUPPORTED=16'h0800, UDP_ZERO=16'h1000,
        PARSE=16'h4000;
    typedef enum logic [2:0] {IDLE, STREAM, PSEUDO, FOLD1, FOLD2, RESULT} state_t;
    state_t state;
    typedef struct packed {
        logic [15:0] ethertype, total, frag, udp_length, udp_checksum;
        logic [7:0] version_ihl, protocol, tcp_offset;
        logic [31:0] source_ip, dest_ip;
        logic [31:0] seen;
        logic malformed;
    } header_t;
    header_t h, hn;
    logic tx, want_ip, want_l4, auto_parse;
    logic [1:0] expected_proto;
    logic [8:0] l3;
    logic [31:0] ip_sum, l4_sum, ip_fold, l4_fold;
    logic [15:0] ip_folded, l4_folded;
    logic [31:0] final_length;
    logic [17:0] ip_add, l4_add;
    logic [15:0] ip_part[0:3], l4_part[0:3];
    logic [31:0] off, relative_ip, relative_l4;
    logic [7:0] b, sum_byte;
    logic [15:0] header_bytes, l4_bytes;
    logic [31:0] l4_start;
    logic ipv4, is_udp, is_tcp, invalid, unsupported, config_error;
    integer lane;

    assign header_bytes = {10'd0,h.version_ihl[3:0],2'b00};
    assign l4_start = {23'd0,l3} + {16'd0,header_bytes};
    assign l4_bytes = is_udp ? h.udp_length : (h.total-header_bytes);
    assign ipv4 = h.ethertype == 16'h0800;
    assign is_udp = h.protocol == 17;
    assign is_tcp = h.protocol == 6;
    assign busy = state != IDLE && state != RESULT;
    assign result_valid = state == RESULT;
    assign ip_patch_offset = l3 + 11'd10;
    assign l4_patch_offset = l4_start[10:0] + (is_udp ? 11'd6 : 11'd16);

    // Parse in wire order, including fields arriving in the same beat.
    always_comb begin
        hn=h;
        off=0; relative_ip=0; relative_l4=0; b=0; sum_byte=0;
        for (lane=0; lane<4; lane=lane+1) begin
            ip_part[lane]=0; l4_part[lane]=0;
            if (beat_keep[lane]) begin
                off=beat_offset+lane;
                b=beat_data[lane*8 +: 8];
                if (off != hn.seen) hn.malformed=1;
                hn.seen=hn.seen+1'b1;
                if(off==12) hn.ethertype[15:8]=b;
                if(off==13) hn.ethertype[7:0]=b;
                relative_ip=off-{23'd0,l3};
                if(off >= {23'd0,l3}) begin
                    case(relative_ip)
                        0: hn.version_ihl=b;
                        2: hn.total[15:8]=b;
                        3: hn.total[7:0]=b;
                        6: hn.frag[15:8]=b;
                        7: hn.frag[7:0]=b;
                        9: hn.protocol=b;
                        12: hn.source_ip[31:24]=b;
                        13: hn.source_ip[23:16]=b;
                        14: hn.source_ip[15:8]=b;
                        15: hn.source_ip[7:0]=b;
                        16: hn.dest_ip[31:24]=b;
                        17: hn.dest_ip[23:16]=b;
                        18: hn.dest_ip[15:8]=b;
                        19: hn.dest_ip[7:0]=b;
                        default: begin end
                    endcase
                    if(relative_ip < {26'd0,hn.version_ihl[3:0],2'b00}) begin
                        sum_byte=(tx && want_ip && (relative_ip==10 || relative_ip==11)) ? 8'd0 : b;
                        ip_part[lane]=relative_ip[0] ? {8'd0,sum_byte} : {sum_byte,8'd0};
                    end
                    relative_l4=relative_ip-{26'd0,hn.version_ihl[3:0],2'b00};
                    if(relative_ip >= {26'd0,hn.version_ihl[3:0],2'b00}) begin
                        if(hn.protocol==17) begin
                            case(relative_l4)
                                4: hn.udp_length[15:8]=b;
                                5: hn.udp_length[7:0]=b;
                                6: hn.udp_checksum[15:8]=b;
                                7: hn.udp_checksum[7:0]=b;
                                default: begin end
                            endcase
                        end
                        if(hn.protocol==6 && relative_l4==12) hn.tcp_offset=b;
                        if ((hn.protocol==17 && (relative_l4<8 || relative_l4<{16'd0,hn.udp_length})) ||
                            (hn.protocol==6 && relative_ip<{16'd0,hn.total})) begin
                            sum_byte=(tx && want_l4 &&
                                ((hn.protocol==17 && (relative_l4==6 || relative_l4==7)) ||
                                 (hn.protocol==6 && (relative_l4==16 || relative_l4==17)))) ? 8'd0 : b;
                            l4_part[lane]=relative_l4[0] ? {8'd0,sum_byte} : {sum_byte,8'd0};
                        end
                    end
                end
            end
        end
        ip_add=({2'd0,ip_part[0]}+{2'd0,ip_part[1]})+({2'd0,ip_part[2]}+{2'd0,ip_part[3]});
        l4_add=({2'd0,l4_part[0]}+{2'd0,l4_part[1]})+({2'd0,l4_part[2]}+{2'd0,l4_part[3]});
    end

    always_comb begin
        config_error=(!auto_parse && (l3<14)) ||
            (ipv4 && want_l4 && expected_proto!=0 &&
             !((expected_proto==1 && is_udp)||(expected_proto==2 && is_tcp)||(expected_proto==3 && h.protocol==1)));
        invalid=h.malformed || h.seen!=final_length || final_length<14 || final_length>2048;
        unsupported=0;
        if(ipv4) begin
            invalid=invalid || h.version_ihl[7:4]!=4 || h.version_ihl[3:0]<5 ||
                h.total<header_bytes || ({23'd0,l3}+{16'd0,h.total})>final_length;
            unsupported=(h.frag & 16'h3fff)!=0;
            if(is_udp) invalid=invalid || h.total-header_bytes<8 || h.udp_length<8 || h.udp_length>h.total-header_bytes;
            if(is_tcp) invalid=invalid || h.total-header_bytes<20 || h.tcp_offset[7:4]<5 ||
                {10'd0,h.tcp_offset[7:4],2'b00}>h.total-header_bytes;
            if(!is_udp && !is_tcp && h.protocol!=1) unsupported=1;
        end else if(h.ethertype!=16'h0806) unsupported=1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; h<='0; tx<=0; want_ip<=0; want_l4<=0;
            auto_parse<=0; expected_proto<=0; l3<=14;
            ip_sum<=0; l4_sum<=0; ip_fold<=0; l4_fold<=0;
            ip_folded<=0; l4_folded<=0; final_length<=0;
        end else if(frame_cancel) begin
            state<=IDLE; h<='0; ip_sum<=0; l4_sum<=0;
        end else if(frame_start) begin
            state<=STREAM; h<='0; ip_sum<=0; l4_sum<=0;
            tx<=direction; want_ip<=control[5]; want_l4<=control[6];
            auto_parse<=control[7]; expected_proto<=control[9:8];
            l3<=control[7] ? 9'd14 : {1'b0,control[17:10]};
        end else case(state)
            STREAM: begin
                if(beat_valid) begin h<=hn; ip_sum<=ip_sum+{14'd0,ip_add}; l4_sum<=l4_sum+{14'd0,l4_add}; end
                if(frame_finish) begin final_length<=frame_length; state<=PSEUDO; end
            end
            PSEUDO: begin
                ip_fold<=ip_sum;
                l4_fold<=l4_sum+{16'd0,h.source_ip[31:16]}+{16'd0,h.source_ip[15:0]}+
                    {16'd0,h.dest_ip[31:16]}+{16'd0,h.dest_ip[15:0]}+{24'd0,h.protocol}+{16'd0,l4_bytes};
                state<=FOLD1;
            end
            FOLD1: begin
                ip_fold<={16'd0,ip_fold[15:0]}+{16'd0,ip_fold[31:16]};
                l4_fold<={16'd0,l4_fold[15:0]}+{16'd0,l4_fold[31:16]};
                state<=FOLD2;
            end
            FOLD2: begin
                ip_folded<=ip_fold[15:0]+{15'd0,ip_fold[16]};
                l4_folded<=l4_fold[15:0]+{15'd0,l4_fold[16]};
                state<=RESULT;
                // Result signals are latched below on entry's following cycle.
            end
            RESULT: begin end
            default: begin end
        endcase
    end

    // Final folded registers drive stable results during RESULT; no patch on
    // the same edge that performs accumulation or folding.
    always_comb begin : final_result
        result_flags=DONE;
        result_error=0; error_code=0; patch_ip=0; patch_l4=0;
        ip_checksum=~ip_folded;
        l4_checksum=(is_udp && l4_folded==16'hffff) ? 16'hffff : ~l4_folded;
        if(config_error) begin result_error=1; error_code=24; result_flags=DONE|PARSE; end
        else if(invalid) begin result_error=1; error_code=25; result_flags=DONE|PARSE; end
        else if(unsupported) begin result_error=1; error_code=29; result_flags=DONE|UNSUPPORTED; end
        else if(ipv4) begin
            if(want_ip) begin
                if(tx) patch_ip=1;
                else if(ip_folded==16'hffff) result_flags=result_flags|IP_OK;
                else begin result_error=1; error_code=27; result_flags=result_flags|BAD; end
            end
            if(want_l4 && (is_udp || is_tcp)) begin
                if(tx) patch_l4=1;
                else if(is_udp && h.udp_checksum==0) result_flags=result_flags|UDP_ZERO;
                else if(l4_folded==16'hffff) result_flags=result_flags|L4_OK;
                else begin result_error=1; if(error_code==0) error_code=28; result_flags=result_flags|BAD; end
            end
        end
        if(result_error || !result_valid) begin patch_ip=0; patch_l4=0; end
    end
endmodule
