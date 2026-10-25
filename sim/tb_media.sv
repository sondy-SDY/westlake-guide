`timescale 1ns/1ps
module tb_media;
 reg clk=0;always #12 clk=~clk;reg rst=1,play=0;reg [3:0] page=0;reg noaudio=0;
 reg busy=0,sdone=0,bdone=0;reg [7:0] se=0,be=0;reg [31:0] size=921654;
 wire start,cancel,bs,loaded,flush,mode,eof,aerr;wire [87:0] name;wire [10:0] width;
 wire [9:0] height,left,top;wire [20:0] base;wire [3:0] index;wire bootdone;wire [7:0] error;integer i,opens=0;reg [87:0] expected_name;reg [7:0] digit;
 wire mrestart;
 guide_media dut(clk,rst,play,page,noaudio,busy,sdone,se,size,start,cancel,name,bdone,be,1'b1,bs,width,height,base,left,top,loaded,index,bootdone,error,flush,mode,eof,aerr,mrestart);
 task finish_file;begin repeat(5)@(negedge clk);busy=0;sdone=1;bdone=1;end endtask
 always @(posedge clk)if(start)opens=opens+1;
 initial begin
  #100;@(negedge clk)rst=0;
  // 第 1 张：开机卡 PIC11 -> 第 12 页（base = 11*153600）
  wait(start);if(index!=0 || base!=1689600 || name!="PIC11   DAT")$fatal(1,"boot card %s base=%0d",name,base);
  if(width!=640 || height!=480 || left!=0 || top!=0)$fatal(1,"boot card geometry");
  @(negedge clk);busy=1;sdone=0;bdone=0;finish_file();
  repeat(3)@(negedge clk);if(!bootdone)$fatal(1,"boot_done");
  // 第 2..12 张：PIC00..PIC10
  for(i=0;i<11;i=i+1)begin
   wait(start);if(index!=i || base!=i*153600)$fatal(1,"boot index/base");
   digit=48+i;expected_name=(i==10)?{"PIC10","   DAT"}:{"PIC0",digit,"   DAT"};
   if(name!=expected_name || width!=640 || height!=480 || left!=0 || top!=0)$fatal(1,"card %s",name);
   @(negedge clk);busy=1;sdone=0;bdone=0;finish_file();
  end
  wait(loaded);repeat(10)@(negedge clk);if(opens!=12 || error)$fatal(1,"boot prematurely completed");
  $display("PASS twelve 640x480 cards boot (boot card + route+5 spots+emergency+3 ads+dev), route page = PIC00");
  page=3;play=~play;wait(start);if(name!="AUD03   PCM" || flush)$fatal(1,"audio open");
  @(negedge clk);busy=1;sdone=0;bdone=0;size=48000;
  repeat(4)@(negedge clk);page=5;play=~play;wait(cancel);
  repeat(20)@(negedge clk);if(!flush || start)$fatal(1,"unsafe restart");busy=0;
  wait(start);if(name!="AUD05   PCM")$fatal(1,"wrong audio");
  @(negedge clk);busy=1;sdone=0;repeat(3)@(negedge clk);se=8'h26;busy=0;
  repeat(3)@(negedge clk);if(!aerr || !loaded || error)$fatal(1,"missing audio killed display");
  // 广告页（no_audio）：重开音频不发流，并且 flush 必须释放（BUG-5）
  noaudio=1;page=7;play=~play;
  repeat(80)@(negedge clk);
  if(!eof || flush || start)$fatal(1,"no_audio: eof=%b flush=%b start=%b",eof,flush,start);
  // 回导览页：play_toggle 再变一次就重新打开 AUD01，flush 由 AOPEN 清
  noaudio=0;page=1;play=~play;
  wait(start);if(name!="AUD01   PCM" || flush)$fatal(1,"return from ad: %s flush=%b",name,flush);
  $display("PASS audio cancellation, page pairing, missing-audio degradation, ad-page flush release");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout state %d",dut.state);end
endmodule
