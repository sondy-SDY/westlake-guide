// 4096-sample asynchronous FIFO. Gray pointers cross clocks; no multi-bit PCM CDC.
// 51 MHz / 48 kHz = 1062.5 clocks. A fractional enable keeps the exact mean rate.
module guide_audio #(parameter CLOCK_HZ=51000000)(input mclk,input mrst,input flush,input [7:0] data,input valid,output ready,
 input eof,input pclk,input prst,input paused,input mute,input [1:0] volume,
 output reg sample_valid,output reg [23:0] sample,output reg ended,
 output reg playing,output reg underrun);
 reg [15:0] fifo[0:4095];reg [12:0] wp,wgray,rp,rgray;
 reg [12:0] rg1,rg2,wg1,wg2;reg half;reg [7:0] lowbyte;
 reg [15:0] q;reg [1:0] eof_sync,flush_sync;reg [25:0] phase;
 wire [12:0] next_wp=wp+1'b1;
 wire [12:0] next_wgray=(next_wp>>1)^next_wp;
 wire full=next_wgray=={~rg2[12:11],rg2[10:0]};
 wire empty=rgray==wg2;
 function [12:0] ungray;input [12:0] g;integer i;begin
  ungray[12]=g[12];for(i=11;i>=0;i=i-1) ungray[i]=ungray[i+1]^g[i];
 end endfunction
 wire [12:0] available=ungray(wg2)-rp;
 wire fifo_reset=mrst || flush;
 assign ready=!full && !fifo_reset;
 always @(posedge mclk or posedge fifo_reset) begin
  if(fifo_reset) begin wp<=0;wgray<=0;rg1<=0;rg2<=0;half<=0;lowbyte<=0;end
  else begin
   rg1<=rgray;rg2<=rg1;
   if(valid && ready) begin
    if(!half) begin lowbyte<=data;half<=1;end
    else begin wp<=next_wp;wgray<=next_wgray;half<=0;end
   end
  end
 end
 // Keep RAM write outside the asynchronous reset branch for block-RAM inference.
 always @(posedge mclk) if(valid && ready && half) fifo[wp[11:0]]<={data,lowbyte};
 always @(posedge pclk) q<=fifo[rp[11:0]];
 always @(posedge pclk or posedge fifo_reset) begin
  if(fifo_reset) flush_sync<=3;else flush_sync<={flush_sync[0],1'b0};
 end
 wire rrst=prst || flush_sync[1];
 reg signed [15:0] scaled;
 always @* begin
  case(volume) 0:scaled=$signed(q)>>>2;1:scaled=$signed(q)>>>1;default:scaled=$signed(q);endcase
 end
 always @(posedge pclk or posedge rrst) begin
  if(rrst) begin rp<=0;rgray<=0;wg1<=0;wg2<=0;eof_sync<=0;playing<=0;ended<=0;underrun<=0;end
  else begin
   wg1<=wgray;wg2<=wg1;eof_sync<={eof_sync[0],eof};
   if(!playing && (available>=512 || (eof_sync[1] && !empty))) playing<=1;
   if(eof_sync[1] && empty) begin ended<=1;playing<=0;end
   if(phase>=CLOCK_HZ-48000 && playing && !paused) begin
    if(!empty) begin rp<=rp+1'b1;rgray<=((rp+1'b1)>>1)^(rp+1'b1);end
    else if(!eof_sync[1]) begin underrun<=1;playing<=0;end
   end
  end
 end
 // Audio packet cadence continues through silence, pause and file switching.
 always @(posedge pclk or posedge prst) begin
  if(prst) begin phase<=0;sample_valid<=0;sample<=0;end
  else begin
   sample_valid<=0;
   if(phase>=CLOCK_HZ-48000) begin
    phase<=phase-(CLOCK_HZ-48000);sample_valid<=1;
    sample<=(!rrst && playing && !paused && !mute && !empty)?{scaled,8'd0}:24'd0;
   end else phase<=phase+48000;
  end
 end
endmodule
