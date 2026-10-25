`timescale 1ns/1ps
// Replays the sectors captured from the real TF card through guide_fat_stream.
// Every byte the FPGA would receive is written to build/test/real_stream.bin so
// a host-side SHA256 can prove the parsing and chain walk are byte-exact.
module tb_fat_real;
 reg clk=0;always #12 clk=~clk;reg rst=1,start=0,cancel=0;
 reg [87:0] name="UI00    BMP";
 reg tr=1,sv=0,sdone=0;reg [7:0] sd=0;wire req,valid,done,busy;
 wire [31:0] lba,size;wire [7:0] data,error,stage;reg ready=1;
 reg [31:0] lbas[0:255];reg [7:0] sectors[0:131071];reg [31:0] meta[0:1];
 integer idx,bi=0,j,active=0,n=0,fd,cycles=0,limit;
 guide_fat_stream dut(clk,rst,start,cancel,1'b0,name,tr,req,lba,sd,sv,sdone,8'd0,data,valid,ready,done,busy,size,error,stage);
 always @(negedge clk) begin
  sv=0;sdone=0;cycles=cycles+1;
  if(req && tr) begin
   idx=-1;for(j=0;j<meta[0];j=j+1)if(lbas[j]==lba)idx=j;
   if(idx<0)$fatal(1,"FPGA requested LBA %d which the fixture does not contain",lba);
   tr=0;active=1;bi=0;
  end else if(active) begin
   if(bi<512)begin sv=1;sd=sectors[idx*512+bi];bi=bi+1;end
   else begin sdone=1;tr=1;active=0;end
  end
 end
 always @(posedge clk) begin
  if(valid && ready && !cancel) begin
   $fwrite(fd,"%c",data); n=n+1;
   if(n==limit) begin cancel<=1; end
  end
 end
 task launch;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 initial begin
  fd=$fopen("build/test/real_stream.bin","wb");
  $readmemh("build/test/real_lbas.hex",lbas);
  $readmemh("build/test/real_sectors.hex",sectors);
  $readmemh("build/test/real_meta.hex",meta);
  limit=meta[1];
  #100;@(negedge clk)rst=0;launch();
  wait(error || done || n>=limit || cycles>4000000);
  #200;
  $fclose(fd);
  $display("RESULT err=%02x bytes=%0d file_size=%0d stage=%02x",error,n,size,stage);
  if(error==0 && size==32'd1843254) $display("PASS directory entry and file size parsed from the real card");
  else $display("FAIL");
  $finish;
 end
endmodule
