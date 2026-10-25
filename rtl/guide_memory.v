// Four-word writes retain the SDRAM IP's tested alignment and drain contract.
// After boot all seven pages are immutable. One page is a 640x480 card packed two
// RGB565 pixels per word (153,600 words); a line read is 320 words (7.7 us at
// 41.67 MHz), and only 480 of the 635 rows are ever read.
module guide_memory(input clk,input rst,input mem_init,input mem_refresh,
 input source_valid,output source_ready,input [20:0] source_addr,input [31:0] source_data,
 input display_enable,output idle,
 input line_req,input [9:0] line_y,input [3:0] line_page,output reg line_ack,
 output reg line_we,output reg [8:0] line_addr,output reg [31:0] line_data,
 output wr_en,output [20:0] wr_addr,output [31:0] wr_data,
 output rd_en,output [20:0] rd_addr,input rd_valid,input [31:0] rd_data,
 output reg [15:0] words,input restart);
 localparam COLLECT=0,WSTART=1,WRITE=2,WDRAIN=3,RSTART=4,READ=5,RDRAIN=6;
 reg [2:0] state;reg [31:0] group_data[0:3];reg [1:0] fill,send;
 reg [20:0] base,read_base;reg [4:0] drain;reg [9:0] sent,returned;
 reg [1:0] req_sync;reg seen;
 // 页基址 = 页号 * 153600 = (页号*75) << 11。常数乘法，以后加减页都不会漏。
 // 3 位页号够用（0..7），7 页 = 1,075,200 字 < 2M。
 wire [20:0] page_base=({4'd0,line_page}*10'd75)<<11;
 // 装载写和显示读按"组"分时：写只占 COLLECT 的空隙（4 字一组），行读 320 字 7.7 us 仍在 16 us 行预算内。
 // 原来要求 !display_enable：开机卡一显示，后面的卡就写不进去，进度条就卡住了。
 assign source_ready=state==COLLECT && mem_init;
 assign idle=state==COLLECT && fill==0;
 assign wr_en=state==WRITE;assign wr_addr=base+send;assign wr_data=group_data[send];
 assign rd_en=state==READ;assign rd_addr=read_base+sent;
 always @(posedge clk or posedge rst) begin
  if(rst) begin state<=COLLECT;fill<=0;send<=0;base<=0;drain<=0;
   sent<=0;returned<=0;read_base<=0;req_sync<=0;seen<=0;line_ack<=0;
   line_we<=0;line_addr<=0;line_data<=0;words<=0;end
  else begin
   // A retried file rewrites its page from word 0; drop any partial group.
   if(restart && state==COLLECT) fill<=0;
   req_sync<={req_sync[0],line_req};line_we<=0;
   if(rd_valid && (state==READ || state==RDRAIN)) begin
    line_we<=1;line_addr<=returned[8:0];line_data<=rd_data;returned<=returned+1'b1;
    words<=words+1'b1;
   end
   case(state)
    COLLECT: if(source_valid && source_ready) begin
     group_data[fill]<=source_data;fill<=fill+1'b1;if(fill==0) base<=source_addr;
     if(fill==3) state<=WSTART;
    end else if(display_enable && req_sync[1]!=seen) begin
     seen<=req_sync[1];read_base<=page_base+({11'd0,line_y}<<8)+({11'd0,line_y}<<6);
     sent<=0;returned<=0;state<=RSTART;
    end
    WSTART: if(mem_init && !mem_refresh) begin send<=0;state<=WRITE;end
    WRITE: if(send==3) begin state<=WDRAIN;drain<=0;end else send<=send+1'b1;
    WDRAIN: if(drain==15) state<=COLLECT;else drain<=drain+1'b1;
    RSTART: if(!mem_refresh) state<=READ;
    READ: if(sent==319) state<=RDRAIN;else sent<=sent+1'b1;
    RDRAIN: if(returned==320) begin line_ack<=seen;state<=COLLECT;end
    default:state<=COLLECT;
   endcase
  end
 end
endmodule
