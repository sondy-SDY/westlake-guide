// 字幕时间轴：数"真正播出去的采样"，每 12000 个（48 kHz 下 0.25 s）进一格，
// 用 {page, slot} 查表得到该显示第几行字幕。
//
// 为什么数采样而不是用 guide_control 的 seconds：rp 只在 playing && !paused 时前进，
// 所以这个计数和"观众听到的位置"严格同源——暂停、欠载、重播都不会漂。
module guide_subs(input pclk,input prst,input sample_valid,input playing,input paused,
 input [1:0] play_toggle,input [3:0] page,output [3:0] line);
 localparam [13:0] SLOT_SAMPLES=14'd11999;   // 0..11999 共 12000 个采样 = 0.25 s
 reg [1:0] ptog;reg [13:0] acc;reg [6:0] slot;
 wire restart=(ptog!=play_toggle);
 always @(posedge pclk or posedge prst) begin
  if(prst) begin ptog<=0;acc<=0;slot<=0;end
  else begin
   ptog<=play_toggle;
   if(restart) begin acc<=0;slot<=0;end          // 换页/重播：时间轴从头来
   else if(sample_valid&&playing&&!paused) begin
    if(acc==SLOT_SAMPLES) begin acc<=0;if(slot!=7'h7f)slot<=slot+1'b1;end
    else acc<=acc+1'b1;
   end
  end
 end
 guide_tl_rom tl(.clk(pclk),.a({page,slot}),.d(line));
endmodule
