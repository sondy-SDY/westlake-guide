// Fixed-cadence video source for the Anlogic HDMI 1.4b input interface.
// One 640-word line buffer pair prefetches the next card row while the current
// row streams. Only the 640x480 card window (192,76) is read from SDRAM; the
// remaining 44% of the screen is drawn from coordinates and small ROMs, so the
// storage bus sees 153,600 word reads per frame instead of 307,200.
module guide_video #(parameter draw_ui=0)(input pclk,input prst,input mclk,input enabled,input [2:0] page,
 input [3:0] load_index,input [7:0] error,input auto_mode,input paused,input audio_done,
 input audio_error,input [6:0] period,input audio_playing,
 output reg frame_boundary,output reg line_req,output reg [9:0] line_y,
 output reg [2:0] line_page,input line_ack,input line_we,input [8:0] line_addr,input [31:0] line_data,
 output valid,input ready,output user,output last,output [23:0] rgb,output reg underrun,
 output reg [7:0] rows_bad);
 // APUG092 section 2.4.2: each row must contain 1024 consecutive clocks,
 // with 1344 clocks between row starts and 635 total rows per frame.
 localparam HTOTAL=1344,VTOTAL=635,HBLANK=320,VBLANK=35;
 localparam CX0=192,CY0=76,CW=640,CH=480;
 reg [10:0] h;reg [9:0] v;
 wire active=h>=HBLANK && v>=VBLANK;
 wire [9:0] x=h-HBLANK,y=v-VBLANK;
 wire in_win=x>=CX0 && x<CX0+CW && y>=CY0 && y<CY0+CH;
 wire in_row=y>=CY0 && y<CY0+CH;
 wire [9:0] cx=x-CX0;
 // Two row banks of 320 words; the bank half is 512 entries, so the array
 // stays 1024 deep exactly like the previous full-screen version.
 reg [31:0] lines[0:1023];reg [31:0] q;
 reg [1:0] en_sync,ack_sync;
 reg show,row_good,row_ok,pending;reg [2:0] display_page;
 reg [1:0] bank_valid;reg [9:0] bank_cy0,bank_cy1;reg [2:0] bank_page0,bank_page1;
 wire [9:0] cy=y-CY0;
 wire buffer_good=cy[0]?(bank_valid[1] && bank_cy1==cy && bank_page1==display_page):
                         (bank_valid[0] && bank_cy0==cy && bank_page0==display_page);
 // Read address and write address use the same {bank, word} shape as the
 // previous full-screen build. Keeping an explicit enable and a plain
 // concatenated address is what makes TD infer a 9Kb BRAM here; without the
 // enable it infers distributed LUT RAM, which cannot be written on mclk and
 // read on pclk at the same time (that is what hid every card on the board).
 wire [8:0] cwi=cx[9:1];   // 9 bits: {bank,word} must stay a 10-bit BRAM address
 reg [9:0] xd,yd;reg [4:0] vld,sof,lst;
 reg [3:0] load1,load2;reg [7:0] err1,err2;
 assign user=sof[4];assign last=lst[4];assign valid=vld[4];
 wire [15:0] pixel=xd[0]?q[31:16]:q[15:0];
 wire [23:0] pix_in={pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
 always @(posedge mclk) if(line_we) lines[{line_y[0],line_addr}]<=line_data;
 always @(posedge pclk) if(active) q<=lines[{y[0],cwi}];
 // A compact, generated Chinese text ROM labels the playback state.
 wire [6:0] tx=x-10'd700;wire [4:0] ty=y-10'd14;
 reg [2:0] text_id;wire text_bit;
 always @* begin
  if(!show) text_id=err2!=0?3'd7:3'd6;
  else if(auto_mode && !audio_playing) text_id=3'd1;
  else if(audio_error) text_id=3'd5;
  else if(paused) text_id=3'd3;
  else if(audio_done) text_id=3'd4;
  else if(audio_playing) text_id=3'd2;
  else text_id=3'd0;
 end
 guide_text text_rom(.clk(pclk),.ce(active),.label_id(text_id),.x(tx),.y(ty),.pixel(text_bit));
 wire [23:0] ui_rgb;wire ui_card;
 // draw_ui=1 selects the decorative UI (gradient, mountains, text masks);
 // draw_ui=0 selects the plain background used while the card path is being
 // validated on the board.
 generate if(draw_ui) begin : g_full_ui
  guide_ui ui(.pclk(pclk),.active(active),.x(x),.y(y),.pix_in(pix_in),.badge_px(text_bit),
   .show(show),.row_ok(row_ok),.page(display_page),.auto_mode(auto_mode),
   .load_index(load_index),.error(err2),.rgb(ui_rgb),.card(ui_card));
 end else begin : g_plain_ui
  guide_ui_plain ui(.pclk(pclk),.active(active),.x(x),.y(y),.pix_in(pix_in),.badge_px(text_bit),
   .show(show),.row_ok(row_ok),.page(display_page),.auto_mode(auto_mode),
   .load_index(load_index),.error(err2),.rgb(ui_rgb),.card(ui_card));
 end endgenerate
 assign rgb=ui_rgb;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin
   h<=0;v<=0;xd<=0;yd<=0;vld<=0;sof<=0;lst<=0;frame_boundary<=0;
   en_sync<=0;ack_sync<=0;line_req<=0;line_y<=0;line_page<=0;pending<=0;row_good<=0;row_ok<=0;
   show<=0;display_page<=0;bank_valid<=0;bank_cy0<=0;bank_cy1<=0;bank_page0<=0;bank_page1<=0;
   underrun<=0;rows_bad<=0;load1<=0;load2<=0;err1<=0;err2<=0;
  end else begin
   en_sync<={en_sync[0],enabled};ack_sync<={ack_sync[0],line_ack};
   load1<=load_index;load2<=load1;err1<=error;err2<=err1;frame_boundary<=0;
   if(h==HTOTAL-1) begin h<=0;if(v==VTOTAL-1) v<=0;else v<=v+1'b1;end
   else h<=h+1'b1;
   if(active) begin xd<=x;yd<=y;end
   vld<={vld[3:0],active};
   sof<={sof[3:0],active && x==0 && y==0};
   lst<={lst[3:0],active && x==1023};
   if(pending && ack_sync[1]==line_req) begin
    pending<=0;bank_valid[line_y[0]]<=1;
    if(line_y[0]) begin bank_cy1<=line_y;bank_page1<=line_page;end
    else begin bank_cy0<=line_y;bank_page0<=line_page;end
   end
   // Controls get the boundary first; then latch their updated page.
   if(v==0 && h==0) begin frame_boundary<=1;show<=en_sync[1];bank_valid<=0;row_ok<=1;end
   if(v==0 && h==2) display_page<=page;
   // Fetch card row 0 in vertical blank, then row k during line k-1.
   if(show && !pending && ((v==0 && h==4) ||
      (active && h==HBLANK && y>=CY0 && y<CY0+CH-1))) begin
    line_y<=(v==0)?10'd0:(y-CY0+1'b1);line_page<=display_page;
    line_req<=~line_req;pending<=1;
    if(v==0) bank_valid[0]<=0;else bank_valid[!y[0]]<=0;
   end
   // A late read keeps the previous timing and latches a diagnostic; the
   // affected cell shows paper instead of a torn row.
   // h==HBLANK-1 is one clock before the active window, where active is low;
   // qualify by the row index instead so the fallback actually latches.
   if(h==HBLANK-1 && in_row) begin
    row_good<=buffer_good;row_ok<=buffer_good;
    if(show && !buffer_good) begin
     underrun<=1;
     if(rows_bad!=8'hff) rows_bad<=rows_bad+1'b1;
    end
   end
  end
 end
endmodule
