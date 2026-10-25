module guide_key #(parameter DEBOUNCE=1020000,parameter LONG=51000000)(
 input clk,input rst,input key_n,output reg tap,output reg hold);
 reg [1:0] sync;reg stable;reg [25:0] count,held;reg long_sent;
 always @(posedge clk or posedge rst) begin
  if(rst) begin sync<=3;stable<=1;count<=0;held<=0;long_sent<=0;tap<=0;hold<=0;end
  else begin
   sync<={sync[0],key_n};tap<=0;hold<=0;
   if(sync[1]==stable) count<=0;
   else if(count==DEBOUNCE-1) begin
    stable<=sync[1];count<=0;
    if(sync[1] && !long_sent) tap<=1;
    if(!sync[1]) begin held<=0;long_sent<=0;end
   end else count<=count+1'b1;
   if(!stable && !long_sent) begin
    if(held==LONG-1) begin hold<=1;long_sent<=1;end else held<=held+1'b1;
   end
  end
 end
endmodule

// All application changes happen in the pixel domain; the page is latched in vblank.
// A fade sequencer sits in front of the switch: fade out to paper -> swap the page
// (and restart the narration) -> fade in. Only one page is read from SDRAM at a
// time, so the transition costs no extra bandwidth.
module guide_control #(parameter CLOCK_HZ=51000000,parameter FADE_TICK=2)(
 input clk,input rst,input enabled,input next_tap,input home_hold,input auto_tap,
 input pause_tap,input replay_hold,input [6:0] period_cfg,input audio_done,input audio_playing,
 input frame_boundary,output reg [3:0] page,output reg auto_mode,output reg paused,
 output reg play_toggle,output reg [6:0] seconds,output [6:0] period,output reg [7:0] fade,
 input zoom_hold,output reg zoom);
 reg [25:0] ticks;reg [3:0] wanted;reg was_enabled;reg replay;
 reg [1:0] fphase;reg [1:0] ftick;
 assign period=period_cfg;   // 轮播周期由开发者模式设置（10/20/30/60 s）
 always @(posedge clk or posedge rst) begin
  if(rst) begin page<=0;wanted<=0;auto_mode<=0;paused<=0;play_toggle<=0;
   seconds<=0;ticks<=0;was_enabled<=0;replay<=0;fphase<=0;ftick<=0;fade<=8'd255;zoom<=0;end
  else begin
   was_enabled<=enabled;
   if(enabled && !was_enabled) replay<=1;
   if(enabled && !paused) begin
    if(ticks==CLOCK_HZ-1) begin ticks<=0;if(seconds!=127) seconds<=seconds+1'b1;end
    else ticks<=ticks+1'b1;
   end
   if(enabled) begin
    if(next_tap) wanted<=page==5?3'd1:page+1'b1;
    if(home_hold) begin wanted<=0;auto_mode<=0;end
    // 只有"打开"时才清零停留计时，关闭时保留，免得连按 K3 把计时器反复归零。
    if(auto_tap) begin
     if(!auto_mode) begin auto_mode<=1'b1;seconds<=0;ticks<=0;if(page==0) wanted<=1;end
     else auto_mode<=1'b0;
    end
    if(pause_tap) begin
     if(audio_done) replay<=1;else paused<=~paused;
    end
    if(replay_hold) replay<=1;
    // KEY3 长按：整屏放大/还原（短按仍是自动导览，赛题要求②）
    if(zoom_hold) zoom<=~zoom;
    if(auto_mode && !paused && page!=0 && seconds>=period && (audio_done || !audio_playing))
     wanted<=page==5?3'd1:page+1'b1;
   end
   // Fade sequencer: 8 steps of 32, FADE_TICK frames each, out then in.
   if(frame_boundary) begin
    if(fphase==0) begin
     if(enabled && wanted!=page) begin fphase<=1;ftick<=0;end
     else if(enabled && replay) begin
      page<=wanted;play_toggle<=~play_toggle;seconds<=0;ticks<=0;paused<=0;replay<=0;
     end
    end else if(ftick!=(FADE_TICK-1)) ftick<=ftick+1'b1;
    else begin
     ftick<=0;
     if(fphase==1) begin
      if(fade>8'd32) fade<=fade-8'd32;
      else begin
       fade<=8'd0;page<=wanted;play_toggle<=~play_toggle;seconds<=0;ticks<=0;
       paused<=0;replay<=0;fphase<=2;
      end
     end else if(enabled && wanted!=page) fphase<=1;
     else if(fade<8'd224) fade<=fade+8'd32;
     else begin fade<=8'd255;fphase<=0;end
    end
   end
  end
 end
endmodule
