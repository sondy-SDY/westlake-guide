`timescale 1ns/1ps
// BH1750 传感器通路：I2C 主机 + 控制器 + 一个 BH1750 从机模型。
// 从机在 scl/sda 上按协议回 ACK、记录写命令、读的时候返回 raw。
// 延时参数调小只为加速仿真，I2C 位时序（100 kHz）还是真的。
module tb_bh1750;
 reg clk=0;always #10 clk=~clk;          // 50 MHz
 reg rst_n=0;
 wire scl;wire sda;                       // 开漏 + 上拉
 wire [15:0] lux,raw;wire dv,err,busy;
 pullup p_scl(scl);pullup p_sda(sda);

 guide_bh1750 #(.T100MS(32'd200),.T10MS(32'd50),.T180MS(32'd200),.T200MS(32'd400),.T500MS(32'd400))
  dut(.clk(clk),.rst_n(rst_n),.i2c_scl(scl),.i2c_sda(sda),
      .lux(lux),.raw(raw),.data_valid(dv),.error(err),.i2c_busy(busy));

 // ---------------- BH1750 从机模型 ----------------
 reg sda_oe=0;
 assign sda = sda_oe ? 1'b0 : 1'bz;       // 1 = 拉低，0 = 释放（上拉拉高）
 reg scl_d=1,sda_d=1;
 always @(posedge clk) begin scl_d<=scl;sda_d<=sda;end
 wire scl_rise=scl&~scl_d, scl_fall=~scl&scl_d;
 wire start=scl&sda_d&~sda;              // scl 高时 sda 下降
 wire stop =scl&~sda_d&sda;              // scl 高时 sda 上升
 localparam [15:0] RAW=16'h0120;
 wire [31:0] LUX32=RAW*32'd54613;          // 必须显式 32 位，否则上下文按 16 位截断
 wire [15:0] LUX_EXP=LUX32[31:16];
 localparam A_IDLE=0,A_ADDR=1,A_WR=2,A_RD=3;
 reg [1:0] st=A_IDLE;
 reg [3:0] bn=0;
 reg [7:0] shr=0,tx=0;
 reg ack_ph=0,ack_m=0;
 reg [15:0] wr_log=0;                     // 记录收到的命令字节
 integer nwr=0;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   st<=A_IDLE;bn<=0;shr<=0;tx<=0;sda_oe<=0;ack_ph<=0;ack_m<=0;wr_log<=0;nwr<=0;
  end else if(start) begin
   st<=A_ADDR;bn<=0;ack_ph<=0;sda_oe<=0;
  end else if(stop) begin
   st<=A_IDLE;bn<=0;sda_oe<=0;ack_ph<=0;
  end else begin
   if(scl_rise) begin
    if(st==A_RD) begin
     if(bn==8) ack_m<=~sda;              // 主机的 ACK(低)/NAK(高)
    end else if(bn<8) begin
     shr<={shr[6:0],sda};bn<=bn+1;
    end
   end
   if(scl_fall) begin
    if(st==A_RD) begin
     if(bn<7) begin tx<={tx[6:0],1'b0};sda_oe<=~tx[6];bn<=bn+1;end
     else if(bn==7) begin sda_oe<=1'b0;bn<=8;end
     else begin                           // bn==8：本字节结束
      if(ack_m) begin tx<=RAW[7:0];sda_oe<=~RAW[7];bn<=0;end
      else begin sda_oe<=1'b0;bn<=0;st<=A_IDLE;end
     end
    end else if(bn<8) begin
     // 数据位在 scl 上升沿采样，这里不用做事
    end else if(!ack_ph) begin           // ACK 时钟的第一个下降沿：驱动/释放
     ack_ph<=1;
     if(st==A_ADDR) sda_oe<=(shr[7:1]==7'h23);   // 地址匹配才 ACK
     else sda_oe<=1'b1;                          // 写数据一律 ACK
    end else begin                        // ACK 时钟的第二个下降沿：字节结束
     ack_ph<=0;bn<=0;sda_oe<=1'b0;
     if(st==A_ADDR) begin
      if(shr[7:1]==7'h23) begin
       if(shr[0]) begin st<=A_RD;tx<=RAW[15:8];sda_oe<=~RAW[15];bn<=0;end
       else st<=A_WR;
      end else st<=A_IDLE;
     end else if(st==A_WR) begin
      wr_log<={wr_log[7:0],shr};nwr<=nwr+1;
     end
    end
   end
  end
 end

 integer hits=0;
 always @(posedge clk) if(dv) hits<=hits+1;
 initial begin
  repeat(5) @(negedge clk);rst_n=1;
  wait(hits>=2);
  if(raw!==RAW)$fatal(1,"raw=%h want %h",raw,RAW);
  if(lux!==LUX_EXP)$fatal(1,"lux=%0d want %0d",lux,LUX_EXP);
  if(err)$fatal(1,"unexpected i2c error");
  if(nwr<2 || wr_log[15:8]!==8'h01 || wr_log[7:0]!==8'h10)
   $fatal(1,"commands %0d log=%h (want 01 then 10)",nwr,wr_log);
  $display("PASS bh1750: power-on 0x01 + cont 0x10, raw=%h lux=%0d, %0d reads",raw,lux,hits);
  $finish;
 end
 initial begin #5000000;$fatal(1,"timeout: st=%0d hits=%0d sda_oe=%b",st,hits,sda_oe);end
endmodule
