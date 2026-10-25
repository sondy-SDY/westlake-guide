// 字库字幕引擎：文本 ROM 查字码 -> 字库 ROM 查点阵行 -> 取 2bit 灰度。
// 两级同步 ROM，整条链 2 拍；guide_video_640 把像素流水线再延 1 拍对齐。
//
// 一条链里塞两个互不重叠的 x 区间（所以每个像素只需要查一次 ROM）：
//   字幕区 x 24..279   每页第 N 行字幕
//   状态区 x 316..459  自动轮播/手动浏览 · 讲解中/已暂停/待播放/结束
module guide_caption(input pclk,input active,input [9:0] x,input [9:0] y,input en,
 input [3:0] page,input [3:0] line,input auto_mode,input paused,input audio_done,input audio_playing,
 output [1:0] alpha,output on);
 localparam [9:0] CAP_X0=10'd24, CAP_X1=10'd280;
 localparam [9:0] STA_X0=10'd316,STA_X1=10'd460;
 localparam [9:0] BAND_Y0=10'd450,BAND_Y1=10'd466;
 localparam [10:0] STATUS_BASE=11'd960;

 wire in_cap=(x>=CAP_X0)&&(x<CAP_X1)&&(y>=BAND_Y0)&&(y<BAND_Y1);
 wire in_st =(x>=STA_X0)&&(x<STA_X1)&&(y>=BAND_Y0)&&(y<BAND_Y1);

 wire [9:0] lx = in_cap ? (x-CAP_X0) : (x-STA_X0);
 wire [3:0] gi = lx[7:4];          // 行内第几个字（0..15）
 wire [3:0] cx = lx[3:0];          // 字内第几列
 wire [3:0] ly = y-BAND_Y0;

 // 字幕行由时间轴给出：每页 12 行 × 16 字 = 192 字一格
 wire [10:0] cap_base = ({8'd0,page}-11'd1)*11'd192 + ({7'd0,line}<<4);
 wire [3:0] slot = paused       ? (auto_mode?4'd3:4'd4)
                 : audio_done   ? 4'd7
                 : audio_playing? (auto_mode?4'd1:4'd2)
                 :                (auto_mode?4'd5:4'd6);
 wire [10:0] taddr = (in_cap?cap_base:STATUS_BASE+({6'd0,slot}<<4)) + {7'd0,gi};

 wire [15:0] tq;
 guide_text_rom u_txt(.clk(pclk),.a(taddr),.d(tq));

 reg [3:0] ly_q,cx_q,cx_qq;
 reg vld_q,vld_qq;
 always @(posedge pclk) if(active) begin
  ly_q<=ly; cx_q<=cx; vld_q<=en&&(in_cap||in_st);
  cx_qq<=cx_q; vld_qq<=vld_q;
 end

 wire [12:0] faddr={tq[8:0],ly_q};
 wire [31:0] gq;
 guide_font_rom u_font(.clk(pclk),.a(faddr),.d(gq));

 assign alpha=(vld_qq&&en)?gq[{1'b0,cx_qq}*2 +: 2]:2'd0;
 assign on=vld_qq&&en;
endmodule
