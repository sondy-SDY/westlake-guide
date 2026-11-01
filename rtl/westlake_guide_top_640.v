// 640x480@60 / 25 MHz 版本：与教程 lab_ex4/lab_ex5 同一时序，TMDS 只跑 250 Mbps。
// 全屏就是一张 640x480 卡片（卡上 PIC00..PIC05），没有 1024x600 的界面层。
// DRAW_OSD=1 打开信息栏底部文字条（自动轮播/讲解状态）。v4 版式已给它腾出纸色带。
module westlake_guide_top_640 #(parameter DRAW_OSD = 1,parameter NATIVE_PANEL=0)(input sys_clk,input sys_rst_n,
 input key2,input key3,input key4,input pir,
 input [3:0] switches,input sd_miso,output sd_ncs,output sd_dclk,output sd_mosi,output [3:0] led,
 output HDMI_CLK_P,output HDMI_D0_P,output HDMI_D1_P,output HDMI_D2_P,
 output HDMI_DDC_SCL,inout HDMI_DDC_SDA,output uart_tx,output i2c_scl,inout i2c_sda);
 wire pclk,fastclk,mclk,mshift,unused,m_locked,v_locked;
 localparam CLOCK_HZ=NATIVE_PANEL?51000000:25000000;
 hdmi_pll_640 #(.NATIVE_PANEL(NATIVE_PANEL)) u_hdmi_pll(.refclk(sys_clk),.reset(~sys_rst_n),.extlock(v_locked),.clk0_out(fastclk),.clk1_out(pclk));
 sys_pll u_sys_pll(.refclk(sys_clk),.reset(~sys_rst_n),.extlock(m_locked),.clk0_out(unused),.clk1_out(mclk),.clk2_out(mshift));
 wire sys_run;
 guide_clock_guard clock_guard(.clk(sys_clk),.reset_n(sys_rst_n),
  .video_locked(v_locked),.memory_locked(m_locked),.run(sys_run));
 wire arst=!sys_run;
 reg [16:0] mr,pr;
 always @(posedge mclk or posedge arst) if(arst) mr<=0;else mr<={mr[15:0],1'b1};
 always @(posedge pclk or posedge arst) if(arst) pr<=0;else pr<={pr[15:0],1'b1};
 wire rst=~mr[16],prst=~pr[16];
 // 光照传感器 BH1750（GY-302）：I2C 100 kHz，SCL=J1.1(D14)、SDA=J1.2(G11)，跑在 50 MHz 域。
 // 每 200 ms 给一次 lux（lux = raw/1.2），用 toggle 跨到 25 MHz 像素域。
 wire [15:0] lux_sys,raw_sys;wire lux_dv_sys,lux_err_sys,i2c_busy_sys;
 guide_bh1750 sensor(.clk(sys_clk),.rst_n(sys_rst_n),.i2c_scl(i2c_scl),.i2c_sda(i2c_sda),
  .lux(lux_sys),.raw(raw_sys),.data_valid(lux_dv_sys),.error(lux_err_sys),.i2c_busy(i2c_busy_sys));
 reg lux_tog;
 always @(posedge sys_clk or negedge sys_rst_n)
  if(!sys_rst_n) lux_tog<=1'b0;else if(lux_dv_sys) lux_tog<=~lux_tog;
 wire sd_ready,sec_req,sec_valid,sec_done,mem_restart;wire [31:0] lba;wire [7:0] sd_data,sd_error;
 // FAST_DIV=2 -> 41.67/4 = 10.4 MHz（原来是 3 -> 6.94 MHz）。SD 卡扛不住就改回 3。
 sd_spi_reader #(.FAST_DIV(2)) card(.clk(mclk),.rst(rst),.restart(mem_restart),.cs_n(sd_ncs),.sck(sd_dclk),.mosi(sd_mosi),.miso(sd_miso),
  .ready(sd_ready),.read_req(sec_req),.read_lba(lba),.data(sd_data),.valid(sec_valid),.done(sec_done),.error(sd_error));
 wire stream_start,stream_cancel,stream_busy,stream_done,stream_valid,stream_ready;
 wire [87:0] filename;wire [7:0] stream_data,stream_error,stage;wire [31:0] file_size;
 guide_fat_stream files(.clk(mclk),.rst(rst),.start(stream_start),.cancel(stream_cancel),.restart(mem_restart),.filename(filename),
  .transport_ready(sd_ready),.sec_req(sec_req),.sec_lba(lba),.sec_data(sd_data),.sec_valid(sec_valid),
  .sec_done(sec_done),.transport_error(sd_error),.data(stream_data),.valid(stream_valid),.ready(stream_ready),
  .done(stream_done),.busy(stream_busy),.file_size(file_size),.error(stream_error),.debug_state(stage));
 wire bmp_start,bmp_done,memory_idle,loaded,audio_flush,audio_mode,audio_eof,audio_error,boot_done,bmp_raw;
 wire [23:0] total_samples;
 wire [10:0] bmp_width;wire [9:0] bmp_height,bmp_left,bmp_top;wire [20:0] bmp_base;
 wire [7:0] bmp_error,error;wire [3:0] load_index;wire play_toggle;wire [3:0] page;
 // 紧急播报相关的网络必须在这里（用法之前）声明：否则 Verilog 会当成隐式 1 位网络，
 // 后面再声明 3 位就被忽略——页号被截成 1 位，整条字幕/紧急通路会被综合成常量。
 wire emg,emg_tick;wire [3:0] emg_page;wire [3:0] vpage;
 wire ad,ad_tick;wire [3:0] ad_page;
 wire dev;                                   // 开发者模式（SW1 拨上，最高优先级）
 wire no_audio=vpage>=4'd7;                 // 广告页/开发者页没有配音，media 直接跳过开音频
 wire freeze=emg||ad||dev;                   // 导览被接管（紧急/广告/开发者）
 // 只跟随实际可见页面和当前模式的重播事件。后台广告变化不能重启前台紧急音轨。
 // 同一拍的多个变化合并为一次；音频、字幕和频谱共用 play_eff。
 reg pt_d,emg_tick_d;reg [3:0] media_page;reg play_eff;
 wire play_change=(vpage!=media_page)||(!freeze&&play_toggle!=pt_d)||
                  (emg&&!dev&&emg_tick!=emg_tick_d);
 always @(posedge pclk or posedge prst) begin
  if(prst) begin pt_d<=0;emg_tick_d<=0;media_page<=0;play_eff<=0;end
  else begin
   pt_d<=play_toggle;emg_tick_d<=emg_tick;media_page<=vpage;
   if(play_change) play_eff<=~play_eff;
  end
 end
 guide_media #(.PREFER_BMP(1),.ROUTE_CARD(1)) media(.clk(mclk),.rst(rst),.play_toggle(play_eff),.page(vpage),.no_audio(no_audio),.stream_busy(stream_busy),
  .stream_done(stream_done),.stream_error(stream_error),.file_size(file_size),.stream_start(stream_start),
  .stream_cancel(stream_cancel),.filename(filename),.bmp_done(bmp_done),.bmp_error(bmp_error),
  .memory_idle(memory_idle),.bmp_start(bmp_start),.bmp_width(bmp_width),.bmp_height(bmp_height),
  .bmp_base(bmp_base),.bmp_left(bmp_left),.bmp_top(bmp_top),.loaded(loaded),.load_index(load_index),.boot_done(boot_done),
  .error(error),.audio_flush(audio_flush),.audio_mode(audio_mode),.audio_eof(audio_eof),.audio_error(audio_error),
  .mem_restart(mem_restart),.bmp_raw(bmp_raw),.total_samples(total_samples));
 wire bwv,bwr,br;wire [20:0] bwa;wire [31:0] bwd;
 guide_bmp bmp(.clk(mclk),.rst(rst),.start(bmp_start),.raw(bmp_raw),.width(bmp_width),.height(bmp_height),
  .base(bmp_base),.left(bmp_left),.top(bmp_top),.data(stream_data),.valid(stream_valid && !audio_mode),
  .ready(br),.file_done(stream_done && !audio_mode),.file_size(file_size),.wr_valid(bwv),.wr_ready(bwr),
  .wr_addr(bwa),.wr_data(bwd),.done(bmp_done),.error(bmp_error));
 wire init,refreshing,we,re,rv;wire [20:0] wa,ra;wire [31:0] wd,rd;
 wire line_req,line_ack,line_we;wire [9:0] line_y;wire [3:0] line_page;wire [8:0] line_addr;wire [31:0] line_data;
 wire [15:0] mem_words;
 guide_memory memory(.clk(mclk),.rst(rst),.mem_init(init),.mem_refresh(refreshing),
  .source_valid(bwv),.source_ready(bwr),.source_addr(bwa),.source_data(bwd),.display_enable(loaded||boot_done),.idle(memory_idle),
  .line_req(line_req),.line_y(line_y),.line_page(line_page),.line_ack(line_ack),.line_we(line_we),
  .line_addr(line_addr),.line_data(line_data),.wr_en(we),.wr_addr(wa),.wr_data(wd),
  .rd_en(re),.rd_addr(ra),.rd_valid(rv),.rd_data(rd),.words(mem_words),.restart(mem_restart));
 sdram_bridge ram(.clk(mclk),.clk_shift(mshift),.rst(rst),.init(init),.refreshing(refreshing),
  .wr_en(we),.wr_addr(wa),.wr_data(wd),.rd_en(re),.rd_addr(ra),.rd_valid(rv),.rd_data(rd));
 wire next_tap,home_hold,auto_tap,auto_hold,pause_tap,replay_hold;
 guide_key #(.DEBOUNCE(CLOCK_HZ/50),.LONG(CLOCK_HZ)) k2(pclk,prst,key2,next_tap,home_hold);
 guide_key #(.DEBOUNCE(CLOCK_HZ/50),.LONG(CLOCK_HZ)) k3(pclk,prst,key3,auto_tap,auto_hold);
 guide_key #(.DEBOUNCE(CLOCK_HZ/50),.LONG(CLOCK_HZ)) k4(pclk,prst,key4,pause_tap,replay_hold);
 // 下面两组信号在 emg/ad/control 的实例里都要用到，必须先声明后使用（Verilog 不允许先用后声明；
 // 先当隐式 1 位网络用、后面再声明 3 位，会把页号截成 1 位）。
 // 拨码（板卡 SW1..SW4 = C8/C7/C6/C5）：SW1 = 开发者模式（最高优先级），
 // SW2 = 切换导览方向，SW3 = 静音，SW4 = 触发至少 5 秒的广告演示。
 reg [1:0] loaded_p,aerr_p;reg [3:0] sw1,sw2;
 wire auto_mode,paused,frame_boundary,audio_done,audio_playing;wire [6:0] seconds,period;wire [7:0] fade;wire zoom;
 wire route_visible,route_hold,control_idle;wire [7:0] route_fade;
 reg [2:0] station;
 always @(posedge pclk or posedge prst)
  if(prst)station<=0;else if(page>=1&&page<=5)station<=page-1'b1;
 guide_route_panel panel(.clk(pclk),.rst(prst),.enabled(loaded_p[1]),.frame_boundary(frame_boundary),
  .toggle(home_hold&&!freeze),.close(next_tap&&route_visible),.suspended(freeze),.can_open(control_idle),
  .visible(route_visible),.active(route_hold),.fade(route_fade));
 // Three stable frames debounce the closure input. Replanning also tracks station.
 reg road_closed;reg [1:0] road_count;
 always @(posedge pclk or posedge prst)begin
  if(prst)begin road_closed<=0;road_count<=0;end
  else if(frame_boundary)begin
   if(sw2[1]==road_closed)road_count<=0;
   else if(road_count==2)begin road_closed<=sw2[1];road_count<=0;end
   else road_count<=road_count+1'b1;
  end
 end
 // SW2 chooses the tour order, shared by route animation and guide_control.
 wire route_valid=1'b1;wire [5:0] route_edges=6'b111111;
 // 开发者模式：SW1 去抖 -> 菜单状态机 -> 一组运行时参数（亮度手动/自动、PIR 延迟、音量、广告停留、周期）。
 // 按键：K2 上移 / K3 下移 / K4 修改（K1 是硬复位，做不了方向键）。
 reg [17:0] dev_cnt;reg dev_sw;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin dev_cnt<=0;dev_sw<=0;end
  else if(sw2[0]!=dev_sw) begin
   if(dev_cnt==18'h3ffff) begin dev_cnt<=0;dev_sw<=sw2[0];end
   else dev_cnt<=dev_cnt+1'b1;
  end else dev_cnt<=0;
 end
 wire bright_manual;wire [8:0] bright_gain,bright_manual_gain;
 wire [3:0] dev_row;wire [3:0] dev_col;
 wire [23:0] absent_frames,ad_frames;wire [1:0] cfg_volume;wire [6:0] period_s;wire vu_on;wire [23:0] dev_sel;wire [1:0] cfg_contrast;
 guide_dev devctl(.pclk(pclk),.prst(prst),.sw_dev(dev_sw),
  .tap_up(next_tap),.tap_dn(auto_tap),.tap_edit(pause_tap),.cur_gain(bright_gain),
  .dev(dev),.row(dev_row),.col(dev_col),.bright_manual(bright_manual),.bright_gain(bright_manual_gain),
  .absent_frames(absent_frames),.volume(cfg_volume),.ad_frames(ad_frames),.period_s(period_s),.vu_on(vu_on),
  .contrast(cfg_contrast),.sel(dev_sel));
 // K4 长按 = 紧急播报（进入/退出），紧急态下短按 = 本条重播；"从头重播"改为讲解结束后短按。
 // 开发者模式里 K4 短按是"修改"，K4 长按不再触发紧急
 guide_emg emgctl(.pclk(pclk),.prst(prst),.enable(loaded_p[1]),.hold(replay_hold && !dev),.tap(pause_tap && !dev),
  .emg(emg),.emg_page(emg_page),.tick(emg_tick));
 assign vpage=dev?4'd10:(emg?emg_page:(ad?ad_page:page));   // 开发者 > 紧急 > 广告 > 导览
 // PIR remains live during the SW4 demo so it can return after the hold.
 reg [1:0] pir_sync;always @(posedge pclk or posedge prst) if(prst) pir_sync<=0;else pir_sync<={pir_sync[0],pir};
 // 开发者模式下当作"有人"：广告立即退出、无人计时清零
 wire motion=pir_sync[1]||dev;
 // 讲解结束（或音频出错）之前不进广告：中途只留给紧急播报打断（BUG-4）。
 // T_ABSENT=1200 帧 = 20 s @60 fps：PIR 掉线后自己还保持约 10 s，所以人走开后约 30 s 进广告；
 // 现场觉得太慢/太快就改这一个数（1 s = 60）。
 wire narration_done=!freeze && !route_hold && (audio_done||aerr_p[1]);
 guide_ad adctl(.pclk(pclk),.prst(prst),.frame_boundary(frame_boundary),
  .motion(motion||route_hold),.force_absent(sw2[3]),.enable(loaded_p[1]&&!dev&&!emg&&!route_hold),.narration_done(narration_done),
  .absent_frames(absent_frames),.ad_frames(ad_frames),
  .ad(ad),.ad_page(ad_page),.tick(ad_tick));
 reg [5:0] blink;always @(posedge pclk or posedge prst) if(prst) blink<=0;else blink<=blink+1'b1;
 wire emg_blink=emg&&blink[5];
 always @(posedge pclk or posedge prst) begin
  if(prst) begin loaded_p<=0;aerr_p<=0;sw1<=15;sw2<=15;end
  else begin loaded_p<={loaded_p[0],loaded};aerr_p<={aerr_p[0],audio_error};sw1<=switches;sw2<=sw1;end
 end
 guide_control #(.CLOCK_HZ(CLOCK_HZ),.ROUTE_SELECT(1)) controls(.clk(pclk),.rst(prst),.enabled(loaded_p[1]),.next_tap(next_tap && !dev),
  .home_hold(1'b0),.auto_tap(auto_tap && !dev),
  .pause_tap(pause_tap && !freeze),.replay_hold(1'b0),
  .period_cfg(period_s),.audio_done(!freeze && (audio_done || aerr_p[1])),
  .audio_playing(freeze || audio_playing),
  .frame_boundary(frame_boundary),
  .page(page),.auto_mode(auto_mode),.paused(paused),.play_toggle(play_toggle),.seconds(seconds),.period(period),.fade(fade),
  .zoom_hold(auto_hold),.zoom(zoom),.suspended(freeze||route_hold),.route_reverse(road_closed),.idle(control_idle));
 // SW3 拨上 = 静音：只把 HDMI 音频包清零，FIFO 读指针和字幕时间轴照常走，
 // 所以解除静音后从"本来该播到"的位置继续，不会重头；轮播推进也不受影响。
 // 紧急播报（emg）不受静音影响 —— 应急优先；要连紧急一起静音，把 !emg 去掉即可。
 wire audio_mute=sw2[2]&&!emg;
 wire audio_paused=(paused||route_hold)&&!emg;
 wire ar,sample_valid,sample_played,audio_under;wire [23:0] sample;
 guide_audio #(.CLOCK_HZ(CLOCK_HZ)) audio(.mclk(mclk),.mrst(rst),.flush(audio_flush),.data(stream_data),.valid(stream_valid && audio_mode),
  .ready(ar),.eof(audio_eof),.pclk(pclk),.prst(prst),.paused(audio_paused),.mute(audio_mute),
  .volume(cfg_volume),.sample_valid(sample_valid),.sample(sample),.ended(audio_done),
  .playing(audio_playing),.underrun(audio_under),.sample_played(sample_played));
 // The length is stable before FIFO playback starts; synchronize the stable bus.
 reg [23:0] total_meta,total_p;reg [1:0] flush_p;
 always @(posedge pclk or posedge prst)begin
  if(prst)begin total_meta<=0;total_p<=0;flush_p<=3;end
  else begin total_meta<=total_samples;total_p<=total_meta;flush_p<={flush_p[0],audio_flush};end
 end
 wire [23:0] audio_position;wire [9:0] route_progress;
 wire [15:0] elapsed_bcd,total_bcd;
 guide_route_time timeline(.clk(pclk),.rst(prst),.restart(play_change||flush_p[1]),
  .sample_played(sample_played),.total_samples(total_p),.done(audio_done&&!aerr_p[1]),
  .position(audio_position),.progress(route_progress),.elapsed_bcd(elapsed_bcd),.total_bcd(total_bcd));
 assign stream_ready=audio_mode?ar:br;
 wire acr_valid;
 guide_acr acr(.clk(pclk),.rst(prst),.sample_valid(sample_valid),.valid(acr_valid));
 // ---- 环境光自适应亮度 ----
 // lux 在 50 MHz 域 200 ms 才变一次，用 toggle 做准静态跨域；lux_p 和 lux_valid 同拍对齐
 // （lux_new_r 比 lux_p 晚一拍拉高，正好让 guide_bright 采到新值）。
 reg [1:0] lux_sync;reg [15:0] lux_p;reg lux_new_r;
 wire lux_edge=lux_sync[0]^lux_sync[1];
 always @(posedge pclk or posedge prst) begin
  if(prst) begin lux_sync<=0;lux_p<=0;lux_new_r<=0;end
  else begin
   lux_sync<={lux_sync[0],lux_tog};
   lux_new_r<=lux_edge;
   if(lux_edge) lux_p<=lux_sys;
  end
 end
 guide_bright brightctl(.pclk(pclk),.prst(prst),.lux(lux_p),.lux_valid(lux_new_r),
  .emg(emg),.frame_boundary(frame_boundary),.manual(bright_manual),.manual_gain(bright_manual_gain),
  .gain(bright_gain));
 wire vr,vu,vl,video_under,valid;wire [23:0] rgb;wire [7:0] rows_bad;
 // 开机卡：PIC11 先装进第 12 页并立刻显示，等其余 11 页装完再切回正常页
 wire boot=boot_done&&!loaded;
 wire [3:0] boot_prog=boot_done?((load_index==12)?4'd12:load_index+1'b1):4'd0;
 wire [3:0] visual_page=(!freeze&&route_visible)?4'd12:vpage;
 wire [7:0] visual_fade=freeze?8'd255:(route_hold?route_fade:fade);
 guide_video_640 #(.ROUTE_UI(1),.NATIVE_PANEL(NATIVE_PANEL)) video(.pclk(pclk),.prst(prst),.mclk(mclk),.enabled(loaded||boot_done),.page(boot?4'd11:visual_page),
  .load_index(load_index),.error(error),
  .frame_boundary(frame_boundary),.line_req(line_req),.line_y(line_y),.line_page(line_page),.line_ack(line_ack),
  .line_we(line_we),.line_addr(line_addr),.line_data(line_data),
  .valid(valid),.ready(vr),.user(vu),.last(vl),.rgb(rgb),.underrun(video_under),.rows_bad(rows_bad),.fade(visual_fade),.zoom(zoom),
  .auto_mode(auto_mode),.paused(audio_paused),.audio_playing(audio_playing),.audio_done(audio_done||aerr_p[1]),.osd_en(DRAW_OSD!=0),
  .sample_valid(sample_valid),.play_toggle({1'b0,play_eff}),.brightness(bright_gain),.dev_row(dev_row),.dev_col(dev_col),
  .vu_on(vu_on),.sample(sample),.dev_sel(dev_sel),.contrast(cfg_contrast),.boot(boot),.boot_prog(boot_prog),
  .sample_played(sample_played),.route_station(station),.route_closed(road_closed),
  .route_edges(route_edges),.route_valid(route_valid),.route_progress(route_progress),
  .elapsed_bcd(elapsed_bcd),.total_bcd(total_bcd));
 wire vv=valid;
 reg [19:0] edid_count;reg edid_trig;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin edid_count<=0;edid_trig<=0;end
  else begin edid_trig<=0;if(edid_count!=200000) edid_count<=edid_count+1'b1;
   if(edid_count==199999) edid_trig<=1;end
 end
 wire [9:0] ch0,ch1,ch2,chclk;wire video_locked;wire edid_valid;
 hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),
  .HTOTAL(NATIVE_PANEL?1344:800),.HSA(NATIVE_PANEL?136:96),.HFP(NATIVE_PANEL?24:16),.HBP(NATIVE_PANEL?160:48),.HACTIVE(NATIVE_PANEL?1024:640),
  .VTOTAL(NATIVE_PANEL?635:525),.VSA(NATIVE_PANEL?6:2),.VFP(NATIVE_PANEL?3:10),.VBP(NATIVE_PANEL?26:33),.VACTIVE(NATIVE_PANEL?600:480),
  .VIDEO_VIC(NATIVE_PANEL?0:1),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(255)) hdmi(
  .I_pixel_clk(pclk),.I_rst(prst),.I_edid_read_trig(edid_trig),.O_edid_read_valid(edid_valid),.O_edid_read_data(),
  .I_axis_s_user(vu),.I_axis_s_valid(vv),.I_axis_s_last(vl),.I_axis_s_data(rgb),.O_axis_s_ready(vr),
  .I_audio_valid(sample_valid),.I_audio_left_data(sample),.I_audio_right_data(sample),
  .I_acr_valid(acr_valid),.I_acr_cts(NATIVE_PANEL?20'd51000:20'd25000),.I_acr_n(20'd6144),
  .O_video_locked(video_locked),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
  .O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(chclk));
 hdmi_phy_wrapper #(.DEVICE("EG")) phy(.I_pixel_clk(pclk),.I_serial_clk(fastclk),.I_rst(prst),
  .I_tmds_channel_0(ch0),.I_tmds_channel_1(ch1),.I_tmds_channel_2(ch2),.I_tmds_channel_clk(chclk),
  .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
 reg ready_conflict;
 always @(posedge pclk or posedge prst) begin
  if(prst) ready_conflict<=0;
  else if(vv && !vr && video_locked) ready_conflict<=1;
 end
 reg [1:0] vs,ms,rs;reg [7:0] vlf,mlf,rcnt;
 assign led={loaded^emg_blink,(error!=0 || aerr_p[1] || audio_under || video_under || (vlf!=8'd0) || ready_conflict),init,video_locked};
 always @(posedge sys_clk or negedge sys_rst_n) begin
  if(!sys_rst_n) begin vs<=0;ms<=0;rs<=0;vlf<=0;mlf<=0;rcnt<=0;end
  else begin
   vs<={vs[0],v_locked};ms<={ms[0],m_locked};rs<={rs[0],prst};
   if(vs[1] && !vs[0] && vlf!=8'hff) vlf<=vlf+1'b1;
   if(ms[1] && !ms[0] && mlf!=8'hff) mlf<=mlf+1'b1;
   if(!rs[1] && rs[0] && rcnt!=8'hff) rcnt<=rcnt+1'b1;
  end
 end
 reg [15:0] frame_cnt;reg [7:0] edid_bytes;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin frame_cnt<=0;edid_bytes<=0;end
  else begin
   if(vu) frame_cnt<=frame_cnt+1'b1;
   if(edid_valid && edid_bytes!=8'hff) edid_bytes<=edid_bytes+1'b1;
  end
 end
 guide_telemetry tel(.clk(sys_clk),.rst(!sys_rst_n),
  .v_locked(v_locked),.m_locked(m_locked),.init(init),.loaded(loaded),.au_under(audio_under || audio_error || ready_conflict),
  .vlf(vlf),.mlf(mlf),.rcnt(rcnt),.err(error),.rows_bad(rows_bad),.edid(edid_bytes),
  .frames(frame_cnt),.words(mem_words),.page(page[2:0]),.load_index(load_index),.tx(uart_tx));
endmodule
