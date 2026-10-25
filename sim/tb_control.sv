`timescale 1ns/1ps
module tb_control;
 reg clk=0;always #10 clk=~clk;reg rst=1,enabled=0,nt=0,hh=0,at=0,pt=0,rh=0,adone=0,fb=0;
 reg aplaying=1;   // narration still running: the tour must not advance yet
 reg [6:0] per=7'd10;wire [2:0] page;wire auto_mode,paused,toggle;wire [6:0] seconds,period;wire [7:0] fade;wire zoomw;reg zh=0;
 guide_control #(.CLOCK_HZ(20),.FADE_TICK(2)) dut(clk,rst,enabled,nt,hh,at,pt,rh,per,adone,aplaying,fb,page,auto_mode,paused,toggle,seconds,period,fade,zh,zoomw);
 reg kn=1;wire tap,hold;integer taps=0,holds=0;reg oldtoggle;
 guide_key #(.DEBOUNCE(3),.LONG(15)) key(clk,rst,kn,tap,hold);
 always @(posedge clk)begin if(tap)taps=taps+1;if(hold)holds=holds+1;end
 reg [2:0] last_page=0;integer n,nf=0;
 task frame;begin @(negedge clk);fb=1;@(negedge clk);fb=0;nf=nf+1;
  if(page!=last_page && fade!=8'd0)$fatal(1,"page switched before the fade-out finished (%0d)",fade);
  last_page=page;end endtask
 task frames;input integer k;integer i;begin for(i=0;i<k;i=i+1)frame();end endtask
 task wait_page;input [2:0] want;begin n=0;while(page!=want && n<300)begin frame();n=n+1;end
  if(page!=want)$fatal(1,"wait_page %0d got %0d",want,page);end endtask
 task wait_fade;begin n=0;while(fade!=8'd255 && n<300)begin frame();n=n+1;end
  if(fade!=8'd255)$fatal(1,"fade stuck at %0d",fade);end endtask
 initial begin
  #100;@(negedge clk)rst=0;enabled=1;repeat(3)@(negedge clk);frames(2);
  if(page!=0 || !toggle)$fatal(1,"welcome not started");
  // KEY2: fade out (~16 frames) -> page swap -> fade in (~16 frames)
  nt=1;@(negedge clk);nt=0;
  frames(6);if(page!=0 || fade>=8'd255)$fatal(1,"fade out never started");
  wait_page(1);wait_fade;
  $display("PASS fade transition: %0d frames for one page change",nf);
  // auto tour: narration must finish first, then a faded advance
  at=1;@(negedge clk);at=0;frames(230);
  if(page!=1 || !auto_mode)$fatal(1,"auto truncated narration");
  adone=1;repeat(2)@(negedge clk);wait_page(2);wait_fade;adone=0;
  $display("PASS auto advance through the fade");
  // pause / replay / home
  pt=1;@(negedge clk);pt=0;repeat(2)@(negedge clk);if(!paused)$fatal(1,"pause");
  oldtoggle=toggle;rh=1;@(negedge clk);rh=0;frame();wait_fade;
  if(paused || toggle==oldtoggle)$fatal(1,"replay");
  hh=1;@(negedge clk);hh=0;wait_page(0);wait_fade;
  if(auto_mode)$fatal(1,"home");
  per=60;#1;if(period!=60)$fatal(1,"period");
  // Bounce, short press and long press must have distinct events.
  kn=0;@(negedge clk);kn=1;@(negedge clk);kn=0;repeat(8)@(negedge clk);kn=1;repeat(8)@(negedge clk);
  if(taps!=1 || holds!=0)$fatal(1,"debounce %0d %0d",taps,holds);
  kn=0;repeat(30)@(negedge clk);kn=1;repeat(8)@(negedge clk);
  if(taps!=1 || holds!=1)$fatal(1,"long press duplicated");
  zh=1;@(negedge clk);zh=0;@(negedge clk);if(!zoomw)$fatal(1,"zoom on failed");
  zh=1;@(negedge clk);zh=0;@(negedge clk);if(zoomw)$fatal(1,"zoom off failed");
  $display("PASS control: fade transition, KEY3-long zoom toggle, narration-aware auto, replay/home, debounce/long press");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule