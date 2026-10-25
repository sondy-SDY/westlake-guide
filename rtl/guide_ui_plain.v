// Minimal 1024x600 background used while the card path is validated on the
// board: paper gradient plus the 640x480 card window. Same port list and the
// same five-stage latency as guide_ui, so guide_video can select either one.
//
// Diagnostic colours:
//   * card window shows the photo when the line fetch for that row succeeded;
//   * the row is painted vermilion when the fetch for that row was late or
//     missing (row_ok=0), so a "red band" means the SDRAM line path is the
//     problem, not the photo data;
//   * before the first frame is loaded the window shows the progress bar and,
//     if there is an error, the eight error cells (bit7 on the left, red = 1).
module guide_ui_plain(input pclk,input active,input [9:0] x,input [9:0] y,
 input [23:0] pix_in,input badge_px,input show,input row_ok,
 input [2:0] page,input auto_mode,input [3:0] load_index,input [7:0] error,
 output reg [23:0] rgb,output reg card);
 localparam [23:0] ZHU=24'hb5432f,LINE=24'hc4d2c8,CELLOFF=24'heae8df,DAI=24'h3e7a76;

 reg [9:0] xp,yp;reg showq,rowq;
 always @(posedge pclk) if(active) begin
  xp<=x;yp<=y;showq<=show;rowq<=row_ok;
 end
 // Same integer gradient as the decorative UI, so the two builds look alike
 // outside the card window.
 wire [31:0] gn={22'd0,yp}*32'd109;
 wire [7:0] gR=8'd246-((gn*12+32'd65535)>>16);
 wire [7:0] gG=8'd243-((gn*3+32'd65535)>>16);
 wire [23:0] bg={gR,gG,8'd234};
 wire in_win=xp>=10'd192 && xp<10'd832 && yp>=10'd76 && yp<10'd556;
 wire barfill=(xp-10'd240)<{2'd0,load_index}*10'd90;
 wire [23:0] bg1=(!showq&&in_win&&yp>=10'd300&&yp<10'd307&&xp>=10'd240&&xp<10'd784)
                  ?(barfill?DAI:LINE):bg;
 wire [23:0] bg2=(!showq&&in_win&&yp>=10'd380&&yp<10'd444&&xp>=10'd256&&xp<10'd768&&error!=0)
                  ?(error[7-((xp-10'd256)>>6)]?ZHU:CELLOFF):bg1;
 wire [23:0] bg3=(showq&&in_win&&!rowq)?ZHU:bg2;
 // Blank the card pixel outside the window so an uninitialised line buffer
 // cannot drive X into the packed pipeline register (simulation only).
 wire [23:0] pix_ok=in_win?pix_in:24'd0;
 reg [48:0] p1,p2,p3;
 always @(posedge pclk) begin
  p1<={showq&&in_win&&rowq,bg3,pix_ok};
  p2<=p1;
  p3<=p2;
 end
 always @(posedge pclk) begin
  card<=p3[48];
  rgb<=p3[48]?p3[23:0]:p3[47:24];   // card ? photo : background
 end
endmodule
