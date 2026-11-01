// Assert reset even if a generated clock stops. Release only after both PLLs
// stay locked for 20 ms of the independent 50 MHz reference clock.
module guide_clock_guard #(parameter HOLD_CYCLES=1000000)(
 input clk,input reset_n,input video_locked,input memory_locked,
 output reg run);
 localparam COUNT_BITS=(HOLD_CYCLES<2)?1:$clog2(HOLD_CYCLES);
 wire clocks_ok=reset_n && video_locked && memory_locked;
 reg [1:0] lock_sync;
 reg [COUNT_BITS-1:0] count;
 always @(posedge clk or negedge clocks_ok) begin
  if(!clocks_ok) begin lock_sync<=0;count<=0;run<=0;end
  else begin
   lock_sync<={lock_sync[0],1'b1};
   if(!lock_sync[1]) begin count<=0;run<=0;end
   else if(!run) begin
    if(count==HOLD_CYCLES-1) run<=1;
    else count<=count+1'b1;
   end
  end
 end
endmodule
