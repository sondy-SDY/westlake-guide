// 【已停用】被 guide_caption.v（字库引擎）取代，不在 640 工程的构建列表里。
// 保留只是为了回退：改 generate_project_640.py 的文件列表 + guide_video_640 的例化即可。
// 640x480 信息栏底部文字条（y 448..466）：纸色底上直接叠深墨色 2bit 抗锯齿字。
// 与视频同一拍流水：t 出掩膜地址，t+1 掩膜与卡片像素同时到，直接混合。
// 注意：ROM 深度 1620 -> 地址 11 位，位宽必须与深度匹配，否则 TD 会降级成分布式 RAM。
module guide_osd(input pclk,input active,input [9:0] x,input [9:0] y,input en,
 input auto_mode,input paused,input audio_playing,input audio_done,
 output [1:0] alpha,output [23:0] ink,output on);
 wire [3:0] id;wire [7:0] lx;wire [4:0] ly;wire [10:0] base;wire [4:0] stride;
 guide_osd_sel sel(.x(x),.y(y),.auto_mode(auto_mode),.paused(paused),
  .audio_playing(audio_playing),.audio_done(audio_done),.id(id),.lx(lx),.ly(ly));
 guide_osd_base bs(.id(id),.base(base),.stride(stride));
 wire [10:0] addr=base+ly*stride+lx[7:3];
 wire [15:0] td;
 guide_osd_rom rom(.clk(pclk),.ta(addr),.td(td));
 reg [2:0] lxq;reg on_q;
 always @(posedge pclk) if(active) begin
  lxq<=lx[2:0];on_q<=(id!=4'hf);
 end
 assign on=on_q&&en;
 assign alpha=(on_q&&en)?td[{1'b0,lxq}*2 +: 2]:2'd0;
 assign ink=24'h2b3836;      // 墨色，和卡片正文同色
endmodule
