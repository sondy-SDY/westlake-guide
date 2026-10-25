`timescale 1ns/1ps
// 广告平移切换（页 7 -> 8）：旧页往左走、新页从右边进。
// 假 SDRAM 按 (页,行) 现算数据：16bit 像素 = {page[3:0], x[9:0], 2'b00}，
// 逐像素核对 3 个采样行；同时统计每帧的取行请求数（平移时每行两份 = 960/帧）。
// SLIDE_STEPS 改成 4 只是缩短仿真时间（每帧 160 px），映射逻辑和默认 32 步完全一样。
module tb_ad_slide;
 reg pclk=0;always #20 pclk=~pclk;          // 25 MHz 像素时钟
 reg mclk=0;always #12 mclk=~mclk;          // 41.67 MHz 存储时钟
 reg prst=1,enabled=0;reg [3:0] page=4'd7;reg [8:0] bright=9'd256;
 wire frame_boundary,line_req,valid,user,last,vunder;
 wire [9:0] line_y;wire [3:0] line_page;
 wire [23:0] rgb;wire [7:0] rows_bad;
 reg line_ack=0,line_we=0;reg [8:0] line_addr=0;reg [31:0] line_data=0;
 guide_video_640 #(.SLIDE_STEPS(4)) video(.pclk(pclk),.prst(prst),.mclk(mclk),.enabled(enabled),.page(page),
  .load_index(4'd8),.error(8'd0),
  .frame_boundary(frame_boundary),.line_req(line_req),.line_y(line_y),.line_page(line_page),
  .line_ack(line_ack),.line_we(line_we),.line_addr(line_addr),.line_data(line_data),
  .valid(valid),.ready(1'b1),.user(user),.last(last),.rgb(rgb),.underrun(vunder),.rows_bad(rows_bad),
  .fade(8'd255),.zoom(1'b0),.auto_mode(1'b0),.paused(1'b0),.audio_playing(1'b0),.audio_done(1'b0),
  .osd_en(1'b0),.sample_valid(1'b0),.play_toggle(2'd0),.brightness(bright),.dev_row(3'd0),.dev_col(4'd0),.dev_sel(24'd0),.contrast(2'd1),.vu_on(1'b0),.sample(24'd0),.boot(1'b0),.boot_prog(4'd0));
 // ---- 假 guide_memory：请求 -> 3 拍后连发 320 字 -> 回一个 ack ----
 function [15:0] px(input [3:0] p,input [9:0] xx);begin px={p,xx,2'b00};end endfunction
 reg [2:0] st=0;reg [1:0] wc=0;reg [8:0] cnt=0;reg [3:0] pg=0;reg [9:0] ry=0;reg lr_d=0;
 always @(posedge mclk or posedge prst) begin
  if(prst) begin
   st<=0;wc<=0;cnt<=0;pg<=0;ry<=0;line_we<=0;line_addr<=0;line_data<=0;line_ack<=0;lr_d<=0;
  end else begin
   lr_d<=line_req;line_we<=0;
   case(st)
    0: if(line_req!=lr_d) begin pg<=line_page;ry<=line_y;cnt<=0;wc<=0;st<=1;end
    1: if(wc==2) st<=2;else wc<=wc+1'b1;
    2: begin
        line_we<=1;line_addr<=cnt;
        line_data<={px(pg,cnt*2+1),px(pg,cnt*2)};
        if(cnt==319) st<=3;else cnt<=cnt+1'b1;
       end
    3: begin line_ack<=~line_ack;st<=0;end
    default:st<=0;
   endcase
  end
 end
 // ---- 逐像素核对 + 每帧请求数 ----
 integer px_i=0,py_i=0,run_frame=0,checked=0,reqs=0,sxi=0,gx_i=0,wr=0,wg=0,wb=0;
 reg started=0,sliding=0;integer off_tb=0;reg [3:0] gp_ex;reg lr_q=0;
 reg [15:0] want16;reg [23:0] want;
 always @(posedge pclk) if(!prst) begin
  lr_q<=line_req;
  if(line_req!=lr_q) reqs=reqs+1;
  if(frame_boundary) begin
   // 这个边界之前数到的取行请求都属于刚结束的那一帧
   if(started && run_frame>=1) begin
    if(reqs!==((run_frame>=2&&run_frame<=6)?960:480))
     $fatal(1,"frame %0d: %0d line requests, want %0d",run_frame,reqs,
            (run_frame>=2&&run_frame<=6)?960:480);
   end
   reqs=0;
   if(started && run_frame==7) bright<=9'd128;   // 第 8 帧起把亮度降到 50%，验证增益
   if(started && run_frame>=8) begin
    $display("PASS ad slide: page 7->8, %0d pixels checked, 960 req/frame during slide",checked);
    $finish;
   end
  end
  if(valid && video.show) begin
   if(user) begin
    px_i=0;py_i=0;
    if(!started) begin started=1;run_frame=0;end
    else run_frame=run_frame+1;
    if(started && run_frame==1) page<=4'd8;      // 下一帧开始平移（run_frame=2 是第 1 个平移帧）
    sliding=(run_frame>=2 && run_frame<=6);
    off_tb=(run_frame-2)*160;
   end
   if(started && (py_i==0||py_i==240||py_i==479)) begin
    if(sliding) begin
     sxi=px_i+off_tb;                             // 拼图坐标 0..1279
     if(sxi<640) begin gp_ex=4'd7;gx_i=sxi;end
     else begin gp_ex=4'd8;gx_i=sxi-640;end
    end else begin
     gp_ex=(run_frame>=2)?4'd8:4'd7;gx_i=px_i;
    end
    want16={gp_ex,gx_i[9:0],2'b00};
    want={want16[15:11],want16[15:13],want16[10:5],want16[10:9],want16[4:0],want16[4:2]};
    if(bright!=9'd256) begin   // 视频在 OSD 之后做 (c*bright)>>8，这里同模型
     // 必须放到 integer 里算：{8bit*bright} 在拼接上下文是自决定宽度（9 bit），会截断
     wr=(want[23:16]*bright)>>8;wg=(want[15:8]*bright)>>8;wb=(want[7:0]*bright)>>8;
     want={wr[7:0],wg[7:0],wb[7:0]};
    end
    if(rgb!==want)
     $fatal(1,"frame %0d row %0d x %0d: rgb=%h want=%h (page %0d srcx %0d off %0d)",
            run_frame,py_i,px_i,rgb,want,gp_ex,gx_i,off_tb);
    checked=checked+1;
   end
   if(px_i==639) begin px_i=0;py_i=py_i+1;end else px_i=px_i+1;
  end
 end
 initial begin
  #200;@(negedge pclk);prst=0;
  @(negedge pclk);enabled=1;
 end
 initial begin #600000000;$fatal(1,"timeout");end
endmodule
