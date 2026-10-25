// FPGA-drawn 1024x600 guide UI. The 640x480 card is supplied by SDRAM and
// only occupies (192,76); everything else here is generated from coordinates
// and two small ROMs (mountain silhouette + 2bpp Chinese text masks), so the
// storage path carries exactly half of the pixels it used to.
//
// Five pipeline stages keep the 51 MHz pixel path short: the compare/flags and
// the colour mux tree sit in different cycles, and the /3 of the text blend is
// the only multiply left in the last one.
//   t+1  ROM word, mountain rows, card pixel
//   t+2  base/overlay colours and flags registered
//   t+3  background (overlays applied)
//   t+4  text blend sum
//   t+5  rgb + card window
module guide_ui(input pclk,input active,input [9:0] x,input [9:0] y,
 input [23:0] pix_in,input badge_px,input show,input row_ok,
 input [2:0] page,input auto_mode,input [3:0] load_index,input [7:0] error,
 output reg [23:0] rgb,output reg card);

 localparam [23:0] PAPER=24'hf6f3ea,PAPER2=24'heaf0ea,DAI=24'h3e7a76,ZHU=24'hb5432f,
  ZHU2=24'hd68c76,LINE=24'hc4d2c8,WHITE=24'hffffff,INK=24'h2b3836,GREY=24'h7a8a84,
  BODY=24'h465450,M0=24'hdee7e0,M1=24'hc9dad1,M2=24'hb0c9bf,AUTOC=24'h60a87c,
  PFUT=24'h96b0a6,CELLOFF=24'heae8df,CHIP=24'heaf0ea;

 // ---- stage 1: element selection and ROM read ---------------------------
 wire [4:0] eid;wire [7:0] lx;wire [5:0] ly;wire [13:0] ebase;
 guide_ui_sel sel(.x(x),.y(y),.page(page),.auto_mode(auto_mode),.id(eid),.lx(lx),.ly(ly));
 guide_ui_base base_rom(.id(eid),.base(ebase));
 wire [13:0] taddr=ebase+({8'd0,ly}<<4)+{8'd0,ly}+{9'd0,lx[7:3]};
 wire [7:0] m0,m1,m2;wire [15:0] tdata;
 guide_ui_rom rom(.clk(pclk),.mx(x),.m0(m0),.m1(m1),.m2(m2),.ta(taddr),.td(tdata));

 reg [9:0] xp,yp;reg [2:0] lxq;reg [4:0] idq;reg showq;
 always @(posedge pclk) if(active) begin
  xp<=x;yp<=y;lxq<=lx[2:0];idq<=eid;showq<=show;
 end

 // ---- stage 2 inputs -----------------------------------------------------
 function [23:0] stcol;input [2:0] k;input [2:0] cur;begin
  stcol=(cur!=0 && k==cur)?ZHU:((cur!=0 && k<cur)?ZHU2:DAI);
 end endfunction
 function [23:0] pfcol;input [2:0] k;input [2:0] cur;begin
  pfcol=(cur!=0 && k==cur)?ZHU:((cur!=0 && k<cur)?ZHU2:PFUT);
 end endfunction

 // Gradient: c = top + ((bot-top)*y*109)>>16, evaluated exactly.
 wire [31:0] gn={22'd0,yp}*32'd109;
 wire [7:0] gR=8'd246-((gn*12+32'd65535)>>16);
 wire [7:0] gG=8'd243-((gn*3+32'd65535)>>16);
 wire [7:0] gB=8'd234;
 wire [9:0] thr0=10'd600-{2'd0,m0},thr1=10'd600-{2'd0,m1},thr2=10'd600-{2'd0,m2};
 wire [23:0] basecol=(yp>=thr2)?M2:(yp>=thr1)?M1:(yp>=thr0)?M0:{gR,gG,gB};

 // static overlays (mutually exclusive, so a one-hot OR is a mux)
 wire h_l1=yp==10'd52 && xp>=10'd32 && xp<=10'd991;
 wire h_l2=yp==10'd55 && xp>=10'd32 && xp<=10'd991;
 wire h_seal=xp>=10'd32 && xp<=10'd61 && yp>=10'd12 && yp<=10'd41;
 wire h_mat=xp>=10'd184 && xp<=10'd839 && yp>=10'd68 && yp<=10'd563;
 wire h_bord=h_mat && (xp==10'd184||xp==10'd839||yp==10'd68||yp==10'd563);
 wire h_panel=h_mat && !h_bord;
 wire h_rail=xp>=10'd47 && xp<=10'd48 && yp>=10'd150 && yp<=10'd406;
 wire h_k0=xp>=10'd853 && xp<=10'd882 && yp>=10'd139 && yp<=10'd161;
 wire h_k1=xp>=10'd853 && xp<=10'd882 && yp>=10'd191 && yp<=10'd213;
 wire h_k2=xp>=10'd853 && xp<=10'd882 && yp>=10'd243 && yp<=10'd265;
 wire h_k3=xp>=10'd853 && xp<=10'd882 && yp>=10'd295 && yp<=10'd317;
 wire [9:0] dxa=(xp>=10'd874)?(xp-10'd874):(10'd874-xp);
 wire [9:0] dya=(yp>=10'd370)?(yp-10'd370):(10'd370-yp);
 wire h_auto=auto_mode && dxa<=10'd5 && dya<=10'd5 && dxa*dxa+dya*dya<=10'd25;
 wire [23:0] statcol=({24{h_l1}}&DAI)|({24{h_l2}}&LINE)|({24{h_seal}}&ZHU)|
  ({24{h_bord}}&LINE)|({24{h_panel}}&WHITE)|({24{h_rail}}&LINE)|
  ({24{h_k0}}&DAI)|({24{h_k1}}&DAI)|({24{h_k2}}&DAI)|({24{h_k3}}&DAI)|
  ({24{h_auto}}&AUTOC);
 wire stathit=h_l1|h_l2|h_seal|h_mat|h_rail|h_k0|h_k1|h_k2|h_k3|h_auto;

 // station dots: five nodes 64 px apart, so the nearest centre is derived
 // arithmetically instead of five parallel comparator blocks.
 wire dot_zone=xp>=10'd33 && xp<=10'd63 && yp>=10'd135 && yp<=10'd421;
 wire [9:0] drel=yp-10'd118;
 wire [9:0] cyq=10'd150+({7'd0,drel[8:6]}<<6);
 wire [3:0] node={1'd0,drel[8:6]}+4'd1;
 wire [4:0] dxl=(xp>=10'd48)?(xp-10'd48):(10'd48-xp);
 wire [5:0] dyl=(yp>=cyq)?(yp-cyq):(cyq-yp);
 wire [11:0] d2=dxl*dxl+dyl*dyl;
 wire dot_cur=(page==node[2:0]);
 wire dot_paint=dot_zone && (d2<=12'd121 || (dot_cur && d2<=12'd225));
 wire dot_ring=dot_paint && dot_cur && d2>12'd169;
 wire dot_in=dot_paint && dot_cur && d2<=12'd169 && d2>12'd121;
 wire dot_solid=dot_paint && d2<=12'd121;
 wire [23:0] doccol=({24{dot_ring}}&ZHU)|({24{dot_in}}&PAPER)|
  ({24{dot_solid}}&stcol(node[2:0],page));

 // bottom progress dots (five centres, 22 px apart)
 wire [9:0] dyp=(yp>=10'd584)?(yp-10'd584):(10'd584-yp);
 wire in_py=yp>=10'd580 && yp<=10'd588;
 wire [9:0] dx1=(xp>=10'd468)?(xp-10'd468):(10'd468-xp);
 wire [9:0] dx2=(xp>=10'd490)?(xp-10'd490):(10'd490-xp);
 wire [9:0] dx3=(xp>=10'd512)?(xp-10'd512):(10'd512-xp);
 wire [9:0] dx4=(xp>=10'd534)?(xp-10'd534):(10'd534-xp);
 wire [9:0] dx5=(xp>=10'd556)?(xp-10'd556):(10'd556-xp);
 wire pg1=in_py&&dx1<=10'd4&&dyp<=10'd4&&dx1*dx1+dyp*dyp<=10'd16;
 wire pg2=in_py&&dx2<=10'd4&&dyp<=10'd4&&dx2*dx2+dyp*dyp<=10'd16;
 wire pg3=in_py&&dx3<=10'd4&&dyp<=10'd4&&dx3*dx3+dyp*dyp<=10'd16;
 wire pg4=in_py&&dx4<=10'd4&&dyp<=10'd4&&dx4*dx4+dyp*dyp<=10'd16;
 wire pg5=in_py&&dx5<=10'd4&&dyp<=10'd4&&dx5*dx5+dyp*dyp<=10'd16;
 wire [23:0] pgcol=({24{pg1}}&pfcol(3'd1,page))|({24{pg2}}&pfcol(3'd2,page))|
  ({24{pg3}}&pfcol(3'd3,page))|({24{pg4}}&pfcol(3'd4,page))|({24{pg5}}&pfcol(3'd5,page));
 wire pgany=pg1|pg2|pg3|pg4|pg5;

 wire [1:0] al=(idq!=5'd31)?tdata[2*lxq +: 2]:2'd0;
 reg [23:0] ink_sel;
 always @* begin
  case(idq)
   5'd0:ink_sel=INK;5'd1:ink_sel=GREY;5'd2:ink_sel=DAI;5'd3:ink_sel=WHITE;5'd4:ink_sel=DAI;
   5'd5:ink_sel=stcol(3'd1,page);5'd6:ink_sel=WHITE;
   5'd7:ink_sel=stcol(3'd2,page);5'd8:ink_sel=WHITE;
   5'd9:ink_sel=stcol(3'd3,page);5'd10:ink_sel=WHITE;
   5'd11:ink_sel=stcol(3'd4,page);5'd12:ink_sel=WHITE;
   5'd13:ink_sel=stcol(3'd5,page);5'd14:ink_sel=WHITE;
   5'd15:ink_sel=DAI;
   5'd16:ink_sel=WHITE;5'd18:ink_sel=WHITE;5'd20:ink_sel=WHITE;5'd22:ink_sel=WHITE;
   5'd17:ink_sel=BODY;5'd19:ink_sel=BODY;5'd21:ink_sel=BODY;5'd23:ink_sel=BODY;
   5'd24:ink_sel=BODY;5'd25:ink_sel=BODY;5'd26:ink_sel=BODY;5'd27:ink_sel=BODY;
   5'd28:ink_sel=DAI;default:ink_sel=INK;
  endcase
 end
 wire in_win=xp>=10'd192 && xp<10'd832 && yp>=10'd76 && yp<10'd556;

 // ---- stage 2 register ---------------------------------------------------
 reg [23:0] base_r,stat_r,dot_r,pg_r,ink_r,ink_r2;
 reg hdot_r,hpg_r,hstat_r;reg [1:0] al_r,al_r2;reg [23:0] pix1,pix2,pix3;reg card1,card2,card3;
 reg [9:0] xp2,yp2;reg showq2;reg badge1;
 always @(posedge pclk) begin
  base_r<=basecol;stat_r<=statcol;dot_r<=doccol;pg_r<=pgcol;
  hdot_r<=dot_paint;hpg_r<=pgany;hstat_r<=stathit;
  al_r<=al;ink_r<=ink_sel;pix1<=pix_in;card1<=showq&&in_win&&row_ok;
  xp2<=xp;yp2<=yp;showq2<=showq;badge1<=badge_px;
 end

 // ---- stage 3: composite the background ---------------------------------
 wire [23:0] bg0=hdot_r?dot_r:(hpg_r?pg_r:(hstat_r?stat_r:base_r));
 wire badge_on=xp2>=10'd700 && xp2<10'd828 && yp2>=10'd14 && yp2<10'd38;
 wire [23:0] bg1=badge_on?(badge1?INK:CHIP):bg0;
 wire in_win2=xp2>=10'd192 && xp2<10'd832 && yp2>=10'd76 && yp2<10'd556;
 wire barfill=(xp2-10'd240)<{2'd0,load_index}*10'd90;
 wire [23:0] bg2=(!showq2&&in_win2&&yp2>=10'd300&&yp2<10'd307&&xp2>=10'd240&&xp2<10'd784)
                 ?(barfill?DAI:LINE):bg1;
 wire [23:0] bg3=(!showq2&&in_win2&&yp2>=10'd380&&yp2<10'd444&&xp2>=10'd256&&xp2<10'd768&&error!=0)
                 ?(error[7-((xp2-10'd256)>>6)]?ZHU:CELLOFF):bg2;
 reg [23:0] bg_r;
 always @(posedge pclk) begin
  bg_r<=bg3;al_r2<=al_r;ink_r2<=ink_r;pix2<=pix1;card2<=card1;
 end

 // ---- stage 4: text blend ------------------------------------------------
 wire [9:0] sh_r=({2'd0,bg_r[23:16]}*3'd3-{2'd0,bg_r[23:16]}*{2'd0,al_r2})+({2'd0,ink_r2[23:16]}*{2'd0,al_r2});
 wire [9:0] sh_g=({2'd0,bg_r[15:8]}*3'd3-{2'd0,bg_r[15:8]}*{2'd0,al_r2})+({2'd0,ink_r2[15:8]}*{2'd0,al_r2});
 wire [9:0] sh_b=({2'd0,bg_r[7:0]}*3'd3-{2'd0,bg_r[7:0]}*{2'd0,al_r2})+({2'd0,ink_r2[7:0]}*{2'd0,al_r2});
 reg [9:0] s_r,s_g,s_b;
 always @(posedge pclk) begin
  s_r<=sh_r;s_g<=sh_g;s_b<=sh_b;pix3<=pix2;card3<=card2;
 end

 // ---- stage 5: exact /3 (s*21846>>16 == floor(s/3) for s<=765) -----------
 // 32-bit product width is required: s<=765 and 765*21846 needs 25 bits.
 wire [31:0] pr=s_r*32'd21846,pg=s_g*32'd21846,pb=s_b*32'd21846;
 always @(posedge pclk) begin
  rgb<=card3?pix3:{pr[23:16],pg[23:16],pb[23:16]};
  card<=card3;
 end
endmodule
