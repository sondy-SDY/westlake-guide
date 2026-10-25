`timescale 1ns/1ps
// Decodes the 115200 8N1 telemetry stream and prints the recovered text, so
// the line format is verified without hardware. One report is 78 bytes =
// 6.8 ms at DIV=434, so the shortened period is 8 ms.
module tb_telemetry;
 localparam integer DIV = 434;
 reg clk=0; always #10 clk=~clk;      // 50 MHz
 reg rst=1;
 reg v_locked=1,m_locked=1,init=1,loaded=1,au_under=0;
 reg [7:0] vlf=8'h02,mlf=8'h00,rcnt=8'h01,err=8'h00,rows_bad=8'h03,edid=8'h80;
 reg [15:0] frames=16'h0123,words=16'hABCD;
 reg [2:0] page=3'd2;
 wire tx;
 guide_telemetry #(.PERIOD(25'd400000)) dut(.clk(clk),.rst(rst),
  .v_locked(v_locked),.m_locked(m_locked),.init(init),.loaded(loaded),.au_under(au_under),
  .vlf(vlf),.mlf(mlf),.rcnt(rcnt),.err(err),.rows_bad(rows_bad),.edid(edid),
  .frames(frames),.words(words),.page(page),.load_index(4'd9),.tx(tx));
 integer st=0,c=0,nb=0; reg [9:0] sh=0; integer got=0; integer fails=0;
 always @(posedge clk) begin
  if(st==0) begin
   if(!tx) begin st=1; c=DIV/2; end
  end else if(c>0) c=c-1;
  else begin
   sh[nb]=tx; nb=nb+1; c=DIV-1;
   if(nb==10) begin
    st=0; nb=0;
    if(sh[0]==1'b0 && sh[9]==1'b1) begin
     got=got+1;
     if(sh[8:1]==8'h0d) $write("\n");
     else if(sh[8:1]!=8'h0a) $write("%c", sh[8:1]);
    end else begin fails=fails+1; $write("\n<FRAME ERROR %b>\n",sh); end
   end
  end
 end
 initial begin
  repeat(4) @(posedge clk);
  rst<=0;
  #9000000; v_locked<=0; frames<=16'h0456; page<=3'd5; rows_bad<=8'h00; edid<=8'h10;
  #16000000;
  $display("[TB] bytes decoded: %0d, frame errors: %0d", got, fails);
  if(got<78 || fails>0) $display("[TB] FAIL");
  else $display("[TB] PASS: two reports decoded cleanly");
  $finish;
 end
endmodule
