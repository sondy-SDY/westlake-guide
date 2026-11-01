// Compact transport timeline in the existing caption margin. All geometry is
// evaluated before the video's overlay register; there is no extra frame RAM.
module guide_playback_bar(input [9:0] x,y,input enabled,input paused,
 input [9:0] progress,input [15:0] elapsed_bcd,total_bcd,
 output reg on,output reg [23:0] color);
 localparam [23:0] TEAL=24'h2d7773,PALE=24'hd7e3de,GOLD=24'hb59453,INK=24'h74827d;
 wire [12:0] scaled=({3'd0,progress}<<2)+{3'd0,progress};
 wire [9:0] cursor=10'd44+((progress>=512)?10'd320:scaled[12:3]);
 wire [9:0] dx=(x>cursor)?x-cursor:cursor-x;
 wire [9:0] dy=(y>440)?y-10'd440:10'd440-y;
 wire outer=(dy<=1&&dx<=4)||(dy==2&&dx<=3)||(dy==3&&dx<=2)||(dy==4&&dx<=1);
 wire inner=(dy==0&&dx<=3)||(dy<=2&&dx<=2)||(dy==3&&dx==0);
 wire track=x>=44&&x<=364&&dy<=1&&((x!=44&&x!=364)||dy==0);
 wire play_icon=x>=24&&x<=34&&dy<=5&&((x-24)+(dy<<1)<=10);
 wire pause_icon=((x>=24&&x<=26)||(x>=31&&x<=33))&&dy<=5;
 wire [9:0] tx=x-10'd372,ty=y-10'd435;
 reg [3:0] glyph;
 always @*begin
  case(tx[6:3])
   0:glyph=elapsed_bcd[15:12];1:glyph=elapsed_bcd[11:8];2:glyph=10;
   3:glyph=elapsed_bcd[7:4];4:glyph=elapsed_bcd[3:0];5:glyph=15;
   6:glyph=11;7:glyph=15;8:glyph=total_bcd[15:12];9:glyph=total_bcd[11:8];
   10:glyph=10;11:glyph=total_bcd[7:4];12:glyph=total_bcd[3:0];default:glyph=15;
  endcase
 end
 wire digit;
 guide_timeline_font font(.glyph(glyph),.x(tx[2:0]),.y(ty[3:0]),.pixel(digit));
 always @*begin
  on=0;color=TEAL;
  if(enabled&&y>=435&&y<=445)begin
   if(paused?pause_icon:play_icon)begin on=1;color=TEAL;end
   if(track)begin on=1;color=(x<=cursor)?TEAL:PALE;end
   if(outer)begin on=1;color=inner?GOLD:24'hfffcf7;end
   if(x>=372&&x<476&&digit)begin on=1;color=INK;end
  end
 end
endmodule
