// One font port serves the 640 glass panels, tips and linked route labels.
// NATIVE_PANEL retains the earlier 1024 sidebar layout for compatibility.
module guide_widgets #(parameter NATIVE_PANEL=0)(input clk,input [9:0] x,y,ax,ay,
 input center,input [3:0] page,input reverse,input [2:0] station,input [8:0] scroll,
 input [2:0] tip_index,input [3:0] tip_alpha,
 output reg on,output [23:0] color,output [3:0] opacity,
 output [23:0] base_color,output [3:0] base_opacity);
 reg [5:0] label;reg [9:0] tx,ty;reg region;reg [23:0] ink,bg;reg paper;
 reg [3:0] ink_alpha,bg_alpha;reg [5:0] list_label;
 wire [3:0] next_page=(page==0)?4'd1:(reverse?((page==1)?4'd5:page-1'b1):((page==5)?4'd1:page+1'b1));
 wire [9:0] scroll_y=ay+{1'b0,scroll};
 reg [2:0] step;
 always @*begin
  label=0;tx=0;ty=0;region=0;ink=24'hc9ded3;bg=24'h213c36;paper=0;step=0;
  ink_alpha=8;bg_alpha=8;list_label=0;
  if(!NATIVE_PANEL&&page>=1&&page<=5&&y<360)begin
   // True 5/8 translucent paper over the photograph; no empty sidebar pixels
   // are fetched and no additional frame/line RAM is used for these panels.
   bg=24'hf6f3e9;bg_alpha=5;ink=24'h29483e;
   if(x<104)begin
    paper=1;tx=x-14;
    if(y>=22&&y<38)begin label=7;ty=y-22;region=1;end
    if(y>=64&&y<80)begin label=reverse?9:8;ty=y-64;region=1;end
    if(y>=101&&y<117)begin label=10;ty=y-101;region=1;ink=24'h667b6d;end
    if(y>=127&&y<143)begin label={2'd0,page};ty=y-127;region=1;end
    if(y>=159&&y<175)begin label=11;ty=y-159;region=1;ink=24'h667b6d;end
    if(y>=186&&y<202)begin step=0;ty=y-186;region=1;end
    if(y>=212&&y<228)begin step=1;ty=y-212;region=1;end
    if(y>=238&&y<254)begin step=2;ty=y-238;region=1;end
    if(y>=264&&y<280)begin step=3;ty=y-264;region=1;end
    if(y>=290&&y<306)begin step=4;ty=y-290;region=1;end
    if(region&&y>=186&&y<306)begin
     list_label=(!reverse||step==0)?{3'd0,step}+1'b1:6'd6-{3'd0,step};
     label=list_label;
     if(list_label==page)begin
      ink=24'hfff9e9;
      if(x>=8&&x<98)begin bg=24'h397f70;bg_alpha=7;end
      if(x>=8&&x<11)begin bg=24'hb5432f;bg_alpha=8;end
     end
    end
    if(y>=321&&y<337)begin label=28;ty=y-321;region=1;end
    if(y>=340&&y<356)begin label=29;ty=y-340;region=1;end
    region=region&&x>=14&&x<94;
    if((y==47&&x>=14&&x<90)||x==103)begin bg=24'hb59453;bg_alpha=6;end
   end else if(x>=512)begin
    paper=1;tx=x-520;
    if(y>=22&&y<38)begin label=19;ty=y-22;region=1;end
    if(y>=70&&y<86)begin label=6'd40+{tip_index,2'b00};ty=y-70;region=1;ink_alpha=tip_alpha;end
    if(y>=98&&y<114)begin label=6'd41+{tip_index,2'b00};ty=y-98;region=1;ink_alpha=tip_alpha;end
    if(y>=126&&y<142)begin label=6'd42+{tip_index,2'b00};ty=y-126;region=1;ink_alpha=tip_alpha;end
    if(y>=154&&y<170)begin label=6'd43+{tip_index,2'b00};ty=y-154;region=1;ink_alpha=tip_alpha;end
    if(y>=244&&y<260)begin label=6;ty=y-244;region=1;ink=24'h667b6d;end
    if(y>=270&&y<286)begin label={2'd0,next_page};ty=y-270;region=1;end
    if(y>=316&&y<332)begin label=32;ty=y-316;region=1;end
    if(y>=337&&y<353)begin label=33;ty=y-337;region=1;end
    region=region&&x>=520&&x<632;
    if(((y==47||y==220)&&x>=520&&x<624)||x==512)begin bg=24'hb59453;bg_alpha=6;end
    if(y>=196&&y<=199&&x>=532&&x<604)begin
     case(x)
      532,533,534,535:begin bg=tip_index==0?24'h397f70:24'h9daa99;bg_alpha=8;end
      545,546,547,548:begin bg=tip_index==1?24'h397f70:24'h9daa99;bg_alpha=8;end
      558,559,560,561:begin bg=tip_index==2?24'h397f70:24'h9daa99;bg_alpha=8;end
      571,572,573,574:begin bg=tip_index==3?24'h397f70:24'h9daa99;bg_alpha=8;end
      584,585,586,587:begin bg=tip_index==4?24'h397f70:24'h9daa99;bg_alpha=8;end
      597,598,599,600:begin bg=tip_index==5?24'h397f70:24'h9daa99;bg_alpha=8;end
     endcase
    end
   end
  end else if(NATIVE_PANEL&&!center)begin
   paper=1;
   if(ax<112)begin
    tx=ax-16;
    if(ay>=30&&ay<46)begin ty=ay-30;label=7;region=1;ink=24'hecddba;end
    if(ay>=76&&ay<92)begin ty=ay-76;label=reverse?9:8;region=1;end
    if(ay>=126&&ay<142)begin ty=ay-126;label=10;region=1;end
    if(ay>=152&&ay<168)begin
     ty=ay-152;label={3'd0,station}+1'b1;region=1;ink=24'hffffff;
     case(page)0:label=13;6:label=14;7,8,9:label=16;10:label=17;11:label=18;endcase
    end
    if(ay>=211&&ay<227)begin ty=ay-211;label=11;region=1;end
    if(ay>=245&&ay<261)begin ty=ay-245;step=0;region=1;end
    if(ay>=285&&ay<301)begin ty=ay-285;step=1;region=1;end
    if(ay>=325&&ay<341)begin ty=ay-325;step=2;region=1;end
    if(ay>=365&&ay<381)begin ty=ay-365;step=3;region=1;end
    if(ay>=405&&ay<421)begin ty=ay-405;step=4;region=1;end
    if(region&&ay>=245&&ay<421)begin
     label=(!reverse||step==0)?{3'd0,step}+1'b1:6'd6-{3'd0,step};
     if(label==station+1'b1)ink=24'hecddba;
    end
    if(ay>=490&&ay<506)begin ty=ay-490;label=28;region=1;end
    if(ay>=516&&ay<532)begin ty=ay-516;label=29;region=1;end
    region=region&&ax>=16&&ax<96;
   end else begin
    tx=ax-928;
    if(ay>=30&&ay<46)begin ty=ay-30;label=12;region=1;ink=24'hecddba;end
    if(ay>=112&&ay<552)begin
     ty={5'd0,scroll_y[4:0]};region=scroll_y[4:0]<16;
     case(scroll_y[8:5])
      0:label=19;1:label=20;2:label=21;3:label=22;
      4:label=23;5:label=24;6:label=25;7:label=26;
      8:label=27;9:label=30;10:label=31;11:label=32;
      12:label=33;13:label=34;14:label=35;default:label=37;
     endcase
    end
    region=region&&ax>=928&&ax<1008;
   end
  end else if(NATIVE_PANEL&&center&&page>=1&&page<=5&&x>=530&&x<626)begin
   tx=x-530;ink=24'hffffff;bg=24'h29443d;
   if(y>=309&&y<325)begin ty=y-309;label=6;region=1;end
   if(y>=334&&y<350)begin ty=y-334;label={2'd0,next_page};region=1;end
  end
 end
 wire pixel;
 guide_label_rom font(.clk(clk),.label_id(label),.letter(tx[6:4]),.x(tx[3:0]),.y(ty[3:0]),.pixel(pixel));
 reg region_q,paper_q;reg [23:0] ink_q,bg_q;reg [3:0] ink_alpha_q,bg_alpha_q;
 always @(posedge clk)begin
  region_q<=region;paper_q<=paper;ink_q<=ink;bg_q<=bg;on<=paper||region;
  ink_alpha_q<=ink_alpha;bg_alpha_q<=bg_alpha;
 end
 assign color=ink_q;
 assign opacity=(region_q&&pixel)?ink_alpha_q:4'd0;
 assign base_color=bg_q;
 assign base_opacity=bg_alpha_q;
endmodule

// Advance only at a frame boundary. Hidden/zoomed pages preserve the current
// message, and each message changes while its text is fully transparent.
module guide_tip_cycle #(parameter HOLD_FRAMES=360)(input clk,input rst,
 input frame_boundary,input enabled,output reg [2:0] index,output [3:0] alpha);
 localparam PERIOD=HOLD_FRAMES+32;
 reg [$clog2(PERIOD)-1:0] frame_count;
 wire [$clog2(PERIOD)-1:0] remaining=PERIOD-1-frame_count;
 assign alpha=(frame_count<16)?(frame_count>>1):
              (frame_count>=HOLD_FRAMES+16)?(remaining>>1):4'd8;
 always @(posedge clk or posedge rst)begin
  if(rst)begin index<=0;frame_count<=0;end
  else if(frame_boundary&&enabled)begin
   if(frame_count==PERIOD-1)begin frame_count<=0;index<=(index==5)?0:index+1'b1;end
   else frame_count<=frame_count+1'b1;
  end
 end
endmodule
