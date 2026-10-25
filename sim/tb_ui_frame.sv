// Full-frame check: drives guide_video with a synthetic SDRAM line source
// loaded from the 640x480 card, dumps active pixels, and lets Python compare
// the result with westlake_guide_v3/preview/*_screen.png.
module tb_ui_frame;
 reg pclk=0,prst=1;
 wire line_req;wire [9:0] line_y;wire [2:0] line_page;
 reg line_ack=0,line_we=0;reg [8:0] line_addr=0;reg [31:0] line_data=0;
 wire valid,user,last,underrun,frame_boundary;wire [7:0] rows_bad;wire [23:0] rgb;
 reg [1023:0] hexpath,outpath;integer out_fd,page_i,auto_i,cnt_dbg;
 reg [31:0] rowmem[0:153599];
 reg [2:0] page_r;
 reg cap=0;integer n=0;
 initial begin
  if(!$value$plusargs("PAGE=%d",page_i)) page_i=1;
  if(!$value$plusargs("AUTO=%d",auto_i)) auto_i=1;
  if(!$value$plusargs("HEX=%s",hexpath)) hexpath="card.hex";
  if(!$value$plusargs("OUT=%s",outpath)) outpath="frame.txt";
  page_r=page_i[2:0];
  $readmemh(hexpath,rowmem);
  out_fd=$fopen(outpath,"w");
 end
 always #10 pclk=~pclk;
 guide_video #(.draw_ui(1)) dut(.pclk(pclk),.prst(prst),.mclk(pclk),.enabled(1'b1),.page(page_r),
  .load_index(4'd6),.error(8'd0),.auto_mode(auto_i[0]),.paused(1'b0),.audio_done(1'b0),
  .audio_error(1'b0),.period(7'd20),.audio_playing(1'b0),
  .frame_boundary(frame_boundary),.line_req(line_req),.line_y(line_y),.line_page(line_page),
  .line_ack(line_ack),.line_we(line_we),.line_addr(line_addr),.line_data(line_data),
  .valid(valid),.ready(1'b1),.user(user),.last(last),.rgb(rgb),.underrun(underrun),
  .rows_bad(rows_bad));
 // SDRAM page model: answer every line request with 320 words.
 reg req_d=0;reg [1:0] st=0;reg [8:0] cnt=0;
 always @(posedge pclk) begin
  line_we<=0;
  case(st)
   0: if(line_req!=req_d) begin req_d<=line_req;cnt<=0;st<=1;end
   1: begin
       line_we<=1;line_addr<=cnt;
       line_data<=rowmem[{22'd0,line_y}*320+cnt];
       if(cnt==9'd319) st<=2;else cnt<=cnt+1'b1;
      end
   2: begin line_ack<=req_d;st<=3;end
   default: st<=0;
  endcase
 end
 // Capture starts exactly at the SOF pixel so the dump is pixel-aligned.
 integer frames=0;
 always @(posedge pclk) begin
  if(user) frames<=frames+1;
  if(user && frames>=2) begin
   $fwrite(out_fd,"%02x%02x%02x\n",rgb[23:16],rgb[15:8],rgb[7:0]);
   if(n<6) $display("dbg n=%0d x=%0d y=%0d rgb=%06x show=%b card=%b ly=%0d nb=%b",
     n,dut.x,dut.y,rgb,dut.show,dut.ui_card,dut.line_y,dut.bank_valid);
   cap<=1;n<=1;
  end else if(valid && cap) begin
   $fwrite(out_fd,"%02x%02x%02x\n",rgb[23:16],rgb[15:8],rgb[7:0]);
   if(n<6) $display("dbg n=%0d x=%0d y=%0d rgb=%06x",n,dut.x,dut.y,rgb);
   n<=n+1;if(n==614399) cap<=0;
  end
 end
 initial begin
  repeat(32) @(posedge pclk);
  prst<=0;
  wait(n==614400);
  repeat(16) @(posedge pclk);
  $fclose(out_fd);
  $display("DONE underrun=%0d rows_bad=%0d n=%0d",underrun,rows_bad,n);
  $finish;
 end
endmodule
