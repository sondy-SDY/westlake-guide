// 640x480@60 视频源：整屏就是一张 640x480 卡片，SDRAM 一行 320 字。
// 时序与教程 lab_ex4/5 完全一致：H 640+16+96+48=800，V 480+10+2+33=525，像素时钟 25 MHz。
// 装载完成前显示纸色底 + 进度条；某行取数迟到则整行画朱红，便于区分取数与数据问题。
// 广告页 7..9 之间换页做水平平移（push）：旧页往左走、新页从右边进。两页在同一帧都要取行，
// 所以行缓冲是 2 个 slot（旧/新页）× 2 个行奇偶 = 4 个 bank（2048 字）。
// SLIDE_STEPS 必须是 640 的约数（32/16/8/4…），每帧平移 640/SLIDE_STEPS 像素。
module guide_video_640 #(parameter SLIDE_STEPS=32,parameter ROUTE_UI=0,parameter NATIVE_PANEL=0)(input pclk,input prst,input mclk,input enabled,input [3:0] page,
 input [3:0] load_index,input [7:0] error,
 output reg frame_boundary,output reg line_req,output reg [9:0] line_y,
 output reg [3:0] line_page,input line_ack,input line_we,input [8:0] line_addr,input [31:0] line_data,
 output valid,input ready,output user,output last,output [23:0] rgb,output reg underrun,
 output reg [7:0] rows_bad,input [7:0] fade,input zoom,
 input auto_mode,input paused,input audio_playing,input audio_done,input osd_en,
 input sample_valid,input [1:0] play_toggle,input [8:0] brightness,
 input [3:0] dev_row,input [3:0] dev_col,input [23:0] dev_sel,
 input [1:0] contrast,
 input vu_on,input [23:0] sample,
 input boot,input [3:0] boot_prog,input sample_played,
 input [2:0] route_station,input route_closed,input [5:0] route_edges,input route_valid,
 input [9:0] route_progress,input [15:0] elapsed_bcd,total_bcd);
 localparam HTOTAL=NATIVE_PANEL?1344:800,VTOTAL=NATIVE_PANEL?635:525,
 HBLANK=NATIVE_PANEL?320:160,VBLANK=NATIVE_PANEL?35:45,HACT=NATIVE_PANEL?1024:640,VACT=NATIVE_PANEL?600:480;
 reg [10:0] h;reg [9:0] v;
 wire active=h>=HBLANK && v>=VBLANK;
 wire [9:0] ax=h-HBLANK,ay=v-VBLANK;
 reg [9:0] scale_x,scale_y;reg [2:0] scale_xphase,scale_yphase;
 wire center=!NATIVE_PANEL||(ax>=112&&ax<912);
 wire [9:0] x=NATIVE_PANEL?scale_x:ax,y=NATIVE_PANEL?scale_y:ay;
 wire [9:0] next_y=NATIVE_PANEL?(scale_y+((scale_yphase>=1)?1'b1:1'b0)):(y+1'b1);
 always @(posedge pclk or posedge prst)begin
  if(prst)begin scale_x<=0;scale_y<=0;scale_xphase<=0;scale_yphase<=0;end
  else begin
   if(h<HBLANK+112||h>=HBLANK+912)begin scale_x<=0;scale_xphase<=0;end
   else if(scale_xphase>=1)begin scale_x<=scale_x+1'b1;scale_xphase<=scale_xphase-1'b1;end
   else scale_xphase<=4;
   if(v<VBLANK)begin scale_y<=0;scale_yphase<=0;end
   else if(h==HTOTAL-1)begin
    if(scale_yphase>=1)begin scale_y<=scale_y+1'b1;scale_yphase<=scale_yphase-1'b1;end
    else scale_yphase<=4;
   end
  end
 end
 reg [3:0] display_page;                    // vblank 锁存的当前页，帧内不会跳变
 // 缩放（KEY3 长按）：把照片区（卡内 x 0..479, y 0..359，正好 4:3）放大 4/3 铺满整屏。
 // 两轴都是精确的 3/4 映射，只用移位加法，没有乘法器：
 //     sx = 3x/4      sy = 3y/4
 // 只对导览页 1..5 生效（BUG-3）：路线图(0)/紧急(6)/广告(7..9) 长按 K3 仍会切换 zoom 状态，
 // 只是这里不应用；回到导览页自然恢复原来的放大状态。
 reg display_zoom,display_vu;
 wire zoom_eff=display_zoom&&display_page>=4'd1&&display_page<=4'd5;
 // 广告平移：每帧 640/SLIDE_STEPS 像素，默认 32 步 × 20 px = 640（约 0.55 s）。
 localparam [10:0] SLIDE_INC=640/SLIDE_STEPS;
 reg slide_active;reg [3:0] slide_from;reg [5:0] slide_step;
 wire [10:0] slide_off=slide_step*SLIDE_INC;
 wire [10:0] s3={y,1'b0}+{1'b0,y};        // 3y
 wire [10:0] n3={next_y,1'b0}+{1'b0,next_y};
 wire [9:0] sy=zoom_eff?(s3>>2):y;
 wire [9:0] sy1=zoom_eff?(n3>>2):next_y;
 // 左对齐裁切（x 0..479）：卡片左下角的站名和"第X站"角标刚好在左侧，
 // 居中裁切会把它们切成半个字，所以这里不偏移。
 wire [10:0] sxz=zoom_eff?(({x,1'b0}+{1'b0,x})>>2):{1'b0,x};  // 3x/4
 // 平移：屏幕 x 对应"拼接图"的 x+off。sxa<640 取旧页第 sxa 列，sxa>=640 取新页第 sxa-640 列。
 wire [10:0] sxa={1'b0,x}+slide_off;
 wire slide_new=sxa>=11'd640;
 wire [10:0] sxw=slide_active?(slide_new?(sxa-11'd640):sxa):sxz;
 wire [9:0] sx=sxw[9:0];
 wire rd_slot=slide_active&&slide_new;    // 读 slot1（新页）还是 slot0（旧页）
 wire row_adv=sy1!=sy;                 // 源行变了才需要重新取一行
 // {slot,行奇偶,行内字地址} = 11 位地址，2048 字；地址位宽和深度严格对应，TD 才会推成 BRAM
 reg [31:0] lines[0:2047];reg [31:0] q;
 reg [1:0] en_sync,ack_sync;
 reg show,row_good,pending;reg line_slot;
 reg [3:0] bank_valid;                    // 位下标 {slot,行奇偶}，页号 4 位！
 reg [9:0] bank_y[0:3];reg [3:0] bank_page[0:3];
 wire row_par=sy[0];
 wire bank_ok0=bank_valid[{1'b0,row_par}] && bank_y[{1'b0,row_par}]==sy &&
               bank_page[{1'b0,row_par}]==(slide_active?slide_from:display_page);
 wire bank_ok1=bank_valid[{1'b1,row_par}] && bank_y[{1'b1,row_par}]==sy &&
               bank_page[{1'b1,row_par}]==display_page;
 wire buffer_good=slide_active?(bank_ok0&&bank_ok1):bank_ok0;
 reg [9:0] xd,yd,axd,ayd;reg center_d;reg sxd;reg [3:0] load1,load2;reg [7:0] err1,err2;reg [3:0] load_d;reg [7:0] err_d;reg vld;
 always @(posedge mclk) if(line_we) lines[{line_slot,line_y[0],line_addr}]<=line_data;
 always @(posedge pclk) if(active) q<=lines[{rd_slot,sy[0],sx[9:1]}];
 wire [15:0] pixel=sxd?q[31:16]:q[15:0];
 wire [23:0] card={pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
 // 转场：淡出到纸色 -> 换页 -> 淡入。out = paper + ((card-paper)*fade)>>8，
 // 只读一个页面，所以转场期间 SDRAM 访问量和平时完全一样。
 wire signed [8:0] dr=$signed({1'b0,card[23:16]})-9'sd246;
 wire signed [8:0] dg=$signed({1'b0,card[15:8]})-9'sd243;
 wire signed [8:0] db=$signed({1'b0,card[7:0]})-9'sd234;
 wire signed [17:0] mr=dr*$signed({1'b0,fade});
 wire signed [17:0] mg=dg*$signed({1'b0,fade});
 wire signed [17:0] mb=db*$signed({1'b0,fade});
 wire [23:0] faded={8'd246+mr[15:8],8'd243+mg[15:8],8'd234+mb[15:8]};
 wire [23:0] shown=(fade==8'd255)?card:faded;
 // Register fade before contrast; the native panel runs at 51 MHz.
 reg [23:0] shown_r;reg [9:0] xr,yr,axr,ayr;reg center_r,vld_r;
 reg [3:0] load_r;reg [7:0] err_r;
 always @(posedge pclk)begin
  vld_r<=vld;
  if(vld)begin shown_r<=shown;xr<=xd;yr<=yd;axr<=axd;ayr<=ayd;center_r<=center_d;load_r<=load_d;err_r<=err_d;end
 end
 // 字幕：字库引擎两级查表 = 2 拍，所以从 q 往后整条输出流水线再延 1 拍。
// 路线总览页(0)整屏是地图，不画字幕。
 wire [1:0] osd_a;wire osd_on;wire [3:0] cap_line;
 guide_subs subs(.pclk(pclk),.prst(prst),.sample_valid(ROUTE_UI?sample_played:sample_valid),
  .playing(ROUTE_UI?1'b1:audio_playing),.paused(ROUTE_UI?1'b0:paused),
  .play_toggle(play_toggle),.page(display_page),.line(cap_line));
 guide_caption cap(.pclk(pclk),.active(active),.x(x),.y(y),
  .en(osd_en&&show&&row_good&&center&&display_page>=4'd1&&display_page<=4'd5&&!zoom_eff),.page(display_page),.line(cap_line),
  .auto_mode(auto_mode),.paused(paused),.audio_done(audio_done),.audio_playing(audio_playing),
  .alpha(osd_a),.on(osd_on));
 wire [23:0] osd_ink=24'h2b3836;
 reg [1:0] osd_a_r;reg osd_on_r;
 always @(posedge pclk)begin osd_a_r<=osd_a;osd_on_r<=osd_on;end
 reg [23:0] shown_q;reg [9:0] xq,yq,axq,ayq;reg center_q;reg [3:0] load_q;reg [7:0] err_q;
 // 在源像素这一拍计算柱号，再和 RGB 一起延迟两拍；列边界不会借用前一根的高度。
 reg [3:0] bar_ph,bar_ph_d,bar_ph_q;reg [5:0] bar_idx;
 wire [5:0] wave_hgt;
 reg [5:0] wave_hgt_q;
 reg [5:0] wave_hgt_r;reg [3:0] bar_ph_r;
 reg [1:0] wave_play;
 reg [3:0] wave_page;
 wire wave_restart=(wave_play!=play_toggle)||(wave_page!=display_page);
 always @(posedge pclk or posedge prst) begin
  if(prst) begin
   bar_ph<=0;bar_idx<=0;bar_ph_d<=0;bar_ph_q<=0;wave_hgt_q<=0;wave_play<=0;wave_page<=0;
  end else begin
   wave_play<=play_toggle;wave_page<=display_page;
   if(!active||!center) begin bar_ph<=0;bar_idx<=0;end
   else begin
    bar_ph_d<=bar_ph;
    if(!NATIVE_PANEL||scale_xphase>=1)begin
     if(bar_ph==4'd9) begin bar_ph<=0;bar_idx<=bar_idx+1'b1;end
     else bar_ph<=bar_ph+1'b1;
    end
   end
   if(vld) begin bar_ph_r<=bar_ph_d;wave_hgt_r<=wave_hgt;end
   if(vld_r)begin bar_ph_q<=bar_ph_r;wave_hgt_q<=wave_hgt_r;end
  end
 end
 guide_wave wave(.pclk(pclk),.prst(prst),.sample_valid(sample_valid),.sample(sample),
  .frame_boundary(frame_boundary),.restart(wave_restart),.bx(bar_idx),.hgt(wave_hgt));
 // 注意门控用 vld 而不是 active：这一拍要搬的是"上一拍已经算出"的像素，
 // 行末那拍 active 已经拉低，用 active 会把最后一个像素丢掉。
 // 对比度：以 128 为轴，k = 0.75 / 1.0 / 1.25 / 1.5（只用移位加法）；k=1.0 时逐像素不变
 wire signed [9:0] sd_r={2'b0,shown_r[23:16]}-10'sd128;
 wire signed [9:0] sd_g={2'b0,shown_r[15:8]} -10'sd128;
 wire signed [9:0] sd_b={2'b0,shown_r[7:0]}  -10'sd128;
 wire signed [10:0] kr=(contrast==2'd0)?(sd_r-(sd_r>>>2)):(contrast==2'd2)?(sd_r+(sd_r>>>2)):
                       (contrast==2'd3)?(sd_r+(sd_r>>>1)):sd_r;
 wire signed [10:0] kg=(contrast==2'd0)?(sd_g-(sd_g>>>2)):(contrast==2'd2)?(sd_g+(sd_g>>>2)):
                       (contrast==2'd3)?(sd_g+(sd_g>>>1)):sd_g;
 wire signed [10:0] kb=(contrast==2'd0)?(sd_b-(sd_b>>>2)):(contrast==2'd2)?(sd_b+(sd_b>>>2)):
                       (contrast==2'd3)?(sd_b+(sd_b>>>1)):sd_b;
 wire signed [10:0] cs_r=11'sd128+kr, cs_g=11'sd128+kg, cs_b=11'sd128+kb;
 wire [7:0] con_r=(cs_r<0)?8'd0:(cs_r>11'sd255)?8'd255:cs_r[7:0];
 wire [7:0] con_g=(cs_g<0)?8'd0:(cs_g>11'sd255)?8'd255:cs_g[7:0];
 wire [7:0] con_b=(cs_b<0)?8'd0:(cs_b>11'sd255)?8'd255:cs_b[7:0];
 always @(posedge pclk) if(vld_r) begin
  shown_q<={con_r,con_g,con_b};xq<=xr;yq<=yr;axq<=axr;ayq<=ayr;center_q<=center_r;load_q<=load_r;err_q<=err_r;
 end
 reg vld_q;
 always @(posedge pclk) vld_q<=vld_r;
 // Shift-only alpha avoids the former multiply/divide chain after the font ROM.
 function [7:0] caption_mix;input [7:0] bg,fg;input [1:0] a;reg [9:0] n;begin
  case(a)0:n={2'b0,bg};1:n=({2'b0,bg}*3+{2'b0,fg})>>2;
   2:n=({2'b0,bg}+{2'b0,fg}*3)>>2;default:n={2'b0,fg};endcase
  caption_mix=n[7:0];
 end endfunction
 reg [23:0] card_out;reg [9:0] xm,ym,axm,aym;reg center_m,vld_m;
 reg [3:0] bar_ph_m;reg [5:0] wave_hgt_m;
 always @(posedge pclk)begin
  vld_m<=vld_q;
  if(vld_q)begin
   card_out<=osd_on_r?{caption_mix(shown_q[23:16],osd_ink[23:16],osd_a_r),
    caption_mix(shown_q[15:8],osd_ink[15:8],osd_a_r),caption_mix(shown_q[7:0],osd_ink[7:0],osd_a_r)}:shown_q;
   xm<=xq;ym<=yq;axm<=axq;aym<=ayq;center_m<=center_q;bar_ph_m<=bar_ph_q;wave_hgt_m<=wave_hgt_q;
  end
 end // 装载页：开机卡（PIC11）装好前是纯纸色 + 8 个错误格；装好后显示 PIC11 和进度条
 // 开发者页（页 10）高亮：网格 = 行 y 76+36*i、选项 x 212+60*j（和 gen_dev_card.py 一致）。
 // 只用 xm/ym 比较，和 card_out 同一拍，不加流水线。
 wire dev_page=display_page==4'd10;
 wire [9:0] dev_y=10'd76+{6'd0,dev_row}*10'd36;
 wire [9:0] dev_x=10'd212+{6'd0,dev_col}*10'd60;
 wire rowbar_on=dev_page&&xm>=10'd28&&xm<10'd35&&ym>=dev_y-10'd2&&ym<dev_y+10'd26;
 // 第 8 行是"恢复默认"，没有选项框
 wire box_out =dev_page&&dev_row!=4'd8&&xm>=dev_x-10'd4&&xm<dev_x+10'd52&&ym>=dev_y-10'd4&&ym<dev_y+10'd24;
 wire box_in  =dev_page&&dev_row!=4'd8&&xm>=dev_x-10'd2&&xm<dev_x+10'd50&&ym>=dev_y-10'd2&&ym<dev_y+10'd22;
 wire dev_hl=rowbar_on||(box_out&&!box_in);
 // 地图/放大/紧急页贴屏幕底边；景点页停在照片底边，保留标签和字幕。
 // 64 根 8 px 柱 + 2 px 留白，最大 96 px；圆角亮顶、玉绿到湖蓝的渐变和轻微光晕。
 wire glass_panel=ROUTE_UI&&!NATIVE_PANEL&&display_page>=1&&display_page<=5&&!zoom_eff;
 wire vu_area=display_vu&&display_page<=4'd6&&!boot&&fade!=8'd0&&
              (!glass_panel||(xm>=104&&xm<512));
 wire [9:0] vu_base=(display_page==4'd0||zoom_eff||display_page==4'd6)?10'd480:10'd360;
 wire [9:0] wh=(wave_hgt_m==6'd0)?10'd2:{3'd0,wave_hgt_m,1'b0};
 wire [9:0] vu_dy=vu_base-ym;
 wire bar_body=vu_area&&(bar_ph_m>=4'd1)&&(bar_ph_m<=4'd8)&&(ym<vu_base)&&(vu_dy<=wh);
 wire bar_cap=bar_body&&(vu_dy+10'd2>wh);
 wire rounded=bar_cap&&(vu_dy==wh)&&((bar_ph_m==4'd1)||(bar_ph_m==4'd8))&&(wh>10'd2);
 wire bar_glow=vu_area&&(wh>10'd2)&&(ym<vu_base)&&(vu_dy<=wh+10'd2);
 wire in_bar=(bar_body&&!rounded)||bar_glow;
 wire [7:0] tint_r=8'd72+{2'd0,vu_dy[6:1]};
 wire [7:0] tint_g=8'd158+{2'd0,vu_dy[6:1]};
 wire [7:0] tint_b=8'd154+{3'd0,xm[9:5]};
 wire [23:0] bar_tint=bar_cap?24'hc7e9d9:{tint_r,tint_g,tint_b};
 // 移位混色：光晕 1/8，底部 1/4，柱身 1/2，亮顶 3/4；淡出时同步减弱。
 wire [1:0] bar_alpha=(!bar_body||rounded||fade<8'd64)?2'd0:
                       (fade<8'd160||vu_dy<=10'd12)?2'd1:(bar_cap?2'd3:2'd2);
 function [7:0] wave_blend;input [7:0] bg,fg;input [1:0] a;reg [10:0] b,f,n;begin
  b={3'd0,bg};f={3'd0,fg};
  case(a)
   2'd0:n=(b*3'd7+f)>>3;
   2'd1:n=(b*2'd3+f)>>2;
   2'd2:n=(b+f)>>1;
   default:n=(b+f*2'd3)>>2;
  endcase
  wave_blend=n[7:0];
 end endfunction
 wire widget_on;wire [23:0] widget_color,widget_base;wire [3:0] widget_opacity,widget_base_opacity;
 wire [7:0] widget_fade_product=widget_opacity*fade[7:5];
 wire [7:0] widget_base_fade_product=widget_base_opacity*fade[7:5];
 wire [3:0] widget_alpha=(fade==255)?widget_opacity:widget_fade_product[6:3];
 wire [3:0] widget_base_alpha=(fade==255)?widget_base_opacity:widget_base_fade_product[6:3];
 function [7:0] glass_mix;input [7:0] bg,fg;input [3:0] a;reg signed [13:0] n;reg signed [8:0] delta;begin
  delta=$signed({1'b0,fg})-$signed({1'b0,bg});
  n=$signed({1'b0,bg,3'b0})+delta*$signed({1'b0,a});glass_mix=n[10:3];
 end endfunction
 wire [23:0] widget_paper={glass_mix(card_out[23:16],widget_base[23:16],widget_base_alpha),
  glass_mix(card_out[15:8],widget_base[15:8],widget_base_alpha),
  glass_mix(card_out[7:0],widget_base[7:0],widget_base_alpha)};
 wire [23:0] widget_blended={glass_mix(widget_paper[23:16],widget_color[23:16],widget_alpha),
  glass_mix(widget_paper[15:8],widget_color[15:8],widget_alpha),
  glass_mix(widget_paper[7:0],widget_color[7:0],widget_alpha)};
 wire [23:0] card_layer=widget_on?widget_blended:card_out;
 wire [7:0] mix_r=wave_blend(card_layer[23:16],bar_tint[23:16],bar_alpha);
 wire [7:0] mix_g=wave_blend(card_layer[15:8],bar_tint[15:8],bar_alpha);
 wire [7:0] mix_b=wave_blend(card_layer[7:0],bar_tint[7:0],bar_alpha);
 wire [23:0] bar_col={mix_r[7:0],mix_g[7:0],mix_b[7:0]};
 // 设置页总览：7 行各画一条 2 px 下划线标出当前值（光标行另有红框）
 reg [9:0] ux0,ux1,ux2,ux3,ux4,ux5,ux6,ux7;
 always @(posedge pclk) begin
  ux0<=10'd212+{2'd0,dev_sel[2:0]}*10'd60;
  ux1<=10'd212+{2'd0,dev_sel[5:3]}*10'd60;
  ux2<=10'd212+{2'd0,dev_sel[8:6]}*10'd60;
  ux3<=10'd212+{2'd0,dev_sel[11:9]}*10'd60;
  ux4<=10'd212+{2'd0,dev_sel[14:12]}*10'd60;
  ux5<=10'd212+{2'd0,dev_sel[17:15]}*10'd60;
  ux6<=10'd212+{2'd0,dev_sel[20:18]}*10'd60;
  ux7<=10'd212+{2'd0,dev_sel[23:21]}*10'd60;
 end
 wire ul0=(ym==10'd98 ||ym==10'd99 )&&(xm>=ux0+10'd2)&&(xm<ux0+10'd50);
 wire ul1=(ym==10'd134||ym==10'd135)&&(xm>=ux1+10'd2)&&(xm<ux1+10'd50);
 wire ul2=(ym==10'd170||ym==10'd171)&&(xm>=ux2+10'd2)&&(xm<ux2+10'd50);
 wire ul3=(ym==10'd206||ym==10'd207)&&(xm>=ux3+10'd2)&&(xm<ux3+10'd50);
 wire ul4=(ym==10'd242||ym==10'd243)&&(xm>=ux4+10'd2)&&(xm<ux4+10'd50);
 wire ul5=(ym==10'd278||ym==10'd279)&&(xm>=ux5+10'd2)&&(xm<ux5+10'd50);
 wire ul6=(ym==10'd314||ym==10'd315)&&(xm>=ux6+10'd2)&&(xm<ux6+10'd50);
 wire ul7=(ym==10'd350||ym==10'd351)&&(xm>=ux7+10'd2)&&(xm<ux7+10'd50);
 wire ulx=dev_page&&(ul0||ul1||ul2||ul3||ul4||ul5||ul6||ul7);
 // 开机卡进度条：画在 PIC11 空出来的条位上（x 64..575、y 360..371），两端 2 px 倒角
 wire boot_bar=boot&&show&&ym>=10'd360&&ym<=10'd371;
 wire [2:0] br_off=(ym==10'd360||ym==10'd371)?3'd4:((ym==10'd361||ym==10'd370)?3'd2:3'd0);
 wire [9:0] br_x0=10'd64+{7'd0,br_off}, br_x1=10'd575-{7'd0,br_off};
 wire boot_in=boot_bar&&xm>=br_x0&&xm<=br_x1;
 wire [9:0] br_fill={2'd0,boot_prog}*10'd43;
 wire boot_fill=boot_in&&((xm-10'd64)<br_fill);
 reg [2:0] station_q;reg closed_q;reg [5:0] edges_q,route_phase;
 reg [9:0] progress_q;
 reg [15:0] elapsed_q,total_q;reg paused_q;
 always @(posedge pclk or posedge prst)begin
  if(prst)begin station_q<=0;closed_q<=0;edges_q<=0;route_phase<=0;progress_q<=0;elapsed_q<=0;total_q<=0;paused_q<=0;end
  else if(v==0&&h==2)begin
   station_q<=route_station;closed_q<=route_closed;edges_q<=route_valid?route_edges:6'd0;
   progress_q<=route_progress;route_phase<=route_phase+1'b1;
   elapsed_q<=elapsed_bcd;total_q<=total_bcd;paused_q<=paused;
  end
 end
 wire route_on_calc;wire [23:0] route_color_calc;
 wire timeline_on;wire [23:0] timeline_color;
 reg route_on;reg [23:0] route_color;
 always @(posedge pclk)begin
  route_on<=route_on_calc||timeline_on;
  route_color<=timeline_on?timeline_color:route_color_calc;
 end
 guide_playback_bar playback_bar(.x(xq),.y(yq),
  .enabled(ROUTE_UI&&display_page>=1&&display_page<=5&&!zoom_eff&&!boot),
  .paused(paused_q),.progress(progress_q),.elapsed_bcd(elapsed_q),.total_bcd(total_q),
  .on(timeline_on),.color(timeline_color));
 // Evaluate geometry alongside caption blending, then fade the registered ink.
 guide_route_overlay route_ui(.x(xq),.y(yq),
  .full_map(ROUTE_UI&&(display_page==12)&&!boot),
  .mini_map(ROUTE_UI&&display_page>=1&&display_page<=5&&!zoom_eff&&!boot),
  .emergency(display_page==12),.closed(closed_q),.station(station_q),.route_edges(edges_q),
  .phase(route_phase),.progress(progress_q),.on(route_on_calc),.color(route_color_calc));
 function [7:0] route_fade_channel;input [7:0] c,p,f;reg signed [17:0] product;begin
  product=($signed({1'b0,c})-$signed({1'b0,p}))*$signed({1'b0,f});
  route_fade_channel=p+product[15:8];
 end endfunction
 wire [23:0] route_faded={route_fade_channel(route_color[23:16],8'd246,fade),
                        route_fade_channel(route_color[15:8],8'd243,fade),
                        route_fade_channel(route_color[7:0],8'd234,fade)};
 reg [23:0] color;
 always @* begin
  if(NATIVE_PANEL&&!center_m)color=widget_blended;
  else if(show && row_good) color=boot?(boot_in?(boot_fill?24'h3e7a76:24'he2ddd2):card_layer):
                                    (dev_page?(dev_hl?24'hb5432f:(ulx?24'hc8806a:card_layer)):
                                     (route_on?(fade==255?route_color:route_faded):(in_bar?bar_col:card_layer)));
  else if(show) color=24'hb5432f;
  else begin
   // 开机卡装好之前：纯纸色（0.6 s 左右），有错就画 8 个错误格
   color=24'hf6f3ea;
   if(err_q!=0&&ym>=10'd150&&ym<10'd230&&xm>=10'd240&&xm<10'd400&&xm[5:0]<56)
    color=err_q[7-((xm-10'd240)>>5)]?24'hb5432f:24'heae8df;
  end
 end
 // 环境光数字调光：整幅画面（含字幕、加载页）一起乘 0..256，保持对比；
 // brightness=256 时 (c*256)>>8 == c，逐像素不变，所以现有像素级 TB 只要接 256 就一字不差。
 reg [23:0] color_p,color_q;
 reg [2:0] valid_pipe,user_pipe,last_pipe;
 reg [8:0] scroll;reg [1:0] scroll_tick;
 always @(posedge pclk or posedge prst)begin
  if(prst)begin scroll<=0;scroll_tick<=0;end
  else if(frame_boundary)begin
   scroll_tick<=scroll_tick+1'b1;
   if(scroll_tick==3)scroll<=scroll+1'b1;
  end
 end
 wire [2:0] tip_index;wire [3:0] tip_alpha;
 guide_tip_cycle tips(.clk(pclk),.rst(prst),.frame_boundary(frame_boundary),
  .enabled(glass_panel&&show&&fade==255&&!boot),.index(tip_index),.alpha(tip_alpha));
 guide_widgets #(.NATIVE_PANEL(NATIVE_PANEL)) widgets(.clk(pclk),.x(xq),.y(yq),.ax(axq),.ay(ayq),
  .center(center_q),.page((zoom_eff||!ROUTE_UI)?4'd15:display_page),.reverse(closed_q),
  .station(station_q),.scroll(scroll),.tip_index(tip_index),.tip_alpha(tip_alpha),
  .on(widget_on),.color(widget_color),.opacity(widget_opacity),
  .base_color(widget_base),.base_opacity(widget_base_opacity));
 always @(posedge pclk)begin
  color_p<=color;color_q<=color_p;
  valid_pipe<={valid_pipe[1:0],vld_m};
  user_pipe<={user_pipe[1:0],vld_m&&axm==0&&aym==0};
  last_pipe<={last_pipe[1:0],vld_m&&axm==HACT-1};
 end
 wire [16:0] gain_r=color_q[23:16]*brightness;
 wire [16:0] gain_g=color_q[15:8]*brightness;
 wire [16:0] gain_b=color_q[7:0]*brightness;
 // 注意位宽：要取 [15:8]（8 位）。写成 [16:8] 是 9 位，三个 9 位拼起来 27 位，
 // 截到 24 位后三个通道会整体左移错位（红 <<2、绿 <<1、蓝不动）。
 reg [23:0] rgb_out;
 always @(posedge pclk)rgb_out<={gain_r[15:8],gain_g[15:8],gain_b[15:8]};
 assign rgb=rgb_out;
 assign valid=valid_pipe[2];assign user=user_pipe[2];assign last=last_pipe[2];
 always @(posedge pclk or posedge prst) begin
  if(prst) begin
   h<=0;v<=0;xd<=0;yd<=0;vld<=0;frame_boundary<=0;en_sync<=0;ack_sync<=0;line_req<=0;
   line_y<=0;line_page<=0;line_slot<=0;pending<=0;row_good<=0;show<=0;display_page<=0;
   slide_active<=0;slide_from<=0;slide_step<=0;display_zoom<=0;display_vu<=0;
   bank_valid<=0;bank_y[0]<=0;bank_y[1]<=0;bank_y[2]<=0;bank_y[3]<=0;
   bank_page[0]<=0;bank_page[1]<=0;bank_page[2]<=0;bank_page[3]<=0;underrun<=0;rows_bad<=0;
   load1<=0;load2<=0;err1<=0;err2<=0;load_d<=0;err_d<=0;
  end else begin
   en_sync<={en_sync[0],enabled};ack_sync<={ack_sync[0],line_ack};
   load1<=load_index;load2<=load1;err1<=error;err2<=err1;frame_boundary<=0;
   if(h==HTOTAL-1) begin h<=0;if(v==VTOTAL-1) v<=0;else v<=v+1'b1;end
   else h<=h+1'b1;
   vld<=active;
   if(active) begin xd<=x;yd<=y;axd<=ax;ayd<=ay;center_d<=center;sxd<=sx[0];load_d<=load2;err_d<=err2;end
   if(pending && ack_sync[1]==line_req) begin
    bank_valid[{line_slot,line_y[0]}]<=1;
    bank_y[{line_slot,line_y[0]}]<=line_y;
    bank_page[{line_slot,line_y[0]}]<=line_page;
    // 平移时同一行还要取新页那一份：接着发 slot1，pending 保持
    if(slide_active && !line_slot) begin
     line_slot<=1'b1;line_page<=display_page;line_req<=~line_req;
    end else pending<=0;
   end
   if(v==0 && h==0) begin
    frame_boundary<=1;show<=en_sync[1];bank_valid<=0;
    if(slide_active) begin
     if(slide_step>=SLIDE_STEPS) slide_active<=0;
     else slide_step<=slide_step+1'b1;
    end
   end
   // 帧边界锁存页号：广告 7..9 之间换页走平移，其余（导览/紧急/进出广告）仍然直切。
   if(v==0 && h==2) begin
    display_zoom<=zoom;display_vu<=vu_on;
    if(page!=display_page) begin
     if(!slide_active && page>=4'd7 && page<=4'd9 && display_page>=4'd7 && display_page<=4'd9) begin
      slide_active<=1;slide_step<=0;slide_from<=display_page;display_page<=page;
     end else begin
      slide_active<=0;display_page<=page;
     end
    end
   end
   // 垂直消隐预取第 0 行；之后只在“下一个显示行换了源行”时预取，
   // 1:1 时每行都取，放大时 4 个显示行才取 3 次。
   if(show && !pending && ((v==0 && h==4) || (active && h==HBLANK && ay<VACT-1 && row_adv))) begin
    line_y<=(v==0)?10'd0:sy1;
    line_slot<=1'b0;
    line_page<=slide_active?slide_from:display_page;
    line_req<=~line_req;pending<=1;
    if(v==0) bank_valid[2'b00]<=0;else bank_valid[{1'b0,!sy[0]}]<=0;
    if(slide_active) begin
     if(v==0) bank_valid[2'b10]<=0;else bank_valid[{1'b1,!sy[0]}]<=0;
    end
   end
   // h==HBLANK-1 is one clock before the active window, where active is low,
   // so it must be qualified by v (the row about to be displayed), not by active.
   if(h==HBLANK-1 && v>=VBLANK && v<VBLANK+VACT) begin
    row_good<=buffer_good;
    if(show && !buffer_good) begin
     underrun<=1;
     if(rows_bad!=8'hff) rows_bad<=rows_bad+1'b1;
    end
   end
  end
 end
endmodule
