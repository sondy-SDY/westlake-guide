// 环境光 -> 屏幕数字亮度（0..256）。
//   · 分段映射（6 档），每档之间 1.2 倍迟滞，避免在手电/云影边缘来回跳；
//   · 每帧最多 ±STEP，约 0.5 s 走完一档（60 fps）；
//   · 第一帧有效 lux 直接跳到目标，避免开机时从 100% 慢慢暗下来；
//   · 紧急播报（emg=1）强制 100% —— 应急优先；
//   · 传感器没数据/出错时保持当前值（不闪、不乱跳）。
// 增益 256 = 原样输出（视频里 (c*256)>>8 == c）。
module guide_bright(
 input pclk,input prst,
 input [15:0] lux,input lux_valid,
 input emg,input frame_boundary,
 input manual,input [8:0] manual_gain,   // 开发者模式：手动亮度（1 = 手动）
 output reg [8:0] gain);
 localparam [8:0] G_NIGHT =9'd90;    // 35%  手捂/深夜
 localparam [8:0] G_DIM   =9'd128;   // 50%  暗房间
 localparam [8:0] G_IN    =9'd192;   // 75%  室内（你实测 70 lx 落这里）
 localparam [8:0] G_BRIGHT=9'd230;   // 90%  明亮室内/阴天
 localparam [8:0] G_SUN   =9'd248;   // 97%  强光
 localparam [8:0] G_FULL  =9'd256;   // 100% 户外直射
 localparam [8:0] STEP    =9'd2;     // 每帧 ±2（60 fps 下一档约 0.5 s）
 reg [2:0] zone;reg seen;
 // 迟滞：升档要 >= 阈值*1.2，降档要 < 阈值/1.2
 function [2:0] next_zone;input [2:0] z;input [15:0] l;begin
  case(z)
   0: next_zone=(l>=16'd6)?3'd1:3'd0;
   1: next_zone=(l>=16'd60)?3'd2:(l<16'd4)?3'd0:3'd1;
   2: next_zone=(l>=16'd360)?3'd3:(l<16'd42)?3'd1:3'd2;
   3: next_zone=(l>=16'd3600)?3'd4:(l<16'd250)?3'd2:3'd3;
   4: next_zone=(l>=16'd24000)?3'd5:(l<16'd2500)?3'd3:3'd4;
   5: next_zone=(l<16'd16667)?3'd4:3'd5;
   default:next_zone=3'd0;
  endcase
 end endfunction
 function [8:0] zone_gain;input [2:0] z;begin
  case(z)
   0:zone_gain=G_NIGHT;1:zone_gain=G_DIM;  2:zone_gain=G_IN;
   3:zone_gain=G_BRIGHT;4:zone_gain=G_SUN; default:zone_gain=G_FULL;
  endcase
 end endfunction
 // 上电第一帧直接按当前 lux 落档（不走迟滞的逐档步进），屏幕立刻匹配环境
 function [2:0] zone_of;input [15:0] l;begin
  if(l<16'd5) zone_of=3'd0;
  else if(l<16'd50) zone_of=3'd1;
  else if(l<16'd300) zone_of=3'd2;
  else if(l<16'd3000) zone_of=3'd3;
  else if(l<16'd20000) zone_of=3'd4;
  else zone_of=3'd5;
 end endfunction
 wire [2:0] nzone=next_zone(zone,lux);
 wire [8:0] want=emg?G_FULL:(manual?manual_gain:zone_gain(zone));
 always @(posedge pclk or posedge prst) begin
  if(prst) begin zone<=3'd0;seen<=1'b0;gain<=G_FULL;end
  else begin
   if(lux_valid) begin
    if(!seen) begin
     seen<=1'b1;zone<=zone_of(lux);
     gain<=emg?G_FULL:(manual?manual_gain:zone_gain(zone_of(lux)));
    end else zone<=nzone;
   end else if(frame_boundary) begin
    if(gain<want) gain<=(want-gain<=STEP)?want:gain+STEP;
    else if(gain>want) gain<=(gain-want<=STEP)?want:gain-STEP;
   end
  end
 end
endmodule
