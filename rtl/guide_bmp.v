// Validate standard 24-bit BI_RGB BMP and pack pairs as RGB565 for SDRAM.
// The boot sequencer always supplies 640x480 cards placed at (192,76); one
// row is 320 words, which is also the SDRAM address stride between rows.
module guide_bmp(input clk,input rst,input start,input [10:0] width,input [9:0] height,
 input [20:0] base,input [9:0] left,input [9:0] top,
 input raw,                                   // 1 = 裸 RGB565（每像素 2 字节，自底向上）
 input [7:0] data,input valid,output ready,input file_done,input [31:0] file_size,
 output reg wr_valid,input wr_ready,output reg [20:0] wr_addr,output reg [31:0] wr_data,
 output reg done,output reg [7:0] error);
 reg [31:0] pos,offset,dib,bw,bh,compression,format;
 reg [15:0] magic,first_pixel;reg [7:0] b,g,px_lo;reg [1:0] component;
 reg [10:0] x;reg [9:0] y;reg [20:0] row_base;reg top_down,header_ok;
 wire [15:0] rgb565={data[7:3],g[7:2],b[7:3]};
 assign ready=!wr_valid && error==0 && !done;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   pos<=0;offset<=0;dib<=0;bw<=0;bh<=0;compression<=0;format<=0;magic<=0;
   first_pixel<=0;b<=0;g<=0;component<=0;x<=0;y<=0;row_base<=0;top_down<=0;
   header_ok<=0;wr_valid<=0;wr_addr<=0;wr_data<=0;done<=0;error<=0;
  end else if(start) begin
   pos<=0;offset<=0;dib<=0;bw<=0;bh<=0;compression<=0;format<=0;magic<=0;
   component<=0;x<=0;y<=0;header_ok<=0;wr_valid<=0;done<=0;error<=0;
   if(raw) begin                       // 裸格式没有头，起始行就是最下面一行
    header_ok<=1;
    row_base<=base+({1'b0,top,8'd0}+{1'b0,top,6'd0})
      +(({1'b0,height,8'd0}+{1'b0,height,6'd0})-21'd320)+{12'd0,left[9:1]};
   end
  end else begin
   if(wr_valid && wr_ready) wr_valid<=0;
   if(valid && ready) begin
    pos<=pos+1'b1;
    if(!raw) case(pos)
     0:magic[7:0]<=data;1:magic[15:8]<=data;
     10:offset[7:0]<=data;11:offset[15:8]<=data;12:offset[23:16]<=data;13:offset[31:24]<=data;
     14:dib[7:0]<=data;15:dib[15:8]<=data;16:dib[23:16]<=data;17:dib[31:24]<=data;
     18:bw[7:0]<=data;19:bw[15:8]<=data;20:bw[23:16]<=data;21:bw[31:24]<=data;
     22:bh[7:0]<=data;23:bh[15:8]<=data;24:bh[23:16]<=data;25:bh[31:24]<=data;
     26:format[7:0]<=data;27:format[15:8]<=data;28:format[23:16]<=data;29:format[31:24]<=data;
     30:compression[7:0]<=data;31:compression[15:8]<=data;32:compression[23:16]<=data;33:compression[31:24]<=data;
     53:begin
      if(magic!=16'h4d42) error<=8'h40;
      else if(dib<40 || offset<54 || offset>file_size || (file_size-offset)<width*height*3) error<=8'h41;
      else if(bw!={21'd0,width} || (bh!={22'd0,height} && bh!=(32'd0-{22'd0,height}))) error<=8'h42;
      else if(format!=32'h00180001 || compression!=0) error<=8'h43;
      else begin
       header_ok<=1;top_down<=bh[31];
       row_base<=base+({1'b0,top,8'd0}+{1'b0,top,6'd0})
        +(bh[31]?21'd0:(({1'b0,height,8'd0}+{1'b0,height,6'd0})-21'd320))+{12'd0,left[9:1]};
      end
     end
    endcase
    if(raw) begin
     // 每像素 2 字节：先拼成 16bit，再两个像素拼成一个 32bit 字
     if(header_ok && y<height) begin
      if(!component[0]) begin px_lo<=data;component<=2'd1;end
      else begin
       component<=2'd0;
       if(!x[0]) first_pixel<={data,px_lo};
       else begin
        wr_data<={data,px_lo,first_pixel};wr_addr<=row_base+{11'd0,x[10:1]};wr_valid<=1;
       end
       if(x==width-1) begin x<=0;y<=y+1'b1;row_base<=row_base-320;end
       else x<=x+1'b1;
      end
     end
    end else if(header_ok && pos>=offset && y<height) begin
     case(component)
      0:begin b<=data;component<=1;end
      1:begin g<=data;component<=2;end
      2:begin
       component<=0;
       if(!x[0]) first_pixel<=rgb565;
       else begin wr_data<={rgb565,first_pixel};wr_addr<=row_base+{11'd0,x[10:1]};wr_valid<=1;end
       if(x==width-1) begin x<=0;y<=y+1'b1;row_base<=top_down?row_base+320:row_base-320;end
       else x<=x+1'b1;
      end
     endcase
    end
   end
   if(file_done && !wr_valid && !done && error==0) begin
    if(!header_ok || y!=height || component!=0) error<=8'h44;
    else done<=1;
   end
  end
 end
endmodule
