`timescale 1ns/1ps
module tb_fat_stream;
 reg clk=0;always #12 clk=~clk;reg rst=1,start=0,cancel=0;reg [87:0] name="TEST    PCM";
 reg tr=1,sv=0,sdone=0;reg [7:0] sd=0;wire req,valid,done,busy;wire [31:0] lba,size;
 wire [7:0] data,error,stage;reg ready=0;integer cycles=0,idx,bi=0,i,j,active=0,count=0;
 reg [31:0] lbas[0:6];reg [7:0] sectors[0:3583];
 guide_fat_stream dut(clk,rst,start,cancel,1'b0,name,tr,req,lba,sd,sv,sdone,8'd0,data,valid,ready,done,busy,size,error,stage);
 always @(negedge clk) begin
  cycles=cycles+1;sv=0;sdone=0;ready=cycles%17>4;
  if(req && tr) begin
   idx=-1;for(j=0;j<7;j=j+1)if(lbas[j]==lba)idx=j;
   if(idx<0)$fatal(1,"unknown lba %d",lba);
   tr=0;active=1;bi=0;
  end else if(active) begin
   if(bi<512)begin sv=1;sd=sectors[idx*512+bi];bi=bi+1;end
   else begin sdone=1;tr=1;active=0;end
  end
 end
 always @(posedge clk) if(valid && ready && !cancel) begin
  if(data!==((count*37+11)&255))$fatal(1,"stream mismatch %d %h",count,data);count=count+1;
 end
 task launch;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 initial begin
  $readmemh("build/test/lbas.hex",lbas);$readmemh("build/test/sectors.hex",sectors);
  #100;@(negedge clk)rst=0;launch();wait(done || error);
  if(error || count!=1300 || size!=1300)$fatal(1,"first read failure %h %d",error,count);
  $display("PASS fragmented root and file chains with backpressure");
  count=0;launch();wait(stage==41);@(negedge clk)cancel=1;@(negedge clk)cancel=0;
  wait(!busy);if(active)$fatal(1,"cancel abandoned outstanding sector");
  count=0;launch();wait(done || error);if(error || count!=1300)$fatal(1,"restart failure");
  $display("PASS cancel drains in-flight sector and restart");
  name="MISS    PCM";count=0;launch();wait(error);if(error!=8'h26)$fatal(1,"missing error %h",error);
  $display("PASS missing file gives 26");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
