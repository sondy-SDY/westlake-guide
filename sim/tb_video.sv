`timescale 1ns/1ps
module tb_video;
 reg mc=0,pc=0;always #12 mc=~mc;always #9.8039 pc=~pc;reg rst=1;
 reg enabled=0;reg [2:0] page=0;reg [31:0] mem[0:921599];reg [2:0] fb_pipe=0;
 wire lr,la,lw;wire [9:0] ly;wire [2:0] lp;wire [8:0] lx;wire [31:0] ld;
 wire we,re,rv;wire [20:0] wa,ra;wire [31:0] wd,rd;wire idle,sready;
 reg source_valid=0;reg [20:0] source_addr=0;reg [31:0] source_data=0;
 reg [9:0] pipe=0;reg [31:0] dp[0:9];integer c=0,k,i,j,p,checked=0,frame=0,px=0,py=0,rows=0;integer gs,gr,gg;
 wire refresh=c%1300<15;assign rv=pipe[9];assign rd=dp[9];
 wire [15:0] mem_words;
 guide_memory memory(mc,rst,1'b1,refresh,source_valid,sready,source_addr,source_data,enabled,idle,lr,ly,lp,la,lw,lx,ld,we,wa,wd,re,ra,rv,rd,mem_words,1'b0);
 wire valid,user,last,boundary,under;wire [23:0] rgb;reg ready=0;integer vcycles=0;
 wire [7:0] rows_bad;
 guide_video video(pc,rst,mc,enabled,page,4'd6,8'd0,1'b0,1'b0,1'b0,1'b0,7'd10,1'b1,boundary,lr,ly,lp,la,lw,lx,ld,valid,ready,user,last,rgb,under,rows_bad);
 always @(posedge mc)begin
  c<=c+1;pipe<={pipe[8:0],re};if(re)dp[0]<=mem[ra];
  for(k=1;k<10;k=k+1)dp[k]<=dp[k-1];
  if(we)begin if(re || wa>=921600)$fatal(1,"memory bounds");mem[wa]<=wd;end
 end
 string filename;integer f;reg [15:0] pix;reg [31:0] pair;reg [23:0] want;reg [2:0] current;
 integer cycle=0,sof_cycle=-1,row_cycle=-1,row_pixels=0;reg prev_valid=0,started=0;
 always @(negedge pc)begin vcycles=vcycles+1;ready=(vcycles%1344<1024 && vcycles%19!=0);end
 // Page is latched by the DUT at (v==0,h==2); advance it a few cycles later so
 // every frame shows exactly the page the checker expects.
 // Page is latched by the DUT at (v==0,h==2); advance it a few cycles later so
 // every frame shows exactly the page the checker expects.
 reg [2:0] disp_page=0;
 always @(posedge pc)begin
  fb_pipe<={fb_pipe[1:0],boundary};
  if(fb_pipe[2] && page!=3'd5)page<=page+1'b1;
  if(video.v==0 && video.h==2)disp_page<=page;
 end
 always @(posedge pc)if(!rst)begin
  cycle=cycle+1;
  if(user && !valid || last && !valid)$fatal(1,"marker outside valid");
  if(valid && !prev_valid)begin
   if(user)begin
    if(sof_cycle>=0 && (cycle-sof_cycle!=1344*635 || rows!=600))$fatal(1,"frame cadence/rows");
    sof_cycle=cycle;rows=0;
   end else if(row_cycle>=0 && cycle-row_cycle!=1344)$fatal(1,"row cadence");
   row_cycle=cycle;row_pixels=0;rows=rows+1;
  end
  if(valid)begin
   if(user!==(row_pixels==0 && rows==1) || last!==(row_pixels==1023))$fatal(1,"timed marker mismatch");
   row_pixels=row_pixels+1;
  end
  if(!valid && prev_valid && row_pixels!=1024)$fatal(1,"nonconsecutive row or wrong width");
  prev_valid=valid;
  if(valid && video.show)begin
   if(user)begin px=0;py=0;current=disp_page;started=1;end
   // The pipeline still holds the previous frame's last pixels for a few
   // cycles after the frame boundary; started/py==600 mark "not this frame".
   if(started && py<600)begin
   if(user!==(px==0 && py==0) || last!==(px==1023))$fatal(1,"AXIS marker mismatch px=%0d py=%0d user=%b last=%b cycle=%0d",px,py,user,last,cycle);
   if(checked<4) $display("dbg px=%0d py=%0d rgb=%h ui=%h card=%b show=%b rowok=%b inwin=%b",
     px,py,rgb,video.ui_rgb,video.ui_card,video.show,video.row_ok,(video.x>=192&&video.x<832&&video.y>=76&&video.y<556));
   if(px>=192 && px<832 && py>=76 && py<556)begin
    pair=mem[current*153600+(py-76)*320+(px-192)/2];pix=px[0]?pair[31:16]:pair[15:0];
    want={pix[15:11],pix[15:13],pix[10:5],pix[10:9],pix[4:0],pix[4:2]};
    if(rgb!==want)$fatal(1,"card pixel page=%d x=%d y=%d got=%h want=%h",current,px,py,rgb,want);
    checked=checked+1;
   end else begin
    // plain background: every non-card pixel must be exactly the paper gradient
    gs=py*109;
    gr=246-((gs*12+65535)>>16);gg=243-((gs*3+65535)>>16);
    want={gr[7:0],gg[7:0],8'd234};
    if(rgb!==want)$fatal(1,"background page=%d x=%d y=%d got=%h want=%h",current,px,py,rgb,want);
    checked=checked+1;
   end
   if(px==1023)begin px=0;py=py+1;if(py==600)begin
    $display("PASS frame %0d page %0d checked=%0d",frame,current,checked);frame=frame+1;
    if(under)$fatal(1,"unexpected underrun");
    if(frame==6)$finish;
   end end else px=px+1;
   end
  end
 end
 initial begin
  for(p=0;p<6;p=p+1)begin
   filename=$sformatf("build/test/PIC%02d.hex",p);$readmemh(filename,mem,p*153600,(p+1)*153600-1);
  end
  #200;@(negedge mc)rst=0;
  for(i=0;i<1024;i=i+1)begin source_addr=200000+i;source_data=mem[source_addr];source_valid=1;
   @(posedge mc);while(!sready)@(posedge mc);@(negedge mc);end
  source_valid=0;wait(idle);@(negedge mc)enabled=1;
 end
 initial begin #600000000;$fatal(1,"video timeout");end
endmodule
