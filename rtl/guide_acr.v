// APUG092 example audio_arc_calculate: one ACR update per N/128 samples.
// PCM and pixel clock share the 51 MHz PLL, so CTS=51000 and N=6144 are
// exact constants at 48 kHz. Only the update strobe needs division by 48.
module guide_acr(input clk,input rst,input sample_valid,output reg valid);
 reg [5:0] count;
 always @(posedge clk or posedge rst) begin
  if(rst) begin count<=0;valid<=0;end
  else begin
   valid<=0;
   if(sample_valid) begin
    if(count==47) begin count<=0;valid<=1;end
    else count<=count+1'b1;
   end
  end
 end
endmodule
