create_clock -name SYS_CLK -period 20 [get_ports {sys_clk}]
create_generated_clock -name clk_255m -source [get_ports {sys_clk}] -master_clock SYS_CLK -multiply_by 5.1 [get_pins {u_hdmi_pll/pll_inst.clkc[0]}]
create_generated_clock -name clk_51m -source [get_ports {sys_clk}] -master_clock SYS_CLK -multiply_by 1.02 [get_pins {u_hdmi_pll/pll_inst.clkc[1]}]
create_generated_clock -name clk_100m -source [get_ports {sys_clk}] -master_clock SYS_CLK -multiply_by 2 [get_pins {u_sys_pll/pll_inst.clkc[0]}]
create_generated_clock -name clk_41m -source [get_ports {sys_clk}] -master_clock SYS_CLK -divide_by 1.2 [get_pins {u_sys_pll/pll_inst.clkc[1]}]
create_generated_clock -name clk_41m_shift -source [get_ports {sys_clk}] -master_clock SYS_CLK -divide_by 1.2 -invert [get_pins {u_sys_pll/pll_inst.clkc[2]}]
# Dual-clock line RAM and stable toggle mailboxes cross independent PLLs.
set_clock_groups -asynchronous -group [get_clocks {SYS_CLK}] -group [get_clocks {clk_100m clk_41m clk_41m_shift}] -group [get_clocks {clk_51m clk_255m}]


