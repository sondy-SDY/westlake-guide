# 厂家基础 IP 来源

以下文件从用户已提供的康芯 2026 参考资料复制，保留内容与原有声明，未修改加密 IP：

- `hdmi_1_4b_transmitter_core_wrapper.enc.v`：`7_lab_ex_2026_nosoft/lab_ex5_i2s/src/user_source/hdl_source/hdmi1.4b_transmitter_core/`。
- `hdmi_phy_warpper.v`、`lane_lvds_10_1.v`：同例程的 `hdl_source/`。

工程还引用父目录 `vendor` 中原有 HDMI PLL、系统 PLL、SDRAM 控制器，以及父目录 `rtl` 中已点亮使用的 SPI/SD 传输和 SDRAM 封装。

本目录的 HDMI IP 为厂家加密协议发射核，TD 编译成功不等于真实终端音视频验收。新编写的 `guide/rtl` 负责 FAT32 文件管理、BMP 解析与 RGB565 打包、六页缓存、按键调度、PCM FIFO、状态字模及视频 AXI 流。对外发布或参赛提交时应保留相应来源说明并遵循原 IP 授权条件。
