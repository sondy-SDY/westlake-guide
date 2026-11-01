// Six-node demonstration graph: five scenic stops and one marked demo exit.
// Edges 0..3 join the tour, edge 4 joins stop 5 to the exit, edge 5 is the shortcut.
// Sequential Dijkstra shares one comparator/adder and uses no frame buffer.
module guide_route_plan(input clk,input rst,input [2:0] start_node,input closed,
 output reg valid,output reg [5:0] route_edges,output reg [7:0] distance,
 output reg [2:0] result_start,output reg result_closed);
 localparam INIT=0,SCAN=1,RELAX=2,TRACE=3,READY=4;
 reg [2:0] state,source,scan,best,node,trace_node,trace_steps;
 reg block_shortcut;reg [5:0] visited,trace_mask;
 reg [7:0] distance_to[0:5],best_cost;reg [2:0] previous[0:5];
 integer k;
 function [2:0] edge_id;input [2:0] a,b;begin
  case({a,b})
   6'o01,6'o10:edge_id=0;6'o12,6'o21:edge_id=1;
   6'o23,6'o32:edge_id=2;6'o34,6'o43:edge_id=3;
   6'o45,6'o54:edge_id=4;6'o05,6'o50:edge_id=5;
   default:edge_id=7;
  endcase
 end endfunction
 function [7:0] weight;input [2:0] a,b;input blocked;begin
  case(edge_id(a,b))
   0:weight=8'd2;1:weight=8'd3;2:weight=8'd4;
   3:weight=8'd3;4:weight=8'd3;5:weight=blocked?8'hff:8'd2;
   default:weight=8'hff;
  endcase
 end endfunction
 wire [7:0] cost=weight(node,scan,block_shortcut);
 wire [8:0] candidate={1'b0,distance_to[node]}+{1'b0,cost};
 wire [2:0] trace_edge=edge_id(trace_node,previous[trace_node]);
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   state<=INIT;source<=0;block_shortcut<=0;valid<=0;route_edges<=0;distance<=0;
   result_start<=0;result_closed<=0;visited<=0;scan<=0;best<=0;best_cost<=255;node<=0;
   trace_node<=5;trace_steps<=0;trace_mask<=0;
   for(k=0;k<6;k=k+1)begin distance_to[k]<=255;previous[k]<=7;end
  end else if(state!=INIT && ((start_node<5?start_node:3'd0)!=source||closed!=block_shortcut)) begin
   state<=INIT;valid<=0;
  end else case(state)
   INIT:begin
    source<=(start_node<5)?start_node:3'd0;block_shortcut<=closed;
    valid<=0;visited<=0;scan<=0;best<=0;best_cost<=255;trace_mask<=0;trace_steps<=0;
    for(k=0;k<6;k=k+1)begin distance_to[k]<=(k==(start_node<5?start_node:3'd0))?0:255;previous[k]<=7;end
    state<=SCAN;
   end
   SCAN:begin
    if(!visited[scan]&&distance_to[scan]<best_cost)begin best<=scan;best_cost<=distance_to[scan];end
    if(scan==5)begin scan<=0;state<=RELAX;end else scan<=scan+1'b1;
   end
   RELAX:begin
    // First cycle uses the settled minimum from SCAN.
    if(scan==0)begin
     node<=best;visited[best]<=1;scan<=1;
     if(best_cost==255)begin route_edges<=0;distance<=255;valid<=1;state<=READY;end
     else if(best==5)begin trace_node<=5;distance<=best_cost;state<=TRACE;end
    end else begin
     // Scan neighbours 0..5 with scan-1; no simultaneous array write/read ambiguity.
     if(scan==6)begin scan<=0;best_cost<=255;state<=SCAN;end else scan<=scan+1'b1;
     if(weight(node,scan-1'b1,block_shortcut)!=255 &&
        {1'b0,distance_to[node]}+{1'b0,weight(node,scan-1'b1,block_shortcut)}<{1'b0,distance_to[scan-1'b1]})begin
      distance_to[scan-1'b1]<=distance_to[node]+weight(node,scan-1'b1,block_shortcut);
      previous[scan-1'b1]<=node;
     end
    end
   end
   TRACE:begin
    if(trace_node==source)begin
     route_edges<=trace_mask;result_start<=source;result_closed<=block_shortcut;valid<=1;state<=READY;
    end else if(trace_steps==5||trace_edge==7)begin
     route_edges<=0;distance<=255;result_start<=source;result_closed<=block_shortcut;valid<=1;state<=READY;
    end else begin
     trace_mask[trace_edge]<=1;trace_node<=previous[trace_node];trace_steps<=trace_steps+1'b1;
    end
   end
   default:state<=READY;
  endcase
 end
endmodule

// Sample-based UI position; synthetic HDMI silence never advances this counter.
module guide_route_time(input clk,input rst,input restart,input sample_played,
 input [23:0] total_samples,input done,
 output reg [23:0] position,output reg [9:0] progress,
 output reg [15:0] elapsed_bcd,output reg [15:0] total_bcd);
 reg [24:0] fraction;
 reg [15:0] subsecond;
 reg [23:0] total_seen,remaining;
 reg [15:0] total_work;
 reg converting;
 function [15:0] next_second;input [15:0] value;begin
  if(value[3:0]!=9)next_second=value+16'h0001;
  else if(value[7:4]!=5)next_second={value[15:8],value[7:4]+4'd1,4'd0};
  else if(value[11:8]!=9)next_second={value[15:12],value[11:8]+4'd1,8'd0};
  else next_second={value[15:12]+4'd1,12'd0};
 end endfunction
 wire [24:0] next_fraction=fraction+25'd512;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   position<=0;progress<=0;fraction<=0;subsecond<=0;elapsed_bcd<=0;total_bcd<=0;
   total_seen<=0;remaining<=0;total_work<=0;converting<=0;
  end else if(restart)begin
   position<=0;progress<=0;fraction<=0;subsecond<=0;elapsed_bcd<=0;total_bcd<=0;
   total_seen<=0;remaining<=0;total_work<=0;converting<=0;
  end
  else begin
   // File length changes once per track. A shared subtractor converts it in
   // at most 350 clocks, avoiding a 24-bit divider in the pixel clock domain.
   if(total_samples!=total_seen)begin
    total_seen<=total_samples;remaining<=total_samples;total_work<=0;converting<=1;
   end else if(converting)begin
    if(remaining>=24'd48000)begin remaining<=remaining-24'd48000;total_work<=next_second(total_work);end
    else begin total_bcd<=total_work;converting<=0;end
   end
   // Only consumed PCM advances time: HDMI silence, pause and buffering do not.
   if(done&&total_samples!=0&&!converting&&total_seen==total_samples)elapsed_bcd<=total_bcd;
   else if(sample_played)begin
    if(subsecond==16'd47999)begin subsecond<=0;elapsed_bcd<=next_second(elapsed_bcd);end
    else subsecond<=subsecond+1'b1;
   end
   if(done&&total_samples!=0)progress<=10'd512;
   else if(sample_played&&total_samples!=0&&progress<10'd512)begin
    if(next_fraction>={1'b0,total_samples})begin
     fraction<=next_fraction-{1'b0,total_samples};progress<=progress+1'b1;
    end else fraction<=next_fraction;
   end
   if(sample_played&&position!=24'hffffff)position<=position+1'b1;
  end
 end
endmodule

// One visual-only panel. Change its page only under a fully opaque paper veil.
// Audio selection never follows this panel; pause preserves the FIFO position.
module guide_route_panel(input clk,input rst,input enabled,input frame_boundary,
 input toggle,input close,input suspended,input can_open,
 output reg visible,output active,output reg [7:0] fade);
 reg requested,running;
 // Reserve an idle guide as soon as entry is requested. Otherwise its auto
 // timer could queue an old-direction next stop on the entry frame.
 assign active=running||visible||(requested&&can_open);
 always @(posedge clk or posedge rst)begin
  if(rst)begin requested<=0;visible<=0;running<=0;fade<=255;end
  else begin
   if(enabled&&toggle)requested<=~requested;
   if(close)requested<=0;
   if(!suspended&&frame_boundary)begin
    if(!running && requested!=visible && can_open)running<=1;
    else if(running)begin
     if(requested!=visible)begin
      if(fade>32)fade<=fade-32;
      else if(fade!=0)fade<=0;
      else visible<=requested;
     end else if(fade<224)fade<=fade+32;
     else begin fade<=255;running<=0;end
    end
   end
  end
 end
endmodule
// Route selection panel uses PIC12; PIC06 remains the original typhoon warning.
module guide_route_overlay(input [9:0] x,input [9:0] y,input full_map,input mini_map,
 input emergency,input closed,input [2:0] station,input [5:0] route_edges,
 input [5:0] phase,input [9:0] progress,output reg on,output reg [23:0] color);
 wire [10:0] sum={1'b0,x}+{1'b0,y};
 wire signed [10:0] delta=$signed({1'b0,x})-$signed({1'b0,y});
 wire signed [13:0] diagonal=$signed({1'b0,x})*14'sd5-$signed({1'b0,y})*14'sd3;
 wire edge_hit=(x>=390&&x<=470&&y>=208&&y<=212)||
  (x>=320&&x<=390&&y>=208&&y<=212)||
  (x>=270&&x<=320&&y>=158&&y<=212&&delta>=108&&delta<=112)||
  (x>=220&&x<=270&&y>=158&&y<=162)||
  (x>=218&&x<=222&&y>=160&&y<=320)||
  (x>=178&&x<=222&&y>=320&&y<=360&&sum>=538&&sum<=542)||
  (x>=178&&x<=212&&y>=360&&y<=410&&diagonal>=-188&&diagonal<=-172)||
  (x>=210&&x<=566&&y>=408&&y<=412)||
  (x>=564&&x<=568&&y>=210&&y<=410)||
  (x>=470&&x<=566&&y>=208&&y<=212);
 wire node_label=(x>=459&&x<=481&&y>=199&&y<=221)||
  (x>=379&&x<=401&&y>=199&&y<=221)||(x>=209&&x<=231&&y>=149&&y<=171)||
  (x>=169&&x<=191&&y>=349&&y<=371)||(x>=359&&x<=381&&y>=399&&y<=421);
 reg [9:0] cx,cy;
 always @*begin
  case(station)
   0:begin cx=470;cy=210;end 1:begin cx=390;cy=210;end
   2:begin cx=220;cy=160;end 3:begin cx=180;cy=360;end
   default:begin cx=370;cy=410;end
  endcase
 end
 wire [9:0] dx=x>cx?x-cx:cx-x,dy=y>cy?y-cy:cy-y;
 wire [10:0] radius=11'd14+{9'd0,phase[5:4]};
 wire outer=dx<=radius&&dy<=radius&&({1'b0,dx}+{1'b0,dy})<=radius+radius/2;
 wire inner=dx+2<=radius&&dy+2<=radius&&({1'b0,dx}+{1'b0,dy}+3)<=radius+radius/2;
 // Arc coordinates follow 1 -> 2 -> 3 -> 4 -> 5 -> 1. At the wrap the
 // 1152-unit circuit is an exact multiple of the 64-frame pulse period.
 reg [10:0] along;
 always @*begin
  if(y<=212&&x<472)along=11'd470-{1'b0,x};
  else if(x<=222&&y<=320)along=11'd90+{1'b0,y};
  else if(x<=222&&y<=360)along=11'd630-{1'b0,x};
  else if(x<=212&&y<=410)along=11'd90+{1'b0,y};
  else if(y>=408)along=11'd290+{1'b0,x};
  else if(x>=564)along=11'd1266-{1'b0,y};
  else along=11'd1622-{1'b0,x};
 end
 wire [5:0] march=closed?(along[5:0]+phase):(along[5:0]-phase);
 always @*begin
  on=0;color=24'h397f70;
  if(full_map)begin
   if(edge_hit&&!node_label)begin on=1;color=march[4:0]<6?(closed?24'hf0cf89:24'hc6e1cf):(closed?24'had7635:24'h397f70);end
   if(outer&&!inner)begin on=1;color=24'hc38838;end
   if(y>=117&&y<=119&&((!closed&&x>=33&&x<125)||(closed&&x>=190&&x<282)))begin
    on=1;color=closed?24'had7635:24'h397f70;
   end
  end
 end
endmodule
