// Boot: PIC00 (route card) then PIC01..PIC06 (5 spots + emergency), all 640x480.
// Runtime: cancel/drain/open PCM.
module guide_media(input clk,input rst,input play_toggle,input [3:0] page,input no_audio,
 input stream_busy,input stream_done,input [7:0] stream_error,input [31:0] file_size,
 output reg stream_start,output reg stream_cancel,output reg [87:0] filename,
 input bmp_done,input [7:0] bmp_error,input memory_idle,output reg bmp_start,
 output [10:0] bmp_width,output [9:0] bmp_height,output [20:0] bmp_base,
 output [9:0] bmp_left,output [9:0] bmp_top,output reg loaded,output reg [3:0] load_index,output reg boot_done,
 output reg [7:0] error,output reg audio_flush,output audio_mode,
 output reg audio_eof,output reg audio_error,output reg mem_restart);
 localparam BOOT=0,OPEN=1,IMAGE=2,DRAIN=3,WAITPLAY=4,CANCEL=5,AOPEN=6,ASTREAM=7,FAILED=8,IWAIT=9,AWAIT=10,RETRY=11;
 reg [3:0] state;reg [1:0] play_sync;reg seen;reg [3:0] selected;reg [5:0] settle;reg [2:0] tries;reg [19:0] rdelay;
 reg in_boot;                       // 先加载 PIC11（美化过的开机卡）到第 12 页（11*153600）
 wire [7:0] digit=8'd48+{4'd0,load_index};
 // Cards are stored tightly: 320 words per row, no in-page offset. Their
 // screen position (192,76) lives in guide_video, not in the page layout.
 assign bmp_width=11'd640;assign bmp_height=10'd480;
 assign bmp_left=10'd0;assign bmp_top=10'd0;
 assign bmp_base=in_boot?21'd1689600:{7'd0,load_index}*21'd153600;
 assign audio_mode=loaded;
 always @(posedge clk or posedge rst) begin
  if(rst) begin state<=BOOT;stream_start<=0;stream_cancel<=0;filename<=0;bmp_start<=0;
   loaded<=0;load_index<=0;boot_done<=0;in_boot<=1;error<=0;audio_flush<=1;audio_eof<=0;audio_error<=0;
   play_sync<=0;seen<=0;selected<=0;settle<=0;tries<=0;mem_restart<=0;rdelay<=0;end
  else begin
   stream_start<=0;stream_cancel<=0;bmp_start<=0;play_sync<={play_sync[0],play_toggle};
   case(state)
    // 10 张导览/广告卡是 PIC00..PIC09，第 11 页是开发者设置卡 PIC10
    BOOT:begin filename<=in_boot?{"PIC11","   DAT"}:
                        (load_index==4'd10)?{"PIC10","   DAT"}:{"PIC0",digit,"   DAT"};state<=OPEN;end
    OPEN:begin stream_start<=1;bmp_start<=1;state<=IWAIT;end
    IWAIT:state<=IMAGE;
    IMAGE:if(stream_error!=0 || bmp_error!=0) begin
     // Keep the first code on screen, but a transient read may recover.
     if(error==0) error<=stream_error!=0?stream_error:bmp_error;
     stream_cancel<=1;mem_restart<=1;rdelay<=0;
     if(tries<4) begin tries<=tries+1'b1;state<=RETRY;end else state<=FAILED;
    end else if(bmp_done) begin tries<=0;state<=DRAIN;end
    // Hold the storage path in restart long enough for the card to re-run its
    // power-up sequence (sd_spi_reader POWER_WAIT is 3 ms of mclk).
    RETRY:if(!stream_busy && memory_idle) begin
     if(rdelay==20'hfffff) begin rdelay<=0;mem_restart<=0;state<=BOOT;end
     else rdelay<=rdelay+1'b1;
    end
    DRAIN:if(memory_idle) begin
     if(in_boot) begin boot_done<=1;in_boot<=0;state<=BOOT;end
     else if(load_index==4'd10) begin loaded<=1;load_index<=4'd11;state<=WAITPLAY;end
     else begin load_index<=load_index+1'b1;state<=BOOT;end
    end
    WAITPLAY:begin end
    CANCEL:begin
     // Hold flush while the old SD transaction drains and pointers reset.
     if(settle!=63) settle<=settle+1'b1;
     if(!stream_busy && settle==63) begin
      if(no_audio) begin
       // 广告页没有音轨：不发流，但 flush 必须释放（BUG-5）。原来这里只清 eof/error，
       // audio_flush 一直保持 1，FIFO 整个广告期都挂在复位上；清掉以后广告态是"空转"
       // 而不是"复位中"，以后给广告加配音不用再改这里。
       audio_eof<=1;audio_error<=0;audio_flush<=0;state<=WAITPLAY;
      end
      else begin filename<={"AUD0",(8'd48+{4'd0,selected}),"   PCM"};state<=AOPEN;end
     end
    end
    AOPEN:begin stream_start<=1;audio_flush<=0;state<=AWAIT;end
    AWAIT:state<=ASTREAM;
    ASTREAM:begin
     if(stream_error!=0 || (file_size[0] && file_size!=0)) begin
      audio_error<=1;audio_eof<=1;stream_cancel<=1;state<=WAITPLAY;
     end else if(stream_done) begin audio_eof<=1;state<=WAITPLAY;end
    end
    FAILED:begin end
    default:state<=FAILED;
   endcase
   if(loaded && play_sync[1]!=seen) begin
    seen<=play_sync[1];selected<=page;stream_cancel<=1;audio_flush<=1;
    audio_eof<=0;audio_error<=0;settle<=0;state<=CANCEL;
   end
  end
 end
endmodule
