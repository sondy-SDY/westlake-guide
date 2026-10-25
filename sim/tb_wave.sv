`timescale 1ns/1ps
// 音频频谱：100 Hz 正弦 -> 低频段高；4.8 kHz 正弦 -> 高频段高；采样率按 25 MHz/520 = 48 kHz 送。
module tb_wave;
 reg pclk=0;always #20 pclk=~pclk;
 reg prst=1,sv=0,fb=0;reg [23:0] sample=0;reg [5:0] bx=0;
 wire [5:0] hgt;
 guide_wave dut(.pclk(pclk),.prst(prst),.sample_valid(sv),.sample(sample),
  .frame_boundary(fb),.bx(bx),.hgt(hgt));
 real ph;integer i,v;
 task feed(input integer n,input real freq);begin
  for(i=0;i<n;i=i+1)begin
   ph=6.283185307179586*freq*(i/48000.0);
   v=$rtoi(28000.0*$sin(ph));
   repeat(520)@(negedge pclk);
   sample={v[15:0],8'd0};sv=1;@(negedge pclk);sv=0;
   if(((i+1)%800)==0)begin fb=1;@(negedge pclk);fb=0;end
  end
 end endtask
 task rdh(input [5:0] b,output [5:0] v);begin @(negedge pclk);bx=b;repeat(2)@(negedge pclk);v=hgt;end endtask
 reg [5:0] a1,a2,a4,a7,a8,b1,b2,b7,b8;
 initial begin
  @(negedge pclk);prst=0;@(negedge pclk);
  feed(24000,100.0);
  rdh(6'd4,a1); rdh(6'd12,a2); rdh(6'd28,a4); rdh(6'd52,a7); rdh(6'd60,a8);
  $display("100Hz: b1=%0d b2=%0d b4=%0d b7=%0d b8=%0d",a1,a2,a4,a7,a8);
  if(!(a2>a8+6))$fatal(1,"100 Hz should favour band 2 over band 8");
  feed(24000,4800.0);
  rdh(6'd4,b1); rdh(6'd12,b2); rdh(6'd52,b7); rdh(6'd60,b8);
  $display("4.8k:  b1=%0d b2=%0d b7=%0d b8=%0d",b1,b2,b7,b8);
  if(!(b8>b2+6))$fatal(1,"4.8 kHz should favour band 8 over band 2");
  if(a2>6'd44||a8>6'd44||b2>6'd44||b8>6'd44)$fatal(1,"height over 44");
  $display("PASS wave: 8-band filter bank, band lerp, 0..44 px");
  $finish;
 end
 initial begin #2000000000;$fatal(1,"timeout");end
endmodule
