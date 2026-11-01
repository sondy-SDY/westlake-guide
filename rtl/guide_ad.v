// Unattended advertisements wait for narration to finish. SW4 starts a single
// demo: ignore PIR for 300 frames (~5 s), then return when someone is present.
// Lowering SW4 cancels a demo and arms its next rising transition.
module guide_ad #(parameter DEMO_HOLD_FRAMES=300)(
 input pclk,input prst,input frame_boundary,input motion,input force_absent,input enable,
 input narration_done,input [23:0] absent_frames,input [23:0] ad_frames,
 output reg ad,output reg [3:0] ad_page,output reg tick);
 localparam [3:0] AD_FIRST=4'd7,AD_LAST=4'd9;
 localparam HOLD_BITS=(DEMO_HOLD_FRAMES<2)?1:$clog2(DEMO_HOLD_FRAMES+1);
 reg [23:0] last,rot;
 reg ndone_q,demo_armed,demo_run;
 reg [HOLD_BITS-1:0] demo_left;
 always @(posedge pclk or posedge prst)begin
  if(prst)begin
   ad<=0;ad_page<=AD_FIRST;tick<=0;last<=0;rot<=0;ndone_q<=0;
   demo_armed<=1;demo_run<=0;demo_left<=0;
  end else begin
   if(!force_absent)demo_armed<=1;
   if(!enable)begin
    // Higher-priority pages suspend the demo, including its visible hold time.
    last<=0;ndone_q<=0;
   end else begin
    if(frame_boundary)begin
     ndone_q<=narration_done;
     if(motion)last<=0;else if(last!=24'hffffff)last<=last+1'b1;
     if(ad)begin
      if(demo_left!=0)demo_left<=demo_left-1'b1;
      if(ad_frames==0||rot>=ad_frames-1'b1)begin
       rot<=0;ad_page<=(ad_page>=AD_LAST)?AD_FIRST:ad_page+1'b1;
      end else rot<=rot+1'b1;
     end
    end
    if(frame_boundary&&force_absent&&demo_armed)begin
     ad<=1;ad_page<=AD_FIRST;rot<=0;tick<=~tick;
     demo_armed<=0;demo_run<=1;demo_left<=DEMO_HOLD_FRAMES;
    end else if(!ad)begin
     // Two completed-narration frames reject stale EOF during media flush.
     if(frame_boundary&&!motion&&narration_done&&ndone_q&&last>=absent_frames)begin
      ad<=1;ad_page<=AD_FIRST;rot<=0;tick<=~tick;demo_run<=0;demo_left<=0;
     end
    end else if((demo_run&&!force_absent)||(motion&&demo_left==0))begin
     ad<=0;ad_page<=AD_FIRST;tick<=~tick;last<=0;rot<=0;ndone_q<=0;
     demo_run<=0;demo_left<=0;
    end
   end
  end
 end
endmodule
