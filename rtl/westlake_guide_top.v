// Scenic guide top: TF/FAT32 resource load, SDRAM page cache, HDMI 1.4b video+audio.
// A 50 MHz-domain telemetry stream on uart_tx reports lock/reset/load state at
// 115200 8N1 once per 0.5 s, so field failures can be read without a scope.
// DRAW_UI = 1 draws the full decorative interface (gradient, three mountain
// layers, card mat, route rail, key hints, text masks). DRAW_UI = 0 keeps only
// the paper gradient and the 640x480 card window, which is what the current
// bring-up needs: every non-card pixel is one predictable colour, so a missing
// photo can only come from the SDRAM line path.
module westlake_guide_top #(parameter DRAW_UI = 0) (input sys_clk,input sys_rst_n,
 input key2,input key3,input key4,
 input [3:0] switches,input sd_miso,output sd_ncs,output sd_dclk,output sd_mosi,output [3:0] led,
 output HDMI_CLK_P,output HDMI_D0_P,output HDMI_D1_P,output HDMI_D2_P,
 output HDMI_DDC_SCL,inout HDMI_DDC_SDA,output uart_tx);
 wire pclk,fastclk,mclk,mshift,unused,m_locked,v_locked;
 hdmi_pll u_hdmi_pll(.refclk(sys_clk),.reset(~sys_rst_n),.extlock(v_locked),.clk0_out(fastclk),.clk1_out(pclk));
 sys_pll u_sys_pll(.refclk(sys_clk),.reset(~sys_rst_n),.extlock(m_locked),.clk0_out(unused),.clk1_out(mclk),.clk2_out(mshift));
 // --- reset controller (50 MHz oscillator domain) ---------------------------
 // Same intent as the tutorial lab_ex4 top: wait for both PLLs to stay locked
 // for 20 ms, release the reset once, then ignore later extlock dips. Re-arming
 // the whole design on a 1-clock extlock glitch resets the HDMI core, which
 // drops the TMDS link and shows up as the panel's blue/black blinking.
 localparam [19:0] LOCK_HOLD=20'd999_999;
 reg [19:0] lock_cnt;reg sys_run;
 always @(posedge sys_clk or negedge sys_rst_n) begin
  if(!sys_rst_n) begin lock_cnt<=0;sys_run<=0;end
  else if(!sys_run) begin
   if(v_locked && m_locked) begin
    if(lock_cnt==LOCK_HOLD) sys_run<=1;else lock_cnt<=lock_cnt+1'b1;
   end else lock_cnt<=0;
  end
 end
 wire arst=!sys_run;
 reg [16:0] mr,pr;
 always @(posedge mclk or posedge arst) if(arst) mr<=0;else mr<={mr[15:0],1'b1};
 always @(posedge pclk or posedge arst) if(arst) pr<=0;else pr<={pr[15:0],1'b1};
 wire rst=~mr[16],prst=~pr[16];
 wire sd_ready,sec_req,sec_valid,sec_done;wire [31:0] lba;wire [7:0] sd_data,sd_error;
 sd_spi_reader card(.clk(mclk),.rst(rst),.restart(mem_restart),.cs_n(sd_ncs),.sck(sd_dclk),.mosi(sd_mosi),.miso(sd_miso),
  .ready(sd_ready),.read_req(sec_req),.read_lba(lba),.data(sd_data),.valid(sec_valid),.done(sec_done),.error(sd_error));
 wire stream_start,stream_cancel,stream_busy,stream_done,stream_valid,stream_ready;
 wire [87:0] filename;wire [7:0] stream_data,stream_error,stage;wire [31:0] file_size;
 guide_fat_stream files(.clk(mclk),.rst(rst),.start(stream_start),.cancel(stream_cancel),.restart(mem_restart),.filename(filename),
  .transport_ready(sd_ready),.sec_req(sec_req),.sec_lba(lba),.sec_data(sd_data),.sec_valid(sec_valid),
  .sec_done(sec_done),.transport_error(sd_error),.data(stream_data),.valid(stream_valid),.ready(stream_ready),
  .done(stream_done),.busy(stream_busy),.file_size(file_size),.error(stream_error),.debug_state(stage));
 wire bmp_start,bmp_done,memory_idle,loaded,audio_flush,audio_mode,audio_eof,audio_error,mem_restart;
 wire [10:0] bmp_width;wire [9:0] bmp_height,bmp_left,bmp_top;wire [20:0] bmp_base;
 wire [7:0] bmp_error,error;wire [3:0] load_index;wire play_toggle;wire [2:0] page;
 guide_media media(.clk(mclk),.rst(rst),.play_toggle(play_toggle),.page(page),.stream_busy(stream_busy),
  .stream_done(stream_done),.stream_error(stream_error),.file_size(file_size),.stream_start(stream_start),
  .stream_cancel(stream_cancel),.filename(filename),.bmp_done(bmp_done),.bmp_error(bmp_error),
  .memory_idle(memory_idle),.bmp_start(bmp_start),.bmp_width(bmp_width),.bmp_height(bmp_height),
  .bmp_base(bmp_base),.bmp_left(bmp_left),.bmp_top(bmp_top),.loaded(loaded),.load_index(load_index),
  .error(error),.audio_flush(audio_flush),.audio_mode(audio_mode),.audio_eof(audio_eof),.audio_error(audio_error),
  .mem_restart(mem_restart));
 wire bwv,bwr,br;wire [20:0] bwa;wire [31:0] bwd;
 guide_bmp bmp(.clk(mclk),.rst(rst),.start(bmp_start),.width(bmp_width),.height(bmp_height),
  .base(bmp_base),.left(bmp_left),.top(bmp_top),.data(stream_data),.valid(stream_valid && !audio_mode),
  .ready(br),.file_done(stream_done && !audio_mode),.file_size(file_size),.wr_valid(bwv),.wr_ready(bwr),
  .wr_addr(bwa),.wr_data(bwd),.done(bmp_done),.error(bmp_error));
 wire init,refreshing,we,re,rv;wire [20:0] wa,ra;wire [31:0] wd,rd;
 wire line_req,line_ack,line_we;wire [9:0] line_y;wire [2:0] line_page;wire [8:0] line_addr;wire [31:0] line_data;
 wire [15:0] mem_words;
 guide_memory memory(.clk(mclk),.rst(rst),.mem_init(init),.mem_refresh(refreshing),
  .source_valid(bwv),.source_ready(bwr),.source_addr(bwa),.source_data(bwd),.display_enable(loaded),.idle(memory_idle),
  .line_req(line_req),.line_y(line_y),.line_page(line_page),.line_ack(line_ack),.line_we(line_we),
  .line_addr(line_addr),.line_data(line_data),.wr_en(we),.wr_addr(wa),.wr_data(wd),
  .rd_en(re),.rd_addr(ra),.rd_valid(rv),.rd_data(rd),.words(mem_words),.restart(mem_restart));
 sdram_bridge ram(.clk(mclk),.clk_shift(mshift),.rst(rst),.init(init),.refreshing(refreshing),
  .wr_en(we),.wr_addr(wa),.wr_data(wd),.rd_en(re),.rd_addr(ra),.rd_valid(rv),.rd_data(rd));
 wire next_tap,home_hold,auto_tap,auto_hold,pause_tap,replay_hold;
 guide_key k2(pclk,prst,key2,next_tap,home_hold);
 guide_key k3(pclk,prst,key3,auto_tap,auto_hold);
 guide_key k4(pclk,prst,key4,pause_tap,replay_hold);
 reg [1:0] loaded_p,aerr_p;reg [3:0] sw1,sw2;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin loaded_p<=0;aerr_p<=0;sw1<=15;sw2<=15;end
  else begin loaded_p<={loaded_p[0],loaded};aerr_p<={aerr_p[0],audio_error};sw1<=switches;sw2<=sw1;end
 end
 wire auto_mode,paused,frame_boundary,audio_done,audio_playing;wire [6:0] seconds,period;
 guide_control controls(.clk(pclk),.rst(prst),.enabled(loaded_p[1]),.next_tap(next_tap),
  .home_hold(home_hold),.auto_tap(auto_tap || auto_hold),.pause_tap(pause_tap),.replay_hold(replay_hold),
  .period_select(~sw2[1:0]),.audio_done(audio_done || aerr_p[1]),.audio_playing(audio_playing),
  .frame_boundary(frame_boundary),
  .page(page),.auto_mode(auto_mode),.paused(paused),.play_toggle(play_toggle),.seconds(seconds),.period(period),
  .fade(),.zoom_hold(1'b0),.zoom());
 wire ar,sample_valid,audio_under;wire [23:0] sample;
 guide_audio audio(.mclk(mclk),.mrst(rst),.flush(audio_flush),.data(stream_data),.valid(stream_valid && audio_mode),
  .ready(ar),.eof(audio_eof),.pclk(pclk),.prst(prst),.paused(paused),.mute(1'b0),
  .volume(2'd2),.sample_valid(sample_valid),.sample(sample),.ended(audio_done),
  .playing(audio_playing),.underrun(audio_under));
 assign stream_ready=audio_mode?ar:br;
 wire acr_valid;
 guide_acr acr(.clk(pclk),.rst(prst),.sample_valid(sample_valid),.valid(acr_valid));
 wire vv,vr,vu,vl,video_under;wire [23:0] rgb;wire [7:0] rows_bad;
 guide_video #(.draw_ui(DRAW_UI)) video(.pclk(pclk),.prst(prst),.mclk(mclk),.enabled(loaded),.page(page),
  .load_index(load_index),.error(error),.auto_mode(auto_mode),.paused(paused),.audio_done(audio_done),
  .audio_error(aerr_p[1]),.period(period),.audio_playing(audio_playing),.frame_boundary(frame_boundary),
  .line_req(line_req),.line_y(line_y),.line_page(line_page),.line_ack(line_ack),.line_we(line_we),
  .line_addr(line_addr),.line_data(line_data),.valid(vv),.ready(vr),.user(vu),.last(vl),.rgb(rgb),.underrun(video_under),
  .rows_bad(rows_bad));
 reg [19:0] edid_count;reg edid_trig;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin edid_count<=0;edid_trig<=0;end
  else begin edid_trig<=0;if(edid_count!=200000) edid_count<=edid_count+1'b1;
   if(edid_count==199999) edid_trig<=1;end
 end
 wire [9:0] ch0,ch1,ch2,chclk;wire video_locked;wire edid_valid;
 hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),
  .HTOTAL(1344),.HSA(136),.HFP(24),.HBP(160),.HACTIVE(1024),
  .VTOTAL(635),.VSA(6),.VFP(3),.VBP(26),.VACTIVE(600),
  .VIDEO_VIC(0),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(255)) hdmi(
  .I_pixel_clk(pclk),.I_rst(prst),.I_edid_read_trig(edid_trig),.O_edid_read_valid(edid_valid),.O_edid_read_data(),
  .I_axis_s_user(vu),.I_axis_s_valid(vv),.I_axis_s_last(vl),.I_axis_s_data(rgb),.O_axis_s_ready(vr),
  .I_audio_valid(sample_valid),.I_audio_left_data(sample),.I_audio_right_data(sample),
  .I_acr_valid(acr_valid),.I_acr_cts(20'd51000),.I_acr_n(20'd6144),
  .O_video_locked(video_locked),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
  .O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(chclk));
 hdmi_phy_wrapper #(.DEVICE("EG")) phy(.I_pixel_clk(pclk),.I_serial_clk(fastclk),.I_rst(prst),
  .I_tmds_channel_0(ch0),.I_tmds_channel_1(ch1),.I_tmds_channel_2(ch2),.I_tmds_channel_clk(chclk),
  .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
 // LED3 latches any of: resource error, audio/video underrun, a fall of
 // O_video_locked, or a cycle where we drove I_axis_s_valid while the core
 // signalled O_axis_s_ready=0. That last one is the AXI-Stream contract the
 // tutorial's reference also ignores; at HACTIVE=1024 the input elastic FIFO is
 // exactly one line deep, so an overrun there would show up as exactly this
 // kind of intermittent output corruption.
 reg ready_conflict;
 always @(posedge pclk or posedge prst) begin
  if(prst) ready_conflict<=0;
  else if(vv && !vr && video_locked) ready_conflict<=1;
 end
 assign led={loaded,(error!=0 || aerr_p[1] || audio_under || video_under || (vlf!=8'd0) || ready_conflict),init,video_locked};
 // --- diagnostics ----------------------------------------------------------
 // Counters live in the 50 MHz oscillator domain so a dead PLL still reports.
 reg [1:0] vs,ms,rs;reg [7:0] vlf,mlf,rcnt;
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
  .frames(frame_cnt),.words(mem_words),.page(page),.load_index(load_index),.tx(uart_tx));
endmodule
