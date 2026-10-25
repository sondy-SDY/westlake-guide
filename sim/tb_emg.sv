`timescale 1ns/1ps
// 紧急播报状态机：长按进入、再长按退出、紧急态短按重播（tick 翻转）
module tb_emg;
 reg clk=0;always #5 clk=~clk;
 reg prst=1,enable=0,hold=0,tap=0;
 wire emg,tick;wire [3:0] page;
 guide_emg u(.pclk(clk),.prst(prst),.enable(enable),.hold(hold),.tap(tap),
  .emg(emg),.emg_page(page),.tick(tick));
 integer ticks=0,step=0;
 always @(posedge clk) if(tick) ticks=ticks+1;
 task pulse_hold;begin hold=1;@(posedge clk);hold=0;@(posedge clk);end endtask
 task pulse_tap;begin tap=1;@(posedge clk);tap=0;@(posedge clk);end endtask
 task chk;input v;begin
  if(emg!==v)$fatal(1,"step %0d: emg=%b want=%b ticks=%0d",step,emg,v,ticks);
  step=step+1;
 end endtask
 initial begin
  @(negedge clk);prst=0;@(negedge clk);@(negedge clk);
  chk(0);                                   // 上电是导览态
  if(page!==4'd6)$fatal(1,"emg page %0d",page);
  pulse_hold; chk(0);                       // 资源没装载完，长按不响应
  enable=1;
  pulse_hold; chk(1);                       // 进入紧急
  pulse_tap;  chk(1);                       // 紧急态短按：重播，不退出
  if(ticks<2)$fatal(1,"tick did not toggle %0d",ticks);
  pulse_hold; chk(0);                       // 再长按退出
  if(ticks<3)$fatal(1,"tick did not toggle on exit %0d",ticks);
  pulse_tap;  chk(0);                       // 导览态短按不影响
  $display("PASS emg: enter/exit/replay/disabled-guard, tick toggles=%0d",ticks);
  $finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
