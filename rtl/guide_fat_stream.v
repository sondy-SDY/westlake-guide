// Read-only FAT32 root short-name file stream. No physical-sector signature scan.
// The buffered sector allows arbitrary consumer backpressure and fragmented files.
module guide_fat_stream #(parameter TIMEOUT=750000000)(
 input clk,input rst,input start,input cancel,input restart,input [87:0] filename,
 input transport_ready,output reg sec_req,output reg [31:0] sec_lba,
 input [7:0] sec_data,input sec_valid,input sec_done,input [7:0] transport_error,
 output reg [7:0] data,output reg valid,input ready,output reg done,
 output busy,output reg [31:0] file_size,output reg [7:0] error,output [7:0] debug_state);
 localparam IDLE=0,MBR=1,PART=2,BPB0=3,BPB1=4,BPB2=5,BPB3=6,BPB4=7,BPB5=8,
 ROOT=9,DIR0=10,DIR1=11,DIR2=12,DIR3=13,DIR4=14,DIR5=15,DIRNEXT=16,
 CHAIN=17,CHAINVAL=18,FILE0=19,BYTE0=20,BYTE1=21,BYTE2=22,BYTE3=23,
 NEXTSEC=30,FINISH=31,FAIL=32,GETSEC=40,WAITSEC=41,RWAIT=42,RBYTE=43;
 reg [7:0] state,ret_sec,ret_word,buffer[0:511],q;
 reg [8:0] write_idx,rd_idx,entry;reg [9:0] received;
 reg [1:0] word_idx;reg [31:0] word_value;
 reg [31:0] volume,fat_base,data_base,fat_size,cluster,cluster_lba;
 reg [7:0] spc,nfats,cluster_sector;reg [15:0] reserved,cluster_hi;
 reg [31:0] file_pos,chain_steps,watchdog;reg is_file,aborting;
 reg [87:0] name_q;
 assign debug_state=state;
 assign busy=(state!=IDLE && state!=FINISH && state!=FAIL);
 always @(posedge clk) begin
  if(sec_valid) buffer[write_idx]<=sec_data;
  q<=buffer[rd_idx];
 end
 task fetch;input [31:0] lba;input [7:0] next_state;begin
  sec_lba<=lba;ret_sec<=next_state;state<=GETSEC;end endtask
 task word_at;input [8:0] addr;input [7:0] next_state;begin
  rd_idx<=addr;word_idx<=0;word_value<=0;ret_word<=next_state;state<=RWAIT;end endtask
 task fail;input [7:0] code;begin error<=code;valid<=0;state<=FAIL;end endtask
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   state<=IDLE;sec_req<=0;sec_lba<=0;write_idx<=0;received<=0;rd_idx<=0;
   word_idx<=0;word_value<=0;ret_sec<=0;ret_word<=0;volume<=0;fat_base<=0;data_base<=0;
   fat_size<=0;cluster<=0;cluster_lba<=0;spc<=0;nfats<=0;reserved<=0;
   cluster_sector<=0;file_size<=0;file_pos<=0;chain_steps<=0;is_file<=0;entry<=0;cluster_hi<=0;
   valid<=0;data<=0;done<=0;error<=0;watchdog<=0;name_q<=0;aborting<=0;
  end else begin
   sec_req<=0;
   if(sec_valid) begin write_idx<=write_idx+1'b1;received<=received+1'b1;end
   // A consumer may pause indefinitely (audio pause or full FIFO).
   if(sec_valid || state!=WAITSEC) watchdog<=0;else watchdog<=watchdog+1'b1;
   if(cancel) aborting<=1;
   case(state)
    IDLE,FINISH,FAIL: if(start) begin
     name_q<=filename;volume<=0;valid<=0;done<=0;error<=0;file_size<=0;aborting<=0;fetch(0,MBR);
    end
    MBR: word_at(510,PART);
    PART: if(word_value[15:0]!=16'haa55) fail(8'h20);else word_at(11,BPB0);
    BPB0: if(word_value[15:0]==512) begin spc<=word_value[23:16];word_at(14,BPB1);end
     else if(volume==0) word_at(450,BPB5);else fail(8'h21);
    BPB5: if(word_value[7:0]==8'h0b || word_value[7:0]==8'h0c) word_at(454,BPB4);else fail(8'h22);
    BPB4: if(word_value==0) fail(8'h22);else begin volume<=word_value;fetch(word_value,MBR);end
    BPB1: begin reserved<=word_value[15:0];nfats<=word_value[23:16];
     if(spc==0 || (spc & (spc-1'b1))!=0 || spc>128 || word_value[15:0]==0 ||
       (word_value[23:16]!=1 && word_value[23:16]!=2)) fail(8'h23);else word_at(17,BPB2);end
    BPB2: if(word_value[15:0]!=0) fail(8'h24);else word_at(36,BPB3);
    BPB3: if(word_value==0) fail(8'h24);else begin fat_size<=word_value;word_at(44,ROOT);end
    ROOT: begin cluster<=word_value & 32'h0fffffff;fat_base<=volume+reserved;
     data_base<=volume+reserved+((nfats==2)?(fat_size<<1):fat_size);
     cluster_sector<=0;chain_steps<=0;is_file<=0;state<=CHAIN;end
    CHAIN: if(cluster<2 || cluster>=32'h0ffffff0 || chain_steps>1000000) fail(8'h25);
     else begin cluster_lba<=data_base+(cluster-2)*spc;
      if(is_file) fetch(data_base+(cluster-2)*spc,BYTE0);
      else begin entry<=0;fetch(data_base+(cluster-2)*spc,DIR0);end end
    DIR0: word_at(entry,DIR1);
    DIR1: if(word_value[7:0]==0) fail(8'h26);
     else if(word_value!={name_q[63:56],name_q[71:64],name_q[79:72],name_q[87:80]}) state<=DIRNEXT;
     else word_at(entry+4,DIR2);
    DIR2: if(word_value!={name_q[31:24],name_q[39:32],name_q[47:40],name_q[55:48]}) state<=DIRNEXT;
     else word_at(entry+8,DIR3);
    DIR3: if(word_value[23:0]!={name_q[7:0],name_q[15:8],name_q[23:16]} || (word_value[31:24]&8'h18)!=0) state<=DIRNEXT;
     else word_at(entry+20,DIR4);
    DIR4: begin cluster_hi<=word_value[15:0];word_at(entry+24,DIR5);end
    DIR5: begin cluster<={cluster_hi[11:0],word_value[31:16]};word_at(entry+28,FILE0);end
    DIRNEXT: if(entry==480) begin
     if(cluster_sector+1<spc) begin cluster_sector<=cluster_sector+1'b1;entry<=0;fetch(cluster_lba+cluster_sector+1,DIR0);end
     else fetch(fat_base+(cluster>>7),CHAINVAL);
    end else begin entry<=entry+32;state<=DIR0;end
    CHAINVAL: word_at({cluster[6:0],2'b00},NEXTSEC);
    NEXTSEC: begin cluster<=word_value & 32'h0fffffff;cluster_sector<=0;chain_steps<=chain_steps+1'b1;state<=CHAIN;end
    FILE0: begin file_size<=word_value;file_pos<=0;cluster_sector<=0;chain_steps<=0;is_file<=1;
     cluster_lba<=data_base+(cluster-2)*spc;
     if(word_value==0 || cluster<2 || cluster>=32'h0ffffff0) fail(8'h27);
     else fetch(data_base+(cluster-2)*spc,BYTE0);end
    BYTE0: begin rd_idx<=0;state<=BYTE1;end
    BYTE1: state<=BYTE2;
    BYTE2: begin data<=q;valid<=1;state<=BYTE3;end
    BYTE3: if(valid && ready) begin
     valid<=0;file_pos<=file_pos+1'b1;
     if(file_pos+1==file_size) begin done<=1;state<=FINISH;end
     else if(rd_idx==511) begin
      if(cluster_sector+1<spc) begin cluster_sector<=cluster_sector+1'b1;fetch(cluster_lba+cluster_sector+1,BYTE0);end
      else fetch(fat_base+(cluster>>7),CHAINVAL);
     end else begin rd_idx<=rd_idx+1'b1;state<=BYTE1;end
    end
    GETSEC: if(transport_ready) begin sec_req<=1;write_idx<=0;received<=0;state<=WAITSEC;end
    WAITSEC: if(sec_done) begin if(received!=512) fail(8'h2f);else state<=ret_sec;end
    RWAIT: state<=RBYTE;
    RBYTE: begin word_value<={q,word_value[31:8]};
     if(word_idx==3) state<=ret_word;
     else begin word_idx<=word_idx+1'b1;rd_idx<=rd_idx+1'b1;state<=RWAIT;end end
    default: fail(8'h30);
   endcase
   if(restart && (state==FAIL || state==IDLE)) begin
    state<=IDLE;valid<=0;done<=0;error<=0;aborting<=0;
   end
   // Never abandon an outstanding SD request: drain it before another file opens.
   if((aborting || cancel) && !start && ((state!=WAITSEC && state!=GETSEC && !sec_req) || (state==WAITSEC && sec_done))) begin
    state<=IDLE;valid<=0;done<=0;aborting<=0;
   end
   if(transport_error!=0 && busy) fail(transport_error);
   else if(watchdog==TIMEOUT-1) fail(8'h31);
  end
 end
endmodule
