`timescale 1ns/1ps
module tb_hdmi_link_monitor;
 reg clk=0,reset_n=0,pll=0,video=0;wire [3:0] led;
 always #10 clk=~clk;
 hdmi_link_monitor dut(clk,reset_n,pll,video,led);
 task settle;begin repeat(5)@(negedge clk);end endtask
 initial begin
  settle();reset_n=1;settle();
  if(led!==4'b0000)$fatal(1,"startup must not count as loss");
  pll=1;settle();if(led!==4'b0010)$fatal(1,"PLL acquisition");
  video=1;settle();if(led!==4'b0011)$fatal(1,"video acquisition");
  video=0;settle();if(led!==4'b0110)$fatal(1,"video loss history");
  video=1;settle();if(led!==4'b0111)$fatal(1,"history survived reacquisition");
  pll=0;video=0;settle();if(led!==4'b1100)$fatal(1,"PLL loss history");
  pll=1;video=1;settle();if(led!==4'b1111)$fatal(1,"history survived PLL reset");
  reset_n=0;settle();if(led!==4'b0000)$fatal(1,"KEY1 clears history");
  $display("PASS HDMI monitor: startup, acquisition, video loss, PLL loss, sticky recovery, KEY1 clear");$finish;
 end
endmodule
