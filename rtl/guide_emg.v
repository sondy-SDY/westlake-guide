// 紧急播报：K4 长按进入/退出，紧急态下短按重播本条。
// 只管"现在是紧急态吗、该放第几页"，页复用和音频复用由顶层做。
module guide_emg(input pclk,input prst,input enable,input hold,input tap,
 output reg emg,output reg [3:0] emg_page,output reg tick);
 always @(posedge pclk or posedge prst) begin
  if(prst) begin emg<=0;emg_page<=4'd6;tick<=0;end
  else begin
   if(hold && enable) begin
    emg<=~emg;
    tick<=~tick;            // 进/出都让音频重新打开
   end else if(tap && emg) begin
    tick<=~tick;            // 紧急态短按：本条播报从头再来
   end
  end
 end
endmodule
