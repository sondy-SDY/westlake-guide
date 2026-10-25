`timescale 1ns/1ps
module tb_hdmi_source_compare;
 reg clk=0,mclk=0,rst=1,ready=0;
 always #5 clk=~clk; always #6 mclk=~mclk;
 wire vv,vu,vl,gv,gu,gl; wire [23:0] vrgb,grgb;
 video_source_test #(.HTOTAL(1344),.HACTIVE(1024),.HFP(24),.HSA(136),.HBP(160),
  .VTOTAL(635),.VACTIVE(600),.VFP(3),.VSA(6),.VBP(26)) reference(
  .I_clk(clk),.I_rst(rst),.I_tpg_trig_en(1'b1),.O_video_valid(vv),.O_video_user(vu),
  .O_video_last(vl),.O_video_data(vrgb),.I_video_ready(ready));
 guide_video guide(.pclk(clk),.prst(rst),.mclk(mclk),.enabled(1'b0),.page(3'd0),
  .load_index(4'd0),.error(8'd0),.auto_mode(1'b0),.paused(1'b0),.audio_done(1'b0),
  .audio_error(1'b0),.period(7'd10),.audio_playing(1'b0),.frame_boundary(),
  .line_req(),.line_y(),.line_page(),.line_ack(1'b0),.line_we(1'b0),
  .line_addr(9'd0),.line_data(32'd0),.valid(gv),.ready(ready),.user(gu),.last(gl),.rgb(grgb),.underrun());
 reg [2:0] guide_delayed=0; reg prev_valid=0;
 integer cycles=0,sof=-1,row_start=-1,rows=0,pixels=0,frames=0,total_pixels=0;
 always @(negedge clk) ready=(cycles%17!=0 && cycles%1344<1024);
 always @(posedge clk) begin
  #1;
  if(rst) begin cycles=0;guide_delayed=0;prev_valid=0;end
  else begin
   cycles=cycles+1;
   // Vendor trigger latch delays source startup by one clock. After that,
   // compare every valid/user/last cycle, including horizontal/vertical blank.
   if({vv,vu,vl} !== guide_delayed)
    $fatal(1,"vendor/guide timing mismatch cycle=%0d vendor=%b guide_delayed=%b",cycles,{vv,vu,vl},guide_delayed);
   guide_delayed={gv,gu,gl};
   if((vu || vl) && !vv) $fatal(1,"marker outside valid");
   if(vv && !prev_valid) begin
    if(vu) begin
     if(sof>=0 && (cycles-sof!=1344*635 || rows!=600)) $fatal(1,"frame cadence/row count");
     sof=cycles;rows=0;
    end else if(cycles-row_start!=1344) $fatal(1,"row cadence");
    row_start=cycles;rows=rows+1;pixels=0;
   end
   if(vv) begin
    if(vu!==(rows==1 && pixels==0) || vl!==(pixels==1023)) $fatal(1,"pixel marker");
    if(^vrgb===1'bx) $fatal(1,"undefined vendor RGB");
    pixels=pixels+1;total_pixels=total_pixels+1;
   end
   if(!vv && prev_valid) begin
    if(pixels!=1024) $fatal(1,"non-contiguous/wrong-length row");
    if(rows==600) begin
     frames=frames+1;
     if(frames==4) begin
      $display("PASS vendor/guide control waveform equivalence: 4 frames, %0d pixels, fixed 1024/1344/635, ready perturbations; vendor startup is one clock later",total_pixels);
      $finish;
     end
    end
   end
   prev_valid=vv;
  end
 end
 initial begin #30;@(negedge clk) rst=0;end
 initial begin #40000000;$fatal(1,"timeout");end
endmodule
