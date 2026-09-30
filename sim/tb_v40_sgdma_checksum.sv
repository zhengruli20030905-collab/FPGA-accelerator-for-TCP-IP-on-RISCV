`timescale 1ns/1ps
`include "dma_addr_map.svh"
module tb_v40_sgdma_checksum;
    logic clk=0;always #20 clk=~clk;
    logic rst_n=0,mem_write=0,mem_read=0;
    logic [31:0] addr=0,din=0;wire [31:0] dout;
    logic rx_available=0,tx_available=1;
    logic [15:0] rx_length=0;
    logic descriptor_conflict=0,payload_conflict=0,packet_conflict=0;
    wire enabled,busy,dmem_access_active,descriptor_lock_valid,payload_lock_valid;
    wire [31:0] descriptor_lock_addr,descriptor_lock_length,payload_lock_addr,payload_lock_length;
    wire packet_lock,direction,commit,cancel,rx_pop,tx_autorun;
    wire [31:0] length;
    wire dm_req,dm_write;logic dm_ready=0,dm_rvalid=0;
    wire [31:0] dm_addr,dm_wdata;logic [31:0] dm_rdata=0;
    wire [3:0] dm_byteena,pkt_byteena;
    wire pkt_req,pkt_write;logic pkt_ready=0,pkt_rvalid=0;
    wire [10:0] pkt_addr;wire [31:0] pkt_wdata;logic [31:0] pkt_rdata=0;
    packet_dma #(.TIMEOUT_CYCLES(64)) dut(.*);
    byte unsigned ram[0:131071], txram[0:2047],rxram[0:2047],frame[0:2047],golden[0:2047];
    int txhead=0,rxhead=0,commits=0,pops=0,drops=0,cancels=0,checks=0;
    int n,l3,l4,proto,payload,segments,bases[0:3],lens[0:3];
    int watchdog=0;bit force_patch_stall=0;
    function automatic [31:0] getword(input int a);
        return {ram[a+3],ram[a+2],ram[a+1],ram[a]};
    endfunction
    task automatic putword(input int a,input int unsigned v);
        for(int k=0;k<4;k++)ram[a+k]=v>>(k*8);
    endtask
    task automatic netword(input int a,input int unsigned v);
        frame[a]=v>>8;frame[a+1]=v;
    endtask
    function automatic [15:0] refsum(input int a,input int count,input int unsigned s0);
        int unsigned s;s=s0;
        for(int k=0;k<count;k+=2)s+=(int'(frame[a+k])<<8)|((k+1<count)?int'(frame[a+k+1]):0);
        while(s>>16)s=(s&65535)+(s>>16);
        return ~s[15:0];
    endfunction
    task automatic check(input bit condition,input string msg);
        checks++;if(!condition)$fatal(1,"%s TXhead=%0d RXhead=%0d error=%0d state=%0d",msg,txhead,rxhead,dut.u_sgdma_descriptor_engine.global_error,dut.u_sgdma_descriptor_engine.state);
    endtask
    always @(negedge clk) begin
        dm_ready=($urandom_range(0,3)!=0);
        pkt_ready=($urandom_range(0,3)!=0) && !(force_patch_stall && dut.csum_wait);
    end
    always @(posedge clk) begin
        dm_rvalid<=0;pkt_rvalid<=0;
        if(dm_req&&dm_ready) begin
            if(dm_write)begin
                for(int k=0;k<4;k++)if(dm_byteena[k])ram[dm_addr+k]<=dm_wdata[k*8+:8];
            end else begin dm_rdata<=getword(dm_addr);dm_rvalid<=1;end
        end
        if(pkt_req&&pkt_ready)begin
            if(pkt_write)begin
                for(int k=0;k<4;k++)if(pkt_byteena[k])txram[pkt_addr+k]<=pkt_wdata[k*8+:8];
            end else begin pkt_rdata<={rxram[pkt_addr+3],rxram[pkt_addr+2],rxram[pkt_addr+1],rxram[pkt_addr]};pkt_rvalid<=1;end
        end
        if(commit)begin commits++;check(packet_lock,"commit locked");end
        if(rx_pop)begin pops++;rx_available<=0;end
        if(cancel)begin if(direction)cancels++;else begin drops++;rx_available<=0;end end
        if(rst_n && (commit||rx_pop||cancel) && dut.desc_req)begin
            check(dut.desc_write && dut.desc_addr[3:0]==8,"finalize accompanies OWN write");
            check(getword(dut.desc_addr+4)!=0,"STATUS exists before OWN");
        end
        if(dut.csum_beat_valid)
            check((direction ? (pkt_req&&pkt_write&&pkt_ready) : (dm_req&&dm_write&&dm_ready)),"beat exactly successful write");
    end
    task automatic mmio(input logic [31:0] a,input logic [31:0] v);
        @(negedge clk);addr=a;din=v;mem_write=1;
        @(negedge clk);mem_write=0;
    endtask
    task automatic build(input int p,input int len,input int offset=14);
        int unsigned pseudo;logic [15:0] c;
        proto=p;payload=len;l3=offset;l4=l3+20;n=l4+(p==17?8:20)+len;
        for(int i=0;i<2048;i++)begin frame[i]=$urandom;txram[i]=8'ha5;rxram[i]=8'h5a;end
        netword(12,16'h0800);frame[l3]=8'h45;netword(l3+2,n-l3);netword(l3+6,0);
        frame[l3+9]=p;netword(l3+10,0);
        if(p==17)begin netword(l4+4,n-l4);netword(l4+6,0);end
        else begin frame[l4+12]=8'h50;netword(l4+16,0);end
        pseudo=p+n-l4;
        for(int i=l3+12;i<l3+20;i+=2)pseudo+=(int'(frame[i])<<8)|int'(frame[i+1]);
        c=refsum(l4,n-l4,pseudo);if(p==17 && c==0)c=16'hffff;
        netword(l4+(p==17?6:16),c);netword(l3+10,refsum(l3,20,0));
        for(int i=0;i<2048;i++)golden[i]=frame[i];
    endtask
    task automatic prepare(input bit tx,input bit bad,input int fault=0);
        int pos,d,ctrl,base,head;int before_commit,before_pop,before_drop,before_cancel;
        before_commit=commits;before_pop=pops;before_drop=drops;before_cancel=cancels;
        base=tx?4096:4608;head=tx?txhead:rxhead;
        segments=3;
        if(tx)begin lens[0]=5;lens[1]=49;lens[2]=n-54;end
        else begin lens[0]=511;lens[1]=513;lens[2]=1024;end
        if(tx && n<=54)begin lens[0]=1;lens[1]=2;lens[2]=n-3;end
        pos=0;
        for(int s=0;s<segments;s++)begin
            bases[s]=16384+s*4096+(s+1);
            for(int k=-1;k<=lens[s];k++)ram[bases[s]+k]=8'hc7;
            if(tx)for(int k=0;k<lens[s];k++)ram[bases[s]+k]=frame[pos+k];
            d=base+((head+s)&31)*16;
            ctrl=1|(tx?2:0)|(s==0?4:0)|(s==segments-1?8:0);
            if(s==0)ctrl|=tx?(32'h60|(l3<<10)|((proto==17?1:2)<<8)):32'he0;
            putword(d,bases[s]);putword(d+4,lens[s]);putword(d+8,ctrl);putword(d+12,0);
            pos+=lens[s];
        end
        if(!tx)begin for(int k=0;k<n;k++)rxram[k]=frame[k];rx_length=n;rx_available=1;end
        if(fault==2)force_patch_stall=1;
        mmio(tx?`SG_TX_TAIL:`SG_RX_TAIL,head+segments);
        if(fault==1)begin
            wait(dut.csum_wait && dut.csum_result_valid);
            @(negedge clk);packet_conflict=1;
            @(negedge clk);packet_conflict=0;
        end
        watchdog=0;
        while((tx?dut.u_sgdma_descriptor_engine.tx_head:dut.u_sgdma_descriptor_engine.rx_head)!=head+segments && watchdog<200000)begin
            @(negedge clk);watchdog++;
        end
        check(watchdog<200000,"frame head progress");force_patch_stall=0;
        if(tx)txhead+=segments;else rxhead+=segments;
        d=base+((head+segments-1)&31)*16;
        if(bad||fault!=0)begin
            check((getword(d+12)&2)!=0,"bad LAST error status");
            check(tx?(cancels==before_cancel+1 && commits==before_commit):(drops==before_drop+1 && pops==before_pop),"one cancel/drop no commit/pop");
        end else begin
            check((getword(d+12)&16'h0083)==16'h0081,"LAST checksum done");
            check(tx?(commits==before_commit+1):(pops==before_pop+1),"one frame finalize");
            if(tx)begin
                for(int k=0;k<n;k++)check(txram[k]==golden[k],"TX exact patched frame");
                check(txram[n]==8'ha5,"TX outside frame preserved");
                check((getword(d+12)&16'h2000)!=0,"PATCHED status");
            end else begin
                pos=0;
                for(int s=0;s<segments;s++)begin
                    for(int k=0;k<lens[s] && pos<n;k++)begin check(ram[bases[s]+k]==frame[pos],"RX exact scatter");pos++;end
                    check(ram[bases[s]-1]==8'hc7 && ram[bases[s]+lens[s]]==8'hc7,"RX guards");
                end
            end
        end
        if(bad||fault!=0)mmio(`SG_CTRL,5);
        repeat(3)@(negedge clk);
    endtask
    initial begin
        for(int k=0;k<131072;k++)ram[k]=0;
        repeat(4)@(negedge clk);rst_n=1;
        mmio(`SG_TX_DESC_BASE,4096);mmio(`SG_TX_RING_SIZE,32);
        mmio(`SG_RX_DESC_BASE,4608);mmio(`SG_RX_RING_SIZE,32);mmio(`SG_CTRL,1);
        for(int i=0;i<40;i++)begin
            build(i[0]?17:6, i==39?1472:1+i*3);
            // Incoming checksums are ignored/zeroed by TX generation.
            netword(l3+10,16'ha55a);netword(l4+(proto==17?6:16),16'h1234);
            prepare(1,0);
            for(int k=0;k<n;k++)frame[k]=golden[k];prepare(0,0);
        end
        build(6,27,15);prepare(1,0); // L4 checksum low address lane3.
        build(17,31);frame[n-1]^=1;prepare(0,1);
        build(6,31);frame[n-1]^=1;prepare(0,1);
        build(17,31);frame[l3+8]^=1;prepare(0,1);
        build(17,31);netword(l4+6,0);prepare(0,0);
        build(17,31);prepare(1,1,1);
        build(17,31);prepare(1,1,2);
        build(6,37);prepare(1,0);prepare(0,0);
        check(txhead>32 && rxhead>32,"rings wrapped");
        $display("V40 TEST PASSED integration checks=%0d TX=%0d RX=%0d DROP=%0d CANCEL=%0d",checks,commits,pops,drops,cancels);$finish;
    end
    initial begin #100000000;$fatal(1,"integration watchdog");end
endmodule
