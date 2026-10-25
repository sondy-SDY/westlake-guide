// Read-only SD v2 SDHC/SDXC SPI transport. SDSC deliberately rejected.
// At 41.6667 MHz: initialization ~393 kHz, block transfers ~6.94 MHz.
module sd_spi_reader #(parameter POWER_WAIT=125000, parameter TIMEOUT=125000000,
 parameter SLOW_DIV=53, parameter FAST_DIV=3)
(input clk,input rst,input restart,output reg cs_n,output sck,output mosi,input miso,
 output reg ready,input read_req,input [31:0] read_lba,
 output reg [7:0] data,output reg valid,output reg done,output reg [7:0] error);
 localparam BOOT=0,CLOCKS=1,C0=2,C8=3,C55=4,C41=5,C58=6,IDLE=7,
 READ_CMD=8,TOKEN=9,DATA=10,CRC1=11,CRC2=12,RELEASE=13,
 CMD_SEND=20,CMD_R1=21,CMD_EXTRA=22,CMD_GAP=23,XFER=30,FAIL=31;
 reg [5:0] state,after_byte,after_cmd; reg [31:0] timer,watchdog;
 reg [47:0] command; reg [2:0] command_idx; reg [3:0] clocks;
 reg [8:0] byte_idx; reg [7:0] tx,last,r1,divider;
 reg start; wire busy,byte_done;wire [7:0] rx;
 reg [2:0] extra_left;reg [31:0] extra;reg [31:0] lba;
 spi_byte bus(clk,rst,start,tx,divider,miso,sck,mosi,busy,byte_done,rx);
 task transfer;input [7:0] value;input [5:0] next_state;begin
  tx<=value;start<=1;after_byte<=next_state;state<=XFER;end endtask
 task issue;input [47:0] cmd;input [2:0] n;input [5:0] next_state;begin
  command<=cmd;command_idx<=0;extra_left<=n;extra<=0;
  after_cmd<=next_state;cs_n<=0;state<=19;end endtask
 always @(posedge clk or posedge rst) begin
  if(rst) begin state<=BOOT;cs_n<=1;ready<=0;valid<=0;done<=0;error<=0;
   timer<=0;watchdog<=0;start<=0;divider<=SLOW_DIV;tx<=255;last<=255;
   clocks<=0;data<=0;byte_idx<=0;command<=0;command_idx<=0;extra_left<=0;
   extra<=0;r1<=255;after_byte<=BOOT;after_cmd<=BOOT;lba<=0;end
  else begin
   start<=0;valid<=0;done<=0;
   if(state==IDLE || state==FAIL) watchdog<=0; else watchdog<=watchdog+1'b1;
   case(state)
    BOOT: if(timer==POWER_WAIT-1) begin timer<=0;state<=CLOCKS;end else timer<=timer+1'b1;
    CLOCKS: if(clocks==10) state<=C0; else begin clocks<=clocks+1'b1;transfer(255,CLOCKS);end
    C0: issue({8'h40,32'd0,8'h95},0,C8);
    C8: if(r1!=1) begin error<=8'h01;state<=FAIL;end else issue({8'h48,32'h1aa,8'h87},4,C55);
    C55: if(extra!=32'h1aa) begin error<=8'h02;state<=FAIL;end else issue({8'h77,32'd0,8'hff},0,C41);
    C41: if(r1>1) begin error<=8'h03;state<=FAIL;end else issue({8'h69,32'h40000000,8'hff},0,C58);
    C58: if(r1==1) begin extra<=32'h1aa;state<=C55;end
     else if(r1!=0) begin error<=8'h04;state<=FAIL;end
     else issue({8'h7a,32'd0,8'hff},4,RELEASE);
    RELEASE: begin
     cs_n<=1;
     if(r1!=0 || !extra[30] || !extra[31]) begin error<=8'h05;state<=FAIL;end
     else begin divider<=FAST_DIV;transfer(255,IDLE);end
    end
    IDLE: begin ready<=1; if(read_req) begin lba<=read_lba;ready<=0;state<=READ_CMD;end end
    READ_CMD: issue({8'h51,lba,8'hff},0,TOKEN);
    TOKEN: if(r1!=0) begin error<=8'h06;state<=FAIL;end
     else if(last==8'hfe) begin byte_idx<=0;transfer(255,DATA);end
     else if(last!=8'hff && last!=0) begin error<=8'h07;state<=FAIL;end
     else transfer(255,TOKEN);
    DATA: begin data<=last;valid<=1;
     if(byte_idx==511) transfer(255,CRC1);else begin byte_idx<=byte_idx+1'b1;transfer(255,DATA);end end
    CRC1: transfer(255,CRC2);
    CRC2: begin cs_n<=1;transfer(255,CMD_GAP);end
    CMD_GAP: begin done<=1;ready<=1;state<=IDLE;end
    19: transfer(255,CMD_SEND);
    CMD_SEND: begin
     if(command_idx==5) transfer(command[47:40],CMD_R1);
     else transfer(command[47:40],CMD_SEND);
     command<={command[39:0],8'hff};command_idx<=command_idx+1'b1;
    end
    CMD_R1: begin
     // The last byte here is the response to CRC on first entry (always FF).
     if(!last[7]) begin r1<=last;
      if(extra_left!=0) transfer(255,CMD_EXTRA);
      else begin last<=255;state<=after_cmd;end
     end else transfer(255,CMD_R1);
    end
    CMD_EXTRA: begin extra<={extra[23:0],last};extra_left<=extra_left-1'b1;
     if(extra_left==1) begin last<=255;state<=after_cmd;end else transfer(255,CMD_EXTRA);end
    XFER: if(byte_done) begin last<=rx;state<=after_byte;end
    FAIL: begin cs_n<=1;ready<=0;end
    default: state<=FAIL;
   endcase
   // Re-run the card power-up/CMD0/ACMD41 sequence in place. A transport
   // failure otherwise sticks until the whole FPGA is reset, which also drops
   // the HDMI link; this keeps recovery local to the storage path.
   if(restart && (state==FAIL || state==IDLE)) begin
    state<=BOOT;cs_n<=1;ready<=0;error<=0;timer<=0;watchdog<=0;
    divider<=SLOW_DIV;clocks<=0;last<=255;tx<=255;
   end
   if(watchdog==TIMEOUT-1) begin error<=8'h08;state<=FAIL;cs_n<=1;end
  end
 end
endmodule
