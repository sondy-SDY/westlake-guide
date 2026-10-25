`timescale 1ns/1ps
module tb_video_640;
 reg mc=0,pc=0;always #12 mc=~mc;always #20 pc=~pc;reg rst=1;
 reg enabled=0;reg [3:0] page=0;reg [31:0] mem[0:921599];
 wire lr,la,lw;wire [9:0] ly;wire [2:0] lp;wire [8:0] lx;wire [31:0] ld;
 wire we,re,rv;wire [20:0] wa,ra;wire [31:0] wd,rd;wire idle,sready;
 reg source_valid=0;reg [20:0] source_addr=0;reg [31:0] source_data=0;
 reg [9:0] pipe=0;reg [31:0] dp[0:9];integer c=0,k,i,p,checked=0,frame=0,px=0,py=0,rows=0;
 wire refresh=c%1300<15;assign rv=pipe[9];assign rd=dp[9];
 wire [15:0] mem_words;
 guide_memory memory(mc,rst,1'b1,refresh,source_valid,sready,source_addr,source_data,enabled,idle,lr,ly,lp,la,lw,lx,ld,we,wa,wd,re,ra,rv,rd,mem_words,1'b0);
 wire valid,user,last,boundary,under;wire [23:0] rgb;wire [7:0] rows_bad;reg ready=0;integer vcycles=0;
 reg [7:0] fadew=8'd255;reg zoomm=0;integer sx,ssy;reg osdm=0,osden=0;
 reg audio_playing=0;
 // 时间轴注入：每 12000 个 sample_valid = 0.25 s，进到第 9 格（2.25 s）就该切到第 2 行
 reg injecting=0;reg [17:0] inj=0;
 wire sample_valid=injecting;
 always @(posedge pc) if(injecting) begin
  if(inj==18'd108000)injecting<=1'b0;else inj<=inj+1'b1;
 end
 guide_video_640 video(.pclk(pc),.prst(rst),.mclk(mc),.enabled(enabled),.page(page),
  .load_index(4'd6),.error(8'd0),.frame_boundary(boundary),.line_req(lr),.line_y(ly),.line_page(lp),
  .line_ack(la),.line_we(lw),.line_addr(lx),.line_data(ld),.valid(valid),.ready(ready),
  .user(user),.last(last),.rgb(rgb),.underrun(under),.rows_bad(rows_bad),.fade(fadew),.zoom(zoomm),
  .auto_mode(osdm),.paused(1'b0),.audio_playing(audio_playing),.audio_done(1'b0),.osd_en(osden),
  .sample_valid(sample_valid),.play_toggle(2'b00),.brightness(9'd256),.dev_row(3'd0),.dev_col(4'd0),.dev_sel(24'd0),.contrast(2'd1),.vu_on(1'b0),.sample(24'd0),.boot(1'b0),.boot_prog(4'd0));
 always @(posedge mc)begin
  c<=c+1;pipe<={pipe[8:0],re};if(re)dp[0]<=mem[ra];
  for(k=1;k<10;k=k+1)dp[k]<=dp[k-1];
  if(we)begin if(re || wa>=921600)$fatal(1,"memory bounds");mem[wa]<=wd;end
 end
 string filename;integer f;reg [15:0] pix;reg [31:0] pair;reg [23:0] want;reg [2:0] current;
 integer cycle=0,sof_cycle=-1,row_cycle=-1,row_pixels=0;reg prev_valid=0,started=0;
 integer cr,cg,cb;reg [7:0] wr,wg,wb;
 reg [3:0] disp_page=0;integer ink_px=0;
 reg [1:0] map0[0:10239];reg [1:0] map1[0:10239];reg [1:0] a2;integer er,eg,eb;
 reg use_map1=0;
 always @(negedge pc)begin vcycles=vcycles+1;ready=(vcycles%800<640 && vcycles%19!=0);end
 always @(posedge pc)if(!rst)begin
  cycle=cycle+1;
  if(user && !valid || last && !valid)$fatal(1,"marker outside valid");
  if(valid && !prev_valid)begin
   if(user)begin
    if(sof_cycle>=0 && (cycle-sof_cycle!=800*525 || rows!=480))$fatal(1,"frame cadence/rows %0d %0d",cycle-sof_cycle,rows);
    sof_cycle=cycle;rows=0;
   end else if(row_cycle>=0 && cycle-row_cycle!=800)$fatal(1,"row cadence");
   row_cycle=cycle;row_pixels=0;rows=rows+1;
  end
  if(valid)begin
   if(user!==(row_pixels==0 && rows==1) || last!==(row_pixels==639))$fatal(1,"timed marker mismatch rp=%0d rows=%0d user=%b last=%b",row_pixels,rows,user,last);
   row_pixels=row_pixels+1;
  end
  if(!valid && prev_valid && row_pixels!=640)$fatal(1,"wrong width");
  prev_valid=valid;

  if(valid && video.show)begin
   if(user)begin px=0;py=0;current=disp_page;started=1;end
   if(started && py<480)begin
    if(zoomm) begin sx=(px*3)>>2; ssy=(py*3)>>2; end else begin sx=px; ssy=py; end
    pair=mem[current*153600+ssy*320+sx/2];pix=sx[0]?pair[31:16]:pair[15:0];
    want={pix[15:11],pix[15:13],pix[10:5],pix[10:9],pix[4:0],pix[4:2]};
    if(fadew!=8'd255)begin
     cr=(want[23:16]-246)*fadew;cr=cr>>>8;
     cg=(want[15:8]-243)*fadew;cg=cg>>>8;
     cb=(want[7:0]-234)*fadew;cb=cb>>>8;
     wr=246+cr;wg=243+cg;wb=234+cb;want={wr,wg,wb};
    end
    if(osden && py>=450 && py<466) begin
      // 字幕带：和 gen_text.py 的 2bit 金标准逐像素核对（位置/字模/混合一起验）
      a2=use_map1?map1[(py-450)*640+px]:map0[(py-450)*640+px];
      er=(((want[23:16]*(3-a2))+8'h2b*a2)*21846)>>16;
      eg=(((want[15:8] *(3-a2))+8'h38*a2)*21846)>>16;
      eb=(((want[7:0]  *(3-a2))+8'h36*a2)*21846)>>16;
      if(rgb!=={er[7:0],eg[7:0],eb[7:0]})
       $fatal(1,"caption x=%0d y=%0d a=%0d got=%h want=%h",px,py,a2,rgb,{er[7:0],eg[7:0],eb[7:0]});
      if(a2!=0)ink_px=ink_px+1;
      checked=checked+1;
    end else begin
      if(rgb!==want)$fatal(1,"pixel page=%d x=%d y=%d got=%h want=%h",current,px,py,rgb,want);
      checked=checked+1;
    end
    if(px==639)begin px=0;py=py+1;if(py==480)begin
     $display("PASS frame %0d page %0d checked=%0d ink=%0d",frame,current,checked,ink_px);
     if(osden && ink_px<400)$fatal(1,"caption text missing ink=%0d",ink_px);
     ink_px=0;frame=frame+1;
     if(under)$fatal(1,"unexpected underrun");
     if(frame==5)fadew<=8'd128;
     if(frame==6)begin fadew<=8'd255;zoomm<=1'b1;end
     if(frame==7)begin zoomm<=1'b0;osden<=1'b1;end
     if(frame==8)begin use_map1<=1'b1;audio_playing<=1'b1;injecting<=1'b1;end
     if(frame==9)$finish;
    end end else px=px+1;
   end
  end
 end
 reg [2:0] fb_pipe=0;
 always @(posedge pc)begin
  fb_pipe<={fb_pipe[1:0],boundary};
  if(fb_pipe[2] && page!=4'd5)page<=page+1'b1;
  if(video.v==0 && video.h==2)disp_page<=page;
 end
 initial begin
  for(p=0;p<6;p=p+1)begin
   filename=$sformatf("build/test/PIC%02d.hex",p);$readmemh(filename,mem,p*153600,(p+1)*153600-1);
  end
  $readmemh("build/test/cap_alpha0.hex",map0);
  $readmemh("build/test/cap_alpha1.hex",map1);
  #200;@(negedge mc)rst=0;
  for(i=0;i<1024;i=i+1)begin source_addr=200000+i;source_data=mem[source_addr];source_valid=1;
   @(posedge mc);while(!sready)@(posedge mc);@(negedge mc);end
  source_valid=0;wait(idle);@(negedge mc)enabled=1;
 end
 initial begin #400000000;$fatal(1,"video timeout");end
endmodule
