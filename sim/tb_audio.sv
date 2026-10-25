`timescale 1ns/1ps
module tb_audio;
 reg mc=0,pc=0;always #12 mc=~mc;always #9.8039 pc=~pc;
 reg rst=1,flush=1,valid=0,eof=0,paused=0,mute=0;reg [7:0] data;wire ready,sv,ended,playing,under;wire [23:0] sample;
 integer i,received=0,base=1000,cycles=0,last_cycle=0,ticks=0;reg checking=0;
 guide_audio dut(mc,rst,flush,data,valid,ready,eof,pc,rst,paused,mute,2'd2,sv,sample,ended,playing,under);
 wire av;integer acr_samples=0,acr_ticks=0,acr_last=0;reg expect_acr;
 guide_acr acr(pc,rst,sv,av);
 always @(posedge pc) begin
  expect_acr=0;
  if(rst)begin acr_samples=0;acr_ticks=0;acr_last=0;end
  else if(sv)begin
   acr_samples=acr_samples+1;
   if(acr_samples==48)begin acr_samples=0;expect_acr=1;end
  end
  #2;
  if(av!==expect_acr)$fatal(1,"ACR must pulse once per 48 samples");
  if(av)begin
   if(acr_last!=0 && cycles-acr_last!=51000)$fatal(1,"ACR cadence must be 1 kHz");
   acr_last=cycles;acr_ticks=acr_ticks+1;
  end
 end
 task sendbyte(input [7:0] b);begin
  @(negedge mc);valid=1;data=b;@(posedge mc);while(!ready)@(posedge mc);
 end endtask
 task sendclip(input integer seed,input integer length);begin
  for(i=0;i<length;i=i+1) begin sendbyte((seed+i)&255);sendbyte(((seed+i)>>8)&255);end
  @(negedge mc);valid=0;eof=1;
 end endtask
 always @(posedge pc) begin
  cycles=cycles+1;#1;
  if(!rst && sv)begin
   if(last_cycle!=0 && cycles-last_cycle!=1062 && cycles-last_cycle!=1063)$fatal(1,"sample cadence %d",cycles-last_cycle);
   last_cycle=cycles;ticks=ticks+1;
   if(checking && sample!=0) begin
    if(sample!==((base+received)<<8))$fatal(1,"audio sequence n=%d got=%h want=%h",received,sample,(base+received)<<8);
    received=received+1;
   end
  end
 end
 initial begin
  #200;@(negedge mc);rst=0;flush=0;checking=1;
  sendclip(1000,900);wait(received>=90);@(negedge pc);paused=1;
  repeat(4000)@(negedge pc);if(sample!=0)$fatal(1,"pause not silent");paused=0;
  wait(ended);if(received!=900 || under)$fatal(1,"audio completion %d under %b",received,under);
  $display("PASS PCM sequence, pause/resume, EOF and exact 48 kHz cadence");
  @(negedge mc);flush=1;eof=0;checking=0;repeat(20)@(negedge mc);
  received=0;base=2000;flush=0;checking=1;sendclip(2000,6000);wait(ended);
  if(received!=6000 || under)$fatal(1,"replay/full/wrap failed");
  if(acr_ticks<140)$fatal(1,"insufficient ACR coverage");
  $display("PASS FIFO flush/replay, full backpressure and pointer wrap have no stale samples");
  $display("PASS ACR every 48 samples / 51000 clocks, continuous through pause and flush");$finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
