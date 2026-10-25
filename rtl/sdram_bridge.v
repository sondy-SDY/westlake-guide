`include "../vendor/global_def.v"
module sdram_bridge(input clk,input clk_shift,input rst,output init,output refreshing,
 input wr_en,input [20:0] wr_addr,input [31:0] wr_data,
 input rd_en,input [20:0] rd_addr,output rd_valid,output [31:0] rd_data);
 wire sclk,ras_n,cas_n,we_n;wire [10:0] addr;wire [1:0] ba;
 wire [3:0] dm;wire [31:0] dq;wire busy;
 sdr_as_ram #(.self_refresh_open(1'b1)) core(
 .Sdr_clk(clk),.Sdr_clk_sft(clk_shift),.Rst(rst),.Sdr_init_done(init),
 .Sdr_init_ref_vld(refreshing),.Sdr_busy(busy),.App_ref_req(1'b0),
 .App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_dm(4'b0),.App_wr_din(wr_data),
 .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data),
 .SDRAM_CLK(sclk),.SDR_RAS(ras_n),.SDR_CAS(cas_n),.SDR_WE(we_n),
 .SDR_BA(ba),.SDR_ADDR(addr),.SDR_DM(dm),.SDR_DQ(dq));
 EG_PHY_SDRAM_2M_32 memory(.clk(sclk),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),
 .addr(addr),.ba(ba),.dq(dq),.cs_n(1'b0),.dm0(dm[0]),.dm1(dm[1]),.dm2(dm[2]),.dm3(dm[3]),.cke(1'b1));
endmodule
