// 开发者模式菜单（SW1 拨上进入，最高优先级）。
//   · 三个可用按键（K1 是硬复位，不能当方向键）：K2 上移、K3 下移、K4 修改（循环取值）；
//   · 改动立即生效（亮度、对比度、PIR 延迟、音量、广告停留、轮播周期、音频可视化都直接接到各模块）；
//   · 设置掉电不保存（没有安全的 Flash 写入点），重启回默认；
//   · 光标停在"手动亮度"上按 K4 会自动切到手动模式；切手动时取当前实际亮度最接近的一档。
module guide_dev(
 input pclk,input prst,
 input sw_dev,                       // SW1（已两级同步+去抖），1 = 开发者模式
 input tap_up,input tap_dn,input tap_edit,
 input [8:0] cur_gain,               // 当前实际亮度（0..256）
 output dev,
 output reg [3:0] row,               // 0..8
 output reg [3:0] col,               // 当前行选中的选项序号
 output bright_manual,
 output [8:0] bright_gain,
 output [1:0] contrast,              // 0=0.75 1=1.0 2=1.25 3=1.5
 output [23:0] absent_frames,
 output [1:0] volume,
 output [23:0] ad_frames,
 output [6:0] period_s,
 output vu_on,
 output [23:0] sel);                 // 8 行的当前选项（各 3 bit）
 localparam [3:0] ROW_MODE=0,ROW_BRIGHT=1,ROW_CON=2,ROW_PIR=3,ROW_VOL=4,ROW_AD=5,ROW_PER=6,ROW_VU=7,ROW_RESET=8;
 localparam [3:0] ROW_LAST=8;
 // 默认：自动亮度 / 手动 75% / 对比度 100% / PIR 20 s / 音量满 / 广告 12 s / 周期 20 s / 可视化开
 reg i_mode;reg [2:0] i_bright;reg [1:0] i_con;reg [2:0] i_pir;reg [1:0] i_vol;reg [1:0] i_ad;reg [1:0] i_per;reg i_vu;
 reg dev_r;
 assign dev=dev_r;
 assign vu_on=i_vu;
 assign contrast=i_con;
 assign sel={{2'b0,i_vu},{1'b0,i_per},{1'b0,i_ad},{1'b0,i_vol},i_pir,{1'b0,i_con},i_bright,{2'b0,i_mode}};
 // 当前行的选项序号（给屏上红框用；恢复默认行没有选项）
 always @* begin
  case(row)
   ROW_MODE:   col={3'b0,i_mode};
   ROW_BRIGHT: col={1'b0,i_bright};
   ROW_CON:    col={2'b0,i_con};
   ROW_PIR:    col={1'b0,i_pir};
   ROW_VOL:    col={2'b0,i_vol};
   ROW_AD:     col={2'b0,i_ad};
   ROW_PER:    col={2'b0,i_per};
   ROW_VU:     col={3'b0,i_vu};
   default:    col=4'd0;
  endcase
 end
 assign bright_manual=i_mode;
 // 5 档手动亮度：35/50/75/90/100 % -> 90/128/192/230/256
 assign bright_gain = (i_bright==3'd0) ? 9'd90  :
                      (i_bright==3'd1) ? 9'd128 :
                      (i_bright==3'd2) ? 9'd192 :
                      (i_bright==3'd3) ? 9'd230 : 9'd256;
 // PIR 延迟 5/10/20/30/60/90/120 s -> 帧数（60 fps）
 assign absent_frames = (i_pir==3'd0) ? 24'd300  :
                        (i_pir==3'd1) ? 24'd600  :
                        (i_pir==3'd2) ? 24'd1200 :
                        (i_pir==3'd3) ? 24'd1800 :
                        (i_pir==3'd4) ? 24'd3600 :
                        (i_pir==3'd5) ? 24'd5400 : 24'd7200;
 assign volume = i_vol;
 // 广告停留 8/12/20 s -> 帧数
 assign ad_frames = (i_ad==2'd0) ? 24'd480 : (i_ad==2'd1) ? 24'd720 : 24'd1200;
 // 轮播周期 10/20/30/60 s
 assign period_s = (i_per==2'd0) ? 7'd10 : (i_per==2'd1) ? 7'd20 :
                   (i_per==2'd2) ? 7'd30 : 7'd60;
 // 切手动时取当前亮度最接近的一档（90/128/192/230/256 的中点 109/160/211/243）
 function [2:0] snap;input [8:0] g;begin
  snap = (g<9'd109) ? 3'd0 : (g<9'd160) ? 3'd1 : (g<9'd211) ? 3'd2 :
         (g<9'd243) ? 3'd3 : 3'd4;
 end endfunction
 always @(posedge pclk or posedge prst) begin
  if(prst) begin
   dev_r<=0;row<=0;i_mode<=0;i_bright<=3'd2;i_con<=2'd1;i_pir<=3'd2;i_vol<=2'd2;i_ad<=2'd1;i_per<=2'd1;i_vu<=1;
  end else begin
   dev_r<=sw_dev;
   if(!sw_dev) begin
    row<=0;                                  // 退出时下次进来回到第一行
   end else begin
    if(sw_dev && !dev_r) row<=0;             // 刚进开发者模式：光标归零
    if(tap_up) row<=(row==4'd0) ? ROW_LAST : row-1'b1;
    if(tap_dn) row<=(row==ROW_LAST) ? 4'd0 : row+1'b1;
    if(tap_edit) begin
     case(row)
      ROW_MODE:begin
       i_mode<=~i_mode;
       if(!i_mode) i_bright<=snap(cur_gain); // 切到手动：从当前亮度就近取档
      end
      ROW_BRIGHT:begin i_mode<=1'b1;i_bright<=(i_bright==3'd4) ? 3'd0 : i_bright+1'b1;end
      ROW_CON:   i_con<=(i_con==2'd3) ? 2'd0 : i_con+1'b1;
      ROW_PIR:   i_pir<=(i_pir==3'd6) ? 3'd0 : i_pir+1'b1;
      ROW_VOL:   i_vol<=(i_vol==2'd2) ? 2'd0 : i_vol+1'b1;
      ROW_AD:    i_ad<=(i_ad==2'd2) ? 2'd0 : i_ad+1'b1;
      ROW_PER:   i_per<=(i_per==2'd3) ? 2'd0 : i_per+1'b1;
      ROW_VU:    i_vu<=~i_vu;
      ROW_RESET:begin                          // 恢复默认
       i_mode<=0;i_bright<=3'd2;i_con<=2'd1;i_pir<=3'd2;i_vol<=2'd2;i_ad<=2'd1;i_per<=2'd1;i_vu<=1;
      end
      default:;
     endcase
    end
   end
  end
 end
endmodule
