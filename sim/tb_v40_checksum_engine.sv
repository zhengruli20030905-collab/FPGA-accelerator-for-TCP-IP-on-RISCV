`timescale 1ns/1ps
module tb_v40_checksum_engine;
    logic clk=0; always #20 clk=~clk;
    logic rst_n=0,frame_start=0,frame_cancel=0,frame_finish=0,direction=0,beat_valid=0;
    logic [31:0] control=0,frame_length=0,beat_data=0,beat_offset=0;
    logic [3:0] beat_keep=0;
    wire result_valid,result_error,patch_ip,patch_l4,busy;
    wire [7:0] error_code;
    wire [15:0] result_flags,ip_checksum,l4_checksum;
    wire [10:0] ip_patch_offset,l4_patch_offset;
    internet_checksum_engine dut(.*);
    byte unsigned data[0:2047];
    int checks=0, n, l3, ihl, proto, l4, sz;
    int unsigned sum;
    logic [15:0] gip,gl4;
    task automatic require(input bit ok,input string msg);
        checks++; if(!ok) $fatal(1,"%s n=%0d ihl=%0d proto=%0d flags=%h error=%0d",msg,n,ihl,proto,result_flags,error_code);
    endtask
    // Independent conventional 16-bit network-order reference.
    function automatic [15:0] checksum(input int start,input int len,input int unsigned initial_sum);
        int unsigned s; s=initial_sum;
        for(int k=0;k<len;k+=2) s+= (int'(data[start+k])<<8) | ((k+1<len)?int'(data[start+k+1]):0);
        while(s>>16) s=(s&65535)+(s>>16);
        return ~s[15:0];
    endfunction
    task automatic word_at(input int pos,input int v);
        data[pos]=v>>8; data[pos+1]=v;
    endtask
    task automatic make_frame(input int payload,input int header_words,input int protocol,input int l3offset=14);
        l3=l3offset; ihl=header_words; proto=protocol; l4=l3+ihl*4;
        sz=(proto==17)?8:20; n=l4+sz+payload;
        for(int k=0;k<2048;k++) data[k]=$urandom;
        word_at(12,16'h0800); data[l3]=8'h40|ihl;
        word_at(l3+2,n-l3); word_at(l3+6,0); data[l3+9]=proto;
        word_at(l3+10,0); data[l4+12]=8'h50;
        if(proto==17) begin word_at(l4+4,sz+payload);word_at(l4+6,0); end
        else word_at(l4+16,0);
        gip=checksum(l3,ihl*4,0);
        sum=proto+sz+payload;
        for(int k=l3+12;k<l3+20;k+=2) sum+=(int'(data[k])<<8)|int'(data[k+1]);
        gl4=checksum(l4,sz+payload,sum);
        if(proto==17 && gl4==0) gl4=16'hffff;
    endtask
    task automatic run_frame(input bit tx,input int split,input int expect_error=0);
        int pos,cnt,limit;
        @(negedge clk); direction=tx; control=32'he0;
        if(tx) control=32'h60|(l3<<10)|((proto==17?1:2)<<8);
        frame_start=1; @(negedge clk);frame_start=0;
        pos=0;
        while(pos<n) begin
            repeat($urandom_range(0,2)) @(negedge clk);
            limit=(pos<split)?split:n;
            if(limit>n)limit=n;
            cnt=$urandom_range(1,4); if(cnt>limit-pos)cnt=limit-pos;
            beat_data=0; beat_keep=0;
            for(int k=0;k<cnt;k++) begin beat_data[k*8+:8]=data[pos+k]; beat_keep[k]=1; end
            beat_offset=pos;beat_valid=1;
            @(negedge clk);beat_valid=0;pos+=cnt;
        end
        frame_length=n;frame_finish=1;@(negedge clk);frame_finish=0;
        wait(result_valid); @(negedge clk);
        require(result_error==(expect_error!=0),"error classification");
        if(expect_error!=0) require(error_code==expect_error,"specific error");
        else if(tx) begin
            require(ip_checksum==gip,"TX IP golden");
            require(l4_checksum==gl4,"TX L4 golden");
            require(patch_ip && patch_l4,"patch enables");
            require(ip_patch_offset==l3+10 && l4_patch_offset==l4+(proto==17?6:16),"patch positions");
        end else require((result_flags&16'h0100)!=0,"RX IP verified");
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(int p=0;p<2;p++) begin
            for(int h=5;h<=15;h++) begin
                make_frame(37,h,p?6:17);
                // Every possible segment boundary, random beat boundaries.
                for(int split=1;split<n;split++) run_frame(1,split);
                word_at(l3+10,gip);word_at(l4+(proto==17?6:16),gl4);
                run_frame(0,35);
                require(result_flags[9],"RX L4 verified");
                data[n-1]^=1;run_frame(0,51,28);data[n-1]^=1;
                data[l3+8]^=1;run_frame(0,19,27);
            end
        end
        for(int i=0;i<18;i++) begin
            case(i)
                0:sz=1;1:sz=2;2:sz=3;3:sz=4;4:sz=5;5:sz=7;
                6:sz=20;7:sz=21;8:sz=40;9:sz=60;10:sz=64;
                11:sz=511;12:sz=512;13:sz=513;14:sz=1472;
                15:sz=1476;16:sz=1472;default:sz=2006;
            endcase
            make_frame(sz,5,17);run_frame(1,53);
            word_at(l3+10,gip);word_at(l4+6,gl4);run_frame(0,513>n?1:513);
            word_at(l4+6,0);run_frame(0,7);require(result_flags[12]&&!result_flags[9],"UDP absent");
        end
        make_frame(21,5,17);word_at(l3+6,16'h2000);run_frame(1,7,29);
        make_frame(21,5,17);word_at(l4+4,65535);run_frame(1,3,25);
        make_frame(21,5,17);word_at(l3+2,65535);run_frame(1,3,25);
        make_frame(21,5,17);data[l3]=8'h44;run_frame(1,3,25);
        // Zero-result UDP: insert a 16-bit compensating payload word.
        make_frame(2,5,17);word_at(l4+8,0);
        gl4=checksum(l4,10,sum);word_at(l4+8,gl4);gl4=16'hffff;
        run_frame(1,1);
        // Lane-3 checksum patch location (L3=15) is covered by TX metadata.
        make_frame(27,5,6,15);run_frame(1,37);
        // Exhaustive split coverage on the maximum-size frame as well.
        make_frame(2006,5,17);
        for(int split=1;split<n;split++)run_frame(1,split);
        // Mid-frame cancellation and reset must not leak accumulated bytes.
        @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
        beat_valid=1;beat_data=32'h78563412;beat_keep=15;beat_offset=0;
        @(negedge clk);beat_valid=0;frame_cancel=1;
        @(negedge clk);frame_cancel=0;require(!busy,"mid-frame cancel");
        frame_start=1;@(negedge clk);frame_start=0;beat_valid=1;
        @(negedge clk);beat_valid=0;rst_n=0;
        @(negedge clk);rst_n=1;require(!busy,"mid-frame reset");
        @(negedge clk);frame_cancel=1;@(negedge clk);frame_cancel=0;
        require(!busy && !result_valid,"cancel clears state");
        make_frame(13,5,17);run_frame(1,5);
        $display("V40 TEST PASSED checksum checks=%0d",checks);$finish;
    end
    initial begin #300000000; $fatal(1,"watchdog"); end
endmodule
