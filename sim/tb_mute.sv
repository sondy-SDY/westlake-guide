`timescale 1ns/1ps
// 静音开关（SW3/C6）：静音时 HDMI 音频包全 0，但 FIFO 读指针/时间轴照常前进，
// 所以字幕和轮播推进不受影响；解除静音后应从"本来该播到"的位置继续，而不是重头。
module tb_mute;
 reg mc=0,pc=0;always #12 mc=~mc;always #20 pc=~pc;   // 41.67 MHz / 25 MHz
 reg rst=1,flush=1,valid=0,eof=0,paused=0,mute=0;reg [7:0] data=0;
 wire ready,sv,ended,playing,under;wire [23:0] sample;
 guide_audio #(.CLOCK_HZ(25000000)) dut(mc,rst,flush,data,valid,ready,eof,pc,rst,paused,mute,2'd2,
  sv,sample,ended,playing,under);
 integer i,pos=0,muted_seen=0;
 always @(posedge pc) begin
  #1;                                        // 等 NBA 落定再采样，和 tb_audio 一样
  if(!rst && sv && playing && !paused) begin
   if(mute) begin
    if(sample!==0)$fatal(1,"muted sample %h at pos %0d",sample,pos);
    muted_seen=muted_seen+1;
   end else if(sample!==((1000+pos)<<8))
    $fatal(1,"sample %0d got %h want %h (timeline must not restart on unmute)",
           pos,sample,(1000+pos)<<8);
   pos=pos+1;
  end
 end
 task sendbyte(input [7:0] b);begin
  @(negedge mc);valid=1;data=b;@(posedge mc);while(!ready)@(posedge mc);
 end endtask
 initial begin
  #200;@(negedge mc);rst=0;flush=0;
  for(i=0;i<2000;i=i+1) begin sendbyte((1000+i)&255);sendbyte(((1000+i)>>8)&255);end
  @(negedge mc);valid=0;eof=1;
  wait(pos>=100);
  @(negedge pc);mute=1;                       // 第 100 个采样之后静音
  wait(pos>=500);                             // 静音 400 个采样
  @(negedge pc);mute=0;
  wait(ended);
  if(pos!=2000)$fatal(1,"pos %0d after EOF",pos);
  if(muted_seen!=400)$fatal(1,"muted window %0d samples, want 400",muted_seen);
  $display("PASS mute: %0d samples silent while playing, timeline advanced, ended normally",muted_seen);
  $finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
