// 音频频谱柱（8 段滤波器组版）：8 个一阶低通组成对数频段（约 30 Hz..3.8 kHz + 高频残余），
// 相邻低通之差 = 该频段能量（有符号运算）；取绝对值平滑后按 6 dB 一档映射成柱高 0..32 px。
// 屏幕 64 根柱（10 px 间距），第 j 段和第 j+1 段之间按 8 根柱线性插值，
// 柱高在帧边界锁存一次，帧内不变。输出给 guide_video_640 画"底部在 y=360 上方"的柱状图。
module guide_wave(
 input pclk,input prst,
 input sample_valid,input [23:0] sample,
 input frame_boundary,
 input [5:0] bx,                     // 0..63
 output reg [5:0] hgt);              // 0..32 px
 wire signed [16:0] xs={sample[23],sample[23:8]};
 // 8 个一阶低通：k=1 最快（约 3.8 kHz）.. k=8 最慢（约 30 Hz）
 reg signed [15:0] lp1,lp2,lp3,lp4,lp5,lp6,lp7,lp8;
 wire signed [16:0] d1=xs-lp1, d2=xs-lp2, d3=xs-lp3, d4=xs-lp4;
 wire signed [16:0] d5=xs-lp5, d6=xs-lp6, d7=xs-lp7, d8=xs-lp8;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin lp1<=0;lp2<=0;lp3<=0;lp4<=0;lp5<=0;lp6<=0;lp7<=0;lp8<=0;end
  else if(sample_valid) begin
   // 右移后的差值必须符号扩展再相加，否则负差值会被当成大的正数（滤波发散）
   lp1<=lp1+{{0{d1[16]}},d1[16:1]};
   lp2<=lp2+{{1{d2[16]}},d2[16:2]};
   lp3<=lp3+{{2{d3[16]}},d3[16:3]};
   lp4<=lp4+{{3{d4[16]}},d4[16:4]};
   lp5<=lp5+{{4{d5[16]}},d5[16:5]};
   lp6<=lp6+{{5{d6[16]}},d6[16:6]};
   lp7<=lp7+{{6{d7[16]}},d7[16:7]};
   lp8<=lp8+{{7{d8[16]}},d8[16:8]};
  end
 end
 // 频段能量 = 相邻低通之差（17 位有符号），取绝对值后做一阶平滑（约 2.7 ms）
 wire signed [16:0] bd1={lp8[15],lp8}-{lp7[15],lp7};
 wire signed [16:0] bd2={lp7[15],lp7}-{lp6[15],lp6};
 wire signed [16:0] bd3={lp6[15],lp6}-{lp5[15],lp5};
 wire signed [16:0] bd4={lp5[15],lp5}-{lp4[15],lp4};
 wire signed [16:0] bd5={lp4[15],lp4}-{lp3[15],lp3};
 wire signed [16:0] bd6={lp3[15],lp3}-{lp2[15],lp2};
 wire signed [16:0] bd7={lp2[15],lp2}-{lp1[15],lp1};
 wire signed [16:0] bd8=xs-{lp1[15],lp1};
 wire [16:0] a1=bd1[16]?(-bd1):bd1;
 wire [16:0] a2=bd2[16]?(-bd2):bd2;
 wire [16:0] a3=bd3[16]?(-bd3):bd3;
 wire [16:0] a4=bd4[16]?(-bd4):bd4;
 wire [16:0] a5=bd5[16]?(-bd5):bd5;
 wire [16:0] a6=bd6[16]?(-bd6):bd6;
 wire [16:0] a7=bd7[16]?(-bd7):bd7;
 wire [16:0] a8=bd8[16]?(-bd8):bd8;
 reg [16:0] s1,s2,s3,s4,s5,s6,s7,s8;
 wire signed [17:0] e1=$signed({1'b0,a1})- $signed({1'b0,s1});
 wire signed [17:0] e2=$signed({1'b0,a2})- $signed({1'b0,s2});
 wire signed [17:0] e3=$signed({1'b0,a3})- $signed({1'b0,s3});
 wire signed [17:0] e4=$signed({1'b0,a4})- $signed({1'b0,s4});
 wire signed [17:0] e5=$signed({1'b0,a5})- $signed({1'b0,s5});
 wire signed [17:0] e6=$signed({1'b0,a6})- $signed({1'b0,s6});
 wire signed [17:0] e7=$signed({1'b0,a7})- $signed({1'b0,s7});
 wire signed [17:0] e8=$signed({1'b0,a8})- $signed({1'b0,s8});
 always @(posedge pclk or posedge prst) begin
  if(prst) begin s1<=0;s2<=0;s3<=0;s4<=0;s5<=0;s6<=0;s7<=0;s8<=0;end
  else if(sample_valid) begin
   s1<=s1+{{5{e1[17]}},e1[17:6]}; s2<=s2+{{5{e2[17]}},e2[17:6]};
   s3<=s3+{{5{e3[17]}},e3[17:6]}; s4<=s4+{{5{e4[17]}},e4[17:6]};
   s5<=s5+{{5{e5[17]}},e5[17:6]}; s6<=s6+{{5{e6[17]}},e6[17:6]};
   s7<=s7+{{5{e7[17]}},e7[17:6]}; s8<=s8+{{5{e8[17]}},e8[17:6]};
  end
 end
 // 幅度 -> 柱高：取最高有效位，6 dB 一档，每档 4 px（最大 32）
 function [5:0] hgt_of;input [16:0] e;reg [3:0] ex;begin
  if(e[15]) ex=4'd15; else if(e[14]) ex=4'd14; else if(e[13]) ex=4'd13;
  else if(e[12]) ex=4'd12; else if(e[11]) ex=4'd11; else if(e[10]) ex=4'd10; else if(e[9]) ex=4'd9;
  else if(e[8]) ex=4'd8; else if(e[7]) ex=4'd7; else if(e[6]) ex=4'd6; else if(e[5]) ex=4'd5;
  else if(e[4]) ex=4'd4; else if(e[3]) ex=4'd3; else if(e[2]) ex=4'd2; else if(e[1]) ex=4'd1;
  else ex=4'd0;
  hgt_of=(ex>=4'd4)?({2'd0,ex-4'd4}<<2):6'd0;   // 4 px 一档，最大 44（ex=15）
 end endfunction
 // 帧边界锁存 8 个频段高度
 reg [5:0] h1,h2,h3,h4,h5,h6,h7,h8;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin h1<=0;h2<=0;h3<=0;h4<=0;h5<=0;h6<=0;h7<=0;h8<=0;end
  else if(frame_boundary) begin
   h1<=hgt_of(s1); h2<=hgt_of(s2); h3<=hgt_of(s3); h4<=hgt_of(s4);
   h5<=hgt_of(s5); h6<=hgt_of(s6); h7<=hgt_of(s7); h8<=hgt_of(s8);
  end
 end
 // 每根柱：第 j=bx[5:3] 段到第 j+1 段之间按 bx[2:0] 线性插值
 wire [2:0] j=bx[5:3];
 wire [2:0] t=bx[2:0];
 reg [5:0] hj,hj1;
 always @* begin
  case(j)
   3'd0:begin hj=h1;hj1=h2;end 3'd1:begin hj=h2;hj1=h3;end
   3'd2:begin hj=h3;hj1=h4;end 3'd3:begin hj=h4;hj1=h5;end
   3'd4:begin hj=h5;hj1=h6;end 3'd5:begin hj=h6;hj1=h7;end
   3'd6:begin hj=h7;hj1=h8;end default:begin hj=h8;hj1=h8;end
  endcase
 end
 wire signed [6:0] diff=$signed({1'b0,hj1})- $signed({1'b0,hj});
 wire signed [9:0] adj=($signed({3'd0,t})*diff)>>>3;
 wire [5:0] hcur=hj+adj[5:0];
 // 上电前 0.5 s 不显示（滤波器还没稳）
 reg [15:0] warm;
 always @(posedge pclk or posedge prst) if(prst) warm<=0;else if(sample_valid&&warm!=16'hffff) warm<=warm+1'b1;
 always @(posedge pclk) hgt<=(warm>=16'd24000)?hcur:6'd0;
endmodule
