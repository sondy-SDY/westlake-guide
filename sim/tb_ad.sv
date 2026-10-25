`timescale 1ns/1ps
// 红外/无人广告状态机：无人才进、有人立刻走、拨码强制、广告按时轮播，
// 并且只有"讲解播完 + 帧边界"才允许超时接管（BUG-4）。
module tb_ad;
 reg clk=0;always #5 clk=~clk;
 reg prst=1,fb=0,motion=0,fsw=0,enable=0,ndone=0;
 reg [23:0] ta=24'd10,tad=24'd3;          // 运行时参数：无人 10 帧、广告 3 帧
 wire ad,tick;wire [3:0] page;
 guide_ad u(.pclk(clk),.prst(prst),.frame_boundary(fb),
  .motion(motion),.force_absent(fsw),.enable(enable),.narration_done(ndone),
  .absent_frames(ta),.ad_frames(tad),
  .ad(ad),.ad_page(page),.tick(tick));
 integer i,st=0;
 task frm;begin @(negedge clk);fb=1;@(negedge clk);fb=0;end endtask
 task chk;input v;input [3:0] p;begin
  if(ad!==v||page!==p)$fatal(1,"step %0d: ad=%b page=%0d want %b/%0d",st,ad,page,v,p);
  st=st+1;
 end endtask
 initial begin
  @(negedge clk);prst=0;@(negedge clk);
  frm; chk(0,4'd7);                    // 没使能：不动
  enable=1;
  repeat(12) frm; chk(0,4'd7);         // 无人已超过 T_ABSENT，但讲解没结束 -> 不打断
  ndone=1;
  repeat(5) @(negedge clk); chk(0,4'd7);   // 只认帧边界：帧内不切
  frm; chk(0,4'd7);                    // 讲解结束后的第 1 个边界：先记住"已结束"
  frm; chk(1,4'd7);                    // 第 2 个边界（连续两帧结束）才接管，不用再等 120 s
  ndone=0;
  repeat(3) frm; chk(1,4'd8);          // 轮播到第 8 页
  repeat(3) frm; chk(1,4'd9);          // 第 9 页
  repeat(3) frm; chk(1,4'd7);          // 回卷到第 7 页
  motion=1; frm; chk(0,4'd7);          // 有人：立刻退出
  motion=0;ndone=1;
  repeat(10) frm; chk(0,4'd7);         // 计时重新开始：10 帧内不回来
  frm; chk(1,4'd7);                    // 第 11 个帧边界：last 已到 10，判定通过
  ndone=0;
  motion=1; frm; chk(0,4'd7);motion=0; // 再清一次
  ndone=1;
  fsw=1; frm; chk(1,4'd7);             // 拨码强制：只要求帧边界，讲解在播也进
  repeat(2) frm; fsw=0; frm; chk(0,4'd7);   // 拨回来：退出
  repeat(3) frm; chk(0,4'd7);          // 退出时计时清零：讲解已结束也不会马上弹回广告
  repeat(6) frm; chk(0,4'd7);          // 清零后重新数：没人到 10 帧就不再进
  frm; chk(1,4'd7);                    // 数满 10 帧后的下一个边界才允许再进
  $display("PASS ad: absent-timeout+gating, frame edge, rotation, motion-exit, fsw switch, exit-reset");
  $finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
