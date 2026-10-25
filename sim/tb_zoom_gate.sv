`timescale 1ns/1ps
// BUG-3 回归：KEY3 长按的 4/3 缩放只作用于导览页 1..5。
// 像素映射已经由 tb_video_640 逐点验过，这里只看每帧发出的取行请求：
// 缩放页 4 个显示行才换 3 次源行，其余页每个显示行都换源行。
// 把整帧的 (line_y) 序列和模型逐项比对，"页面没缩放"才算过。
module tb_zoom_gate;
 reg pclk=0;always #20 pclk=~pclk;            // 25 MHz 像素时钟
 reg mclk=0;always #12 mclk=~mclk;            // 行缓冲写时钟（本 TB 不写行数据）
 reg prst=1,enabled=0,zoom=0,osd_en=0;reg [3:0] page=0;
 wire frame_boundary,line_req,valid,user,last,vunder;
 wire [9:0] line_y;wire [3:0] line_page;
 wire [23:0] rgb;wire [7:0] rows_bad;
 reg line_ack=0;
 guide_video_640 video(.pclk(pclk),.prst(prst),.mclk(mclk),.enabled(enabled),.page(page),
  .load_index(4'd8),.error(8'd0),
  .frame_boundary(frame_boundary),.line_req(line_req),.line_y(line_y),.line_page(line_page),
  .line_ack(line_ack),.line_we(1'b0),.line_addr(9'd0),.line_data(32'd0),
  .valid(valid),.ready(1'b1),.user(user),.last(last),.rgb(rgb),.underrun(vunder),.rows_bad(rows_bad),
  .fade(8'd255),.zoom(zoom),.auto_mode(1'b0),.paused(1'b0),.audio_playing(1'b0),.audio_done(1'b0),
  .osd_en(osd_en),.sample_valid(1'b0),.play_toggle(2'd0),.brightness(9'd256),.dev_row(3'd0),.dev_col(4'd0),.dev_sel(24'd0),.contrast(2'd1),.vu_on(1'b0),.sample(24'd0),.boot(1'b0),.boot_prog(4'd0));
 // 取行应答：请求翻转后第 2 拍回一个 ack，避免 pending 卡住后续预取
 reg lr_d=0,ack_wait=0;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin lr_d<=0;ack_wait<=0;line_ack<=0;end
  else begin
   lr_d<=line_req;
   if(line_req!=lr_d) ack_wait<=1'b1;
   else if(ack_wait) begin line_ack<=~line_ack;ack_wait<=0;end
  end
 end
 // 记录本帧每一次取行请求的源行号
 integer nreq=0;reg [9:0] req[0:1023];reg lr_c=0;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin lr_c<=0;nreq<=0;end
  else begin
   lr_c<=line_req;
   if(line_req!=lr_c) begin req[nreq]<=line_y;nreq<=nreq+1;end
  end
 end
 integer i;
 // 一帧 = 从帧边界到下一个帧边界；行 0 在 vblank 预取，之后每个"源行变了"的显示行各一次
 task check_case(input [3:0] pg,input z);
  integer y,sy0,sy1,k,zoom_ok;
  begin
   page=pg;zoom=z;
   zoom_ok=(z!=0)&&(pg>=4'd1)&&(pg<=4'd5);
   wait(frame_boundary);@(negedge pclk);nreq=0;   // 本帧边界已到，清计数器
   wait(!frame_boundary);                          // 让边界脉冲先过去
   wait(frame_boundary);@(negedge pclk);           // 下一帧边界：本帧请求已发完
   k=1;
   if(nreq>1023)$fatal(1,"too many requests %0d",nreq);
   if(req[0]!==10'd0)$fatal(1,"page %0d: first prefetch is line %0d, want 0",pg,req[0]);
   for(y=0;y<479;y=y+1) begin
    sy0=zoom_ok?((3*y)>>2):y;
    sy1=zoom_ok?((3*(y+1))>>2):(y+1);
    if(sy1!=sy0) begin
     if(k>=nreq)$fatal(1,"page %0d zoom %0d: only %0d requests, want more",pg,z,nreq);
     if(req[k]!==sy1[9:0])$fatal(1,"page %0d zoom %0d: request %0d is line %0d, want %0d",pg,z,k,req[k],sy1);
     k=k+1;
    end
   end
   if(k!=nreq)$fatal(1,"page %0d zoom %0d: %0d requests, want %0d (zoom applied=%0d)",pg,z,nreq,k,zoom_ok);
   $display("PASS page %0d zoom %0d: %0d line requests, sequence matches (zoomed=%0d)",pg,z,nreq,zoom_ok);
  end
 endtask
 initial begin
  #200;@(negedge pclk);prst=0;
  @(negedge pclk);enabled=1;
  wait(video.show);                                // 装载完成、首帧边界后开始显示
  check_case(4'd0,1'b1);                           // 路线图：长按放大不生效
  check_case(4'd1,1'b1);                           // 导览页：4/3 放大
  check_case(4'd6,1'b1);                           // 紧急页：不放大
  check_case(4'd7,1'b1);                           // 广告页：不放大
  check_case(4'd1,1'b0);                           // 关掉放大：回到 1:1
  check_case(4'd5,1'b1);                           // 导览第 5 站：放大生效（边界）
  $display("PASS zoom gate: 4/3 zoom only on guide pages 1..5");$finish;
 end
 initial begin #600000000;$fatal(1,"timeout");end
endmodule
