// 640x480@60 视频源：整屏就是一张 640x480 卡片，SDRAM 一行 320 字。
// 时序与教程 lab_ex4/5 完全一致：H 640+16+96+48=800，V 480+10+2+33=525，像素时钟 25 MHz。
// 装载完成前显示纸色底 + 进度条；某行取数迟到则整行画朱红，便于区分取数与数据问题。
// 广告页 7..9 之间换页做水平平移（push）：旧页往左走、新页从右边进。两页在同一帧都要取行，
// 所以行缓冲是 2 个 slot（旧/新页）× 2 个行奇偶 = 4 个 bank（2048 字）。
// SLIDE_STEPS 必须是 640 的约数（32/16/8/4…），每帧平移 640/SLIDE_STEPS 像素。
module guide_video_640 #(parameter SLIDE_STEPS=32)(input pclk,input prst,input mclk,input enabled,input [3:0] page,
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
 input boot,input [3:0] boot_prog);
 localparam HTOTAL=800,VTOTAL=525,HBLANK=160,VBLANK=45,HACT=640,VACT=480;
 reg [10:0] h;reg [9:0] v;
 wire active=h>=HBLANK && v>=VBLANK;
 wire [9:0] x=h-HBLANK,y=v-VBLANK;
 reg [3:0] display_page;                    // vblank 锁存的当前页，帧内不会跳变
 // 缩放（KEY3 长按）：把照片区（卡内 x 80..559, y 0..359，正好 4:3）放大 4/3 铺满整屏。
 // 两轴都是精确的 3/4 映射，只用移位加法，没有乘法器：
 //     sx = 80 + 3x/4      sy = 3y/4
 // 只对导览页 1..5 生效（BUG-3）：路线图(0)/紧急(6)/广告(7..9) 长按 K3 仍会切换 zoom 状态，
 // 只是这里不应用；回到导览页自然恢复原来的放大状态。
 wire zoom_eff=zoom&&display_page>=4'd1&&display_page<=4'd5;
 // 广告平移：每帧 640/SLIDE_STEPS 像素，默认 32 步 × 20 px = 640（约 0.55 s）。
 localparam [10:0] SLIDE_INC=640/SLIDE_STEPS;
 reg slide_active;reg [3:0] slide_from;reg [5:0] slide_step;
 wire [10:0] slide_off=slide_step*SLIDE_INC;
 wire [10:0] s3={y,1'b0}+{1'b0,y};        // 3y
 wire [10:0] n3={y,1'b0}+{1'b0,y}+11'd3;  // 3(y+1)
 wire [9:0] sy=zoom_eff?(s3>>2):y;
 wire [9:0] sy1=zoom_eff?(n3>>2):(y+1'b1);
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
 reg [9:0] xd,yd;reg sxd;reg [3:0] load1,load2;reg [7:0] err1,err2;reg [3:0] load_d;reg [7:0] err_d;reg vld;
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
 // 字幕：字库引擎两级查表 = 2 拍，所以从 q 往后整条输出流水线再延 1 拍。
// 路线总览页(0)整屏是地图，不画字幕。
 wire [1:0] osd_a;wire osd_on;wire [3:0] cap_line;
 guide_subs subs(.pclk(pclk),.prst(prst),.sample_valid(sample_valid),.playing(audio_playing),
  .paused(paused),.play_toggle(play_toggle),.page(display_page),.line(cap_line));
 guide_caption cap(.pclk(pclk),.active(active),.x(x),.y(y),
  .en(osd_en&&show&&row_good&&display_page>=4'd1&&display_page<=4'd5&&!zoom_eff),.page(display_page),.line(cap_line),
  .auto_mode(auto_mode),.paused(paused),.audio_done(audio_done),.audio_playing(audio_playing),
  .alpha(osd_a),.on(osd_on));
 wire [23:0] osd_ink=24'h2b3836;
 reg [23:0] shown_q;reg [9:0] xq,yq;reg [3:0] load_q;reg [7:0] err_q;
 // 频谱柱：64 根柱，10 px 一根（6 px 柱 + 4 px 间隔），用相位计数器而不是除法算列号
 reg [3:0] bar_ph;reg [5:0] bar_idx;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin bar_ph<=0;bar_idx<=0;end
  else if(vld) begin
   if(xq==10'd0) begin bar_ph<=4'd1;bar_idx<=6'd0;end
   else if(bar_ph==4'd9) begin bar_ph<=0;if(bar_idx!=6'd63) bar_idx<=bar_idx+1'b1;end
   else bar_ph<=bar_ph+1'b1;
  end
 end
 wire [5:0] wave_hgt;
 guide_wave wave(.pclk(pclk),.prst(prst),.sample_valid(sample_valid),.sample(sample),
  .frame_boundary(frame_boundary),.bx(bar_idx),.hgt(wave_hgt));
 // 注意门控用 vld 而不是 active：这一拍要搬的是"上一拍已经算出"的像素，
 // 行末那拍 active 已经拉低，用 active 会把最后一个像素丢掉。
 // 对比度：以 128 为轴，k = 0.75 / 1.0 / 1.25 / 1.5（只用移位加法）；k=1.0 时逐像素不变
 wire signed [9:0] sd_r={2'b0,shown[23:16]}-10'sd128;
 wire signed [9:0] sd_g={2'b0,shown[15:8]} -10'sd128;
 wire signed [9:0] sd_b={2'b0,shown[7:0]}  -10'sd128;
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
 always @(posedge pclk) if(vld) begin
  shown_q<={con_r,con_g,con_b};xq<=xd;yq<=yd;load_q<=load_d;err_q<=err_d;
 end
 reg vld_q;
 always @(posedge pclk) vld_q<=vld;
 wire [9:0] o_r=({2'd0,shown_q[23:16]}*(3'd3-{1'd0,osd_a}))+({2'd0,osd_ink[23:16]}*{1'd0,osd_a});
 wire [9:0] o_g=({2'd0,shown_q[15:8]}*(3'd3-{1'd0,osd_a}))+({2'd0,osd_ink[15:8]}*{1'd0,osd_a});
 wire [9:0] o_b=({2'd0,shown_q[7:0]}*(3'd3-{1'd0,osd_a}))+({2'd0,osd_ink[7:0]}*{1'd0,osd_a});
 // 先各自算成 8bit 再拼接：把 32bit 表达式直接写进 { } 会被当成 96bit，
 // 赋给 24bit 只留低 24 位，三个通道就串了（这就是字幕条发蓝的原因）。
 wire [31:0] orr={22'd0,o_r}*32'd21846, ogg={22'd0,o_g}*32'd21846, obb={22'd0,o_b}*32'd21846;
 wire [7:0] osd_r=orr[23:16], osd_g=ogg[23:16], osd_b=obb[23:16];
 wire [23:0] osd_col={osd_r,osd_g,osd_b};
 wire [23:0] card_out=osd_on?osd_col:shown_q;
 assign valid=vld_q;
 assign user=vld_q && xq==0 && yq==0;
 assign last=vld_q && xq==HACT-1;
 // 装载页：开机卡（PIC11）装好前是纯纸色 + 8 个错误格；装好后显示 PIC11 和进度条
 // 开发者页（页 10）高亮：网格 = 行 y 76+36*i、选项 x 212+60*j（和 gen_dev_card.py 一致）。
 // 只用 xq/yq 比较，和 card_out 同一拍，不加流水线。
 wire dev_page=display_page==4'd10;
 wire [9:0] dev_y=10'd76+{6'd0,dev_row}*10'd36;
 wire [9:0] dev_x=10'd212+{6'd0,dev_col}*10'd60;
 wire rowbar_on=dev_page&&xq>=10'd28&&xq<10'd35&&yq>=dev_y-10'd2&&yq<dev_y+10'd26;
 // 第 8 行是"恢复默认"，没有选项框
 wire box_out =dev_page&&dev_row!=4'd8&&xq>=dev_x-10'd4&&xq<dev_x+10'd52&&yq>=dev_y-10'd4&&yq<dev_y+10'd24;
 wire box_in  =dev_page&&dev_row!=4'd8&&xq>=dev_x-10'd2&&xq<dev_x+10'd50&&yq>=dev_y-10'd2&&yq<dev_y+10'd22;
 wire dev_hl=rowbar_on||(box_out&&!box_in);
 // 音频频谱柱（开发者模式开关）：普通页底部在标签页上沿 y=360；放大全屏和紧急播报页
 // 没有标签页，底部改到屏幕最下沿 y=480。64 根柱（10 px 间距、6 px 宽），
 // 高度 0..44 px（经 lerp），半透明四段淡彩；不画轴线。
 wire vu_area=vu_on&&display_page<=4'd6;
 wire [9:0] vu_base=(zoom_eff||display_page==4'd6)?10'd480:10'd360;
 // 没声音时也留一小格（2 px）平铺一行，像待机频谱
 wire [9:0]  wh=(wave_hgt==6'd0)?10'd2:{4'd0,wave_hgt};
 wire in_bar=vu_area&&(bar_ph<4'd6)&&(yq<vu_base)&&(yq+wh>=vu_base);
 wire bar_top=in_bar&&(yq==vu_base-wh);
 wire [23:0] bar_tint=(xq[9:8]==2'd0)?24'h9fe0c8:
                       (xq[9:8]==2'd1)?24'ha8e0a0:
                       (xq[9:8]==2'd2)?24'h98d8e8:24'ha8b8ee;
 // 混色只用移位：柱身 1/4（(3*card+tint)>>2），柱顶一行 1/2
 wire [9:0] cr={2'd0,card_out[23:16]}, cg={2'd0,card_out[15:8]}, cb={2'd0,card_out[7:0]};
 wire [9:0] tr={2'd0,bar_tint[23:16]}, tg={2'd0,bar_tint[15:8]}, tb={2'd0,bar_tint[7:0]};
 wire [9:0] mix_r=bar_top?((cr+tr)>>1):((cr+cr+cr+tr)>>2);
 wire [9:0] mix_g=bar_top?((cg+tg)>>1):((cg+cg+cg+tg)>>2);
 wire [9:0] mix_b=bar_top?((cb+tb)>>1):((cb+cb+cb+tb)>>2);
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
 wire ul0=(yq==10'd98 ||yq==10'd99 )&&(xq>=ux0+10'd2)&&(xq<ux0+10'd50);
 wire ul1=(yq==10'd134||yq==10'd135)&&(xq>=ux1+10'd2)&&(xq<ux1+10'd50);
 wire ul2=(yq==10'd170||yq==10'd171)&&(xq>=ux2+10'd2)&&(xq<ux2+10'd50);
 wire ul3=(yq==10'd206||yq==10'd207)&&(xq>=ux3+10'd2)&&(xq<ux3+10'd50);
 wire ul4=(yq==10'd242||yq==10'd243)&&(xq>=ux4+10'd2)&&(xq<ux4+10'd50);
 wire ul5=(yq==10'd278||yq==10'd279)&&(xq>=ux5+10'd2)&&(xq<ux5+10'd50);
 wire ul6=(yq==10'd314||yq==10'd315)&&(xq>=ux6+10'd2)&&(xq<ux6+10'd50);
 wire ul7=(yq==10'd350||yq==10'd351)&&(xq>=ux7+10'd2)&&(xq<ux7+10'd50);
 wire ulx=dev_page&&(ul0||ul1||ul2||ul3||ul4||ul5||ul6||ul7);
 reg ul_r;
 always @(posedge pclk) ul_r<=ulx;
 // 开机卡进度条：画在 PIC11 空出来的条位上（x 64..575、y 360..371），两端 2 px 倒角
 wire boot_bar=boot&&show&&yq>=10'd360&&yq<=10'd371;
 wire [2:0] br_off=(yq==10'd360||yq==10'd371)?3'd4:((yq==10'd361||yq==10'd370)?3'd2:3'd0);
 wire [9:0] br_x0=10'd64+{7'd0,br_off}, br_x1=10'd575-{7'd0,br_off};
 wire boot_in=boot_bar&&xq>=br_x0&&xq<=br_x1;
 wire [9:0] br_fill={2'd0,boot_prog}*10'd47;
 wire boot_fill=boot_in&&((xq-10'd64)<br_fill);
 reg [23:0] color;
 always @* begin
  if(show && row_good) color=boot?(boot_in?(boot_fill?24'h3e7a76:24'he2ddd2):card_out):
                                    (dev_page?(dev_hl?24'hb5432f:(ul_r?24'hc8806a:card_out)):
                                     (in_bar?bar_col:card_out));
  else if(show) color=24'hb5432f;
  else begin
   // 开机卡装好之前：纯纸色（0.6 s 左右），有错就画 8 个错误格
   color=24'hf6f3ea;
   if(err_q!=0&&yq>=10'd150&&yq<10'd230&&xq>=10'd240&&xq<10'd400&&xq[5:0]<56)
    color=err_q[7-((xq-10'd240)>>5)]?24'hb5432f:24'heae8df;
  end
 end
 // 环境光数字调光：整幅画面（含字幕、加载页）一起乘 0..256，保持对比；
 // brightness=256 时 (c*256)>>8 == c，逐像素不变，所以现有像素级 TB 只要接 256 就一字不差。
 wire [16:0] gain_r=color[23:16]*brightness;
 wire [16:0] gain_g=color[15:8]*brightness;
 wire [16:0] gain_b=color[7:0]*brightness;
 // 注意位宽：要取 [15:8]（8 位）。写成 [16:8] 是 9 位，三个 9 位拼起来 27 位，
 // 截到 24 位后三个通道会整体左移错位（红 <<2、绿 <<1、蓝不动）。
 assign rgb={gain_r[15:8],gain_g[15:8],gain_b[15:8]};
 always @(posedge pclk or posedge prst) begin
  if(prst) begin
   h<=0;v<=0;xd<=0;yd<=0;vld<=0;frame_boundary<=0;en_sync<=0;ack_sync<=0;line_req<=0;
   line_y<=0;line_page<=0;line_slot<=0;pending<=0;row_good<=0;show<=0;display_page<=0;
   slide_active<=0;slide_from<=0;slide_step<=0;
   bank_valid<=0;bank_y[0]<=0;bank_y[1]<=0;bank_y[2]<=0;bank_y[3]<=0;
   bank_page[0]<=0;bank_page[1]<=0;bank_page[2]<=0;bank_page[3]<=0;underrun<=0;rows_bad<=0;
   load1<=0;load2<=0;err1<=0;err2<=0;load_d<=0;err_d<=0;
  end else begin
   en_sync<={en_sync[0],enabled};ack_sync<={ack_sync[0],line_ack};
   load1<=load_index;load2<=load1;err1<=error;err2<=err1;frame_boundary<=0;
   if(h==HTOTAL-1) begin h<=0;if(v==VTOTAL-1) v<=0;else v<=v+1'b1;end
   else h<=h+1'b1;
   vld<=active;
   if(active) begin xd<=x;yd<=y;sxd<=sx[0];load_d<=load2;err_d<=err2;end
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
   if(show && !pending && ((v==0 && h==4) || (active && h==HBLANK && y<VACT-1 && row_adv))) begin
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
