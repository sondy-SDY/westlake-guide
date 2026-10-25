// Minimal 8N1 UART transmitter. One bit time is DIV clocks of `clk`.
// Default DIV 434 = 50 MHz / 115200 (0.007% fast), so the status stream is
// readable on any serial assistant without extra hardware.
module guide_uart #(parameter DIV=434)(
  input clk,input rst,input [7:0] data,input send,output reg busy,output reg tx);
  reg [15:0] cnt;reg [3:0] n;reg [9:0] sh;
  always @(posedge clk or posedge rst) begin
   if(rst) begin busy<=0;tx<=1;cnt<=0;n<=0;sh<=10'h3ff;end
   else if(!busy) begin
    tx<=1;
    if(send) begin sh<={1'b1,data,1'b0};busy<=1;n<=0;cnt<=0;end
   end else if(cnt==DIV-1) begin
    cnt<=0;tx<=sh[0];sh<={1'b1,sh[9:1]};
    if(n==9) busy<=0;else n<=n+1'b1;
   end else cnt<=cnt+1'b1;
  end
endmodule
