`timescale 1ns/1ps
// 环境光 -> 亮度映射：6 档 + 1.2 倍迟滞 + 每帧 ±2 渐变 + 紧急播报强制 100%。
module tb_bright;
 reg pclk=0;always #20 pclk=~pclk;     // 25 MHz
 reg prst=1,lux_valid=0,emg=0,fb=0;reg [15:0] lux=0;
 reg manual=0;reg [8:0] mg=9'd230;       // 开发者模式：手动亮度
 wire [8:0] gain;
 guide_bright dut(.pclk(pclk),.prst(prst),.lux(lux),.lux_valid(lux_valid),
  .emg(emg),.frame_boundary(fb),.manual(manual),.manual_gain(mg),.gain(gain));
 task set_lux(input [15:0] l);begin
  @(negedge pclk);lux=l;lux_valid=1;@(negedge pclk);lux_valid=0;
 end endtask
 task frames(input integer n);integer i;begin
  for(i=0;i<n;i=i+1)begin @(negedge pclk);fb=1;@(negedge pclk);fb=0;end
 end endtask
 initial begin
  @(negedge pclk);prst=0;@(negedge pclk);
  if(gain!==9'd256)$fatal(1,"reset gain %0d",gain);
  set_lux(16'd70);                       // 室内 70 lx -> 第 2 档 192，第一次直接到位
  @(negedge pclk);if(gain!==9'd192)$fatal(1,"first lux gain %0d",gain);
  set_lux(16'd400);                      // 升档：>=360 -> 230
  frames(30);if(gain!==9'd230)$fatal(1,"ramp up %0d",gain);
  set_lux(16'd340);                      // 迟滞：340<360 但 >250，留在原档
  frames(10);if(gain!==9'd230)$fatal(1,"hysteresis stay %0d",gain);
  set_lux(16'd200);                      // 降档：<250 -> 192
  frames(30);if(gain!==9'd192)$fatal(1,"ramp down %0d",gain);
  set_lux(16'd0);set_lux(16'd0);set_lux(16'd0);   // 手捂：逐档落到第 0 档
  frames(60);if(gain!==9'd90)$fatal(1,"night %0d",gain);
  repeat(5) set_lux(16'd50000);          // 强光：逐档升到第 5 档
  frames(100);if(gain!==9'd256)$fatal(1,"sun %0d",gain);
  emg=1;repeat(6) set_lux(16'd0);        // 紧急播报：强制 100%
  frames(100);if(gain!==9'd256)$fatal(1,"emg full %0d",gain);
  emg=0;frames(100);if(gain!==9'd90)$fatal(1,"emg off back %0d",gain);
  manual=1;frames(100);if(gain!==9'd230)$fatal(1,"manual 90%% %0d",gain);
  mg=9'd90;frames(100);if(gain!==9'd90)$fatal(1,"manual 35%% %0d",gain);
  manual=0;frames(100);if(gain!==9'd90)$fatal(1,"auto back %0d",gain);
  $display("PASS bright: 6 zones, 1.2x hysteresis, slew +-2/frame, emergency full, manual override");
  $finish;
 end
 initial begin #2000000;$fatal(1,"timeout gain=%0d",gain);end
endmodule
