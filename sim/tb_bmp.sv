`timescale 1ns/1ps
module tb_bmp;
 reg clk=0;always #12 clk=~clk;reg rst=1,start=0;
 reg [10:0] width;reg [9:0] height,left,top;reg [20:0] base;
 reg [7:0] data;reg valid=0,fdone=0;wire ready,wv,done;reg wr=0;reg rawm=0;
 reg [31:0] size;wire [20:0] addr;wire [31:0] word;wire [7:0] error;
 reg [7:0] bytes[0:921653];reg [31:0] expected[0:153599];
 integer f,n,i,index,count,cycle=0,row,col;string filename,golden;
 guide_bmp dut(clk,rst,start,width,height,base,left,top,rawm,data,valid,ready,fdone,size,wv,wr,addr,word,done,error);
 always @(negedge clk) begin cycle=cycle+1;wr=cycle%11>2;end
 always @(posedge clk) if(!rst && wv && wr) begin
  row=(addr-base)/320;col=(addr-base)%320;
  if(row<0 || row>=height || col>=width/2) $fatal(1,"bad address %0d",addr);
  if(word!==expected[row*(width/2)+col]) $fatal(1,"BMP word mismatch file=%s row=%0d col=%0d got=%h expected=%h",filename,row,col,word,expected[row*(width/2)+col]);
  count=count+1;
 end
 initial begin
  #100;@(negedge clk)rst=0;
  for(index=0;index<9;index=index+1) begin
   base=0;left=0;top=0;width=640;height=480;rawm=0;
   filename=$sformatf("card/PIC%02d.BMP",index);golden=$sformatf("build/test/PIC%02d.hex",index);
   if(index==6) begin base=153600;filename="build/test/TOPDOWN.BMP";golden="build/test/PIC01.hex";end
   if(index==7) begin base=153600;filename="build/test/BAD.BMP";golden="build/test/PIC01.hex";end
   if(index==8) begin rawm=1;filename="card/PIC01.DAT";golden="build/test/PIC01.hex";end
   f=$fopen(filename,"rb");if(!f)$fatal(1,"missing %s",filename);n=$fread(bytes,f);$fclose(f);size=n;
   $readmemh(golden,expected,0,width*height/2-1);count=0;fdone=0;start=1;
   @(negedge clk);start=0;
   for(i=0;i<n && error==0;i=i+1) begin
    data=bytes[i];valid=1;@(posedge clk);while(!ready && error==0)@(posedge clk);@(negedge clk);
   end
   valid=0;fdone=1;
   if(index==7) begin if(error!=8'h43)$fatal(1,"bad format not rejected %h",error);end
   else begin wait(done || error!=0);if(error!=0 || count!=width*height/2)$fatal(1,"BMP completion %h %0d",error,count);end
   $display("PASS %s words=%0d error=%h",filename,count,error);@(negedge clk);
  end
  $finish;
 end
 initial begin #400000000;$fatal(1,"timeout");end
endmodule
