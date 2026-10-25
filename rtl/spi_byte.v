// SPI mode 0, one byte per request. div_half is cycles per half SCK.
module spi_byte(input clk,input rst,input start,input [7:0] tx,
 input [7:0] div_half,input miso,output reg sck,output reg mosi,
 output reg busy,output reg done,output reg [7:0] rx);
 reg [7:0] timer,shift; reg [2:0] bitno;
 always @(posedge clk or posedge rst) begin
  if(rst) begin sck<=0;mosi<=1;busy<=0;done<=0;rx<=0;timer<=0;shift<=0;bitno<=7;end
  else begin
   done<=0;
   if(!busy) begin
    sck<=0;
    if(start) begin busy<=1;timer<=div_half-1'b1;shift<=tx;mosi<=tx[7];bitno<=7;end
   end else if(timer!=0) timer<=timer-1'b1;
   else begin
    timer<=div_half-1'b1; sck<=~sck;
    if(!sck) rx<={rx[6:0],miso};
    else if(bitno==0) begin busy<=0;done<=1;mosi<=1;end
    else begin bitno<=bitno-1'b1;shift<={shift[6:0],1'b1};mosi<=shift[6];end
   end
  end
 end
endmodule
