// 640x480@60 用的时钟源：原厂 clk_wize 的原始参数（VIDEO clk 25 MHz / 串行 125 MHz）。
// VCO = (50/2) x 5 x (8/2) = 500 MHz；C0 = 2x500/8 = 125 MHz；C1 = 2x500/40 = 25 MHz。
// 与 hdmi_pll.v（1024x600 用的 255/51 MHz）互不影响：那份文件不能改，旧单图工程还在用。
`timescale 1 ns / 100 fs
module hdmi_pll_640(refclk,reset,extlock,clk0_out,clk1_out);
  input refclk;input reset;output extlock;output clk0_out;output clk1_out;
  wire clk0_buf;
  EG_LOGIC_BUFG bufg_feedback(.i(clk0_buf),.o(clk0_out));
  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.FIN("50.000"),
    .FEEDBK_MODE("NORMAL"),.FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),.PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(2),.ICP_CURRENT(9),.KVCO(2),.LPF_CAPACITOR(1),.LPF_RESISTOR(8),
    .REFCLK_DIV(2),.FBCLK_DIV(5),
    .CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(8),.CLKC0_CPHASE(7),.CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),.CLKC1_DIV(40),.CLKC1_CPHASE(39),.CLKC1_FPHASE(0)
  ) pll_inst(
    .refclk(refclk),.reset(reset),.stdby(1'b0),.extlock(extlock),
    .load_reg(1'b0),.psclk(1'b0),.psdown(1'b0),.psstep(1'b0),.psclksel(3'b000),.psdone(open),
    .dclk(1'b0),.dcs(1'b0),.dwe(1'b0),.di(8'b0),.daddr(6'b0),
    .do(),
    .fbclk(clk0_out),.clkc({open,open,open,clk1_out,clk0_buf}));
endmodule
