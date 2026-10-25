// BH1750FVI 控制器：100 ms 上电等待 -> 0x01 上电 -> 10 ms -> 0x10 连续高分辨率
// -> 180 ms 首测 -> 每 200 ms 读 2 字节；lux = raw/1.2 ≈ raw*54613/65536。
// 移植自用户的 bh1750_fpga_demo/bh1750_ctrl.v，只改了模块名，5 个延时从 localparam 改成
// parameter（默认值仍是 50 MHz 的真延时，测试台可以调小加速仿真）。
module guide_bh1750(
    input  wire        clk,
    input  wire        rst_n,
    output wire        i2c_scl,
    inout  wire        i2c_sda,
    output reg  [15:0] lux,
    output reg  [15:0] raw,
    output reg         data_valid,
    output reg         error,
    output wire        i2c_busy
);

    localparam [3:0] S_PWR       = 4'd0;
    localparam [3:0] S_PON       = 4'd1;
    localparam [3:0] S_PON_DONE  = 4'd2;
    localparam [3:0] S_PON_W     = 4'd3;
    localparam [3:0] S_CONT      = 4'd4;
    localparam [3:0] S_CONT_DONE = 4'd5;
    localparam [3:0] S_CONT_W    = 4'd6;
    localparam [3:0] S_READ      = 4'd7;
    localparam [3:0] S_READ_DONE = 4'd8;
    localparam [3:0] S_READ_W    = 4'd9;
    localparam [3:0] S_ERR_W     = 4'd10;
    localparam [3:0] S_ERR       = 4'd11;

    parameter  [31:0] T100MS = 32'd4_999_999;
    parameter  [31:0] T10MS  = 32'd499_999;
    parameter  [31:0] T180MS = 32'd8_999_999;
    parameter  [31:0] T200MS = 32'd9_999_999;
    parameter  [31:0] T500MS = 32'd24_999_999;

    reg [3:0]  state;
    reg [31:0] delay_cnt;
    reg        i2c_start;
    reg        i2c_rw;
    reg [7:0]  i2c_wdata;

    wire [7:0]  rd_hi;
    wire [7:0]  rd_lo;
    wire        i2c_done;
    wire        ack_err;

    wire [15:0] raw_next = {rd_hi, rd_lo};
    wire [31:0] lux_mult = raw_next * 16'd54613;
    wire [15:0] lux_next = lux_mult[31:16];

    guide_i2c_master u_i2c(
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (i2c_start),
        .dev_addr (7'h23),
        .rw       (i2c_rw),
        .wr_data  (i2c_wdata),
        .rd_hi    (rd_hi),
        .rd_lo    (rd_lo),
        .busy     (i2c_busy),
        .done     (i2c_done),
        .ack_err  (ack_err),
        .scl      (i2c_scl),
        .sda      (i2c_sda)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_PWR;
            delay_cnt  <= 32'd0;
            i2c_start  <= 1'b0;
            i2c_rw     <= 1'b0;
            i2c_wdata  <= 8'd0;
            lux        <= 16'd0;
            raw        <= 16'd0;
            data_valid <= 1'b0;
            error      <= 1'b0;
        end else begin
            i2c_start  <= 1'b0;
            data_valid <= 1'b0;

            case (state)
                S_PWR: begin
                    if (delay_cnt >= T100MS) begin
                        delay_cnt <= 32'd0;
                        state     <= S_PON;
                    end else begin
                        delay_cnt <= delay_cnt + 32'd1;
                    end
                end

                S_PON: begin
                    i2c_rw    <= 1'b0;
                    i2c_wdata <= 8'h01;
                    i2c_start <= 1'b1;
                    state     <= S_PON_DONE;
                end

                S_PON_DONE: begin
                    if (i2c_done) begin
                        if (ack_err) begin
                            error     <= 1'b1;
                            delay_cnt <= 32'd0;
                            state     <= S_ERR_W;
                        end else begin
                            error     <= 1'b0;
                            delay_cnt <= 32'd0;
                            state     <= S_PON_W;
                        end
                    end
                end

                S_PON_W: begin
                    if (delay_cnt >= T10MS) begin
                        delay_cnt <= 32'd0;
                        state     <= S_CONT;
                    end else begin
                        delay_cnt <= delay_cnt + 32'd1;
                    end
                end

                S_CONT: begin
                    i2c_rw    <= 1'b0;
                    i2c_wdata <= 8'h10;
                    i2c_start <= 1'b1;
                    state     <= S_CONT_DONE;
                end

                S_CONT_DONE: begin
                    if (i2c_done) begin
                        if (ack_err) begin
                            error     <= 1'b1;
                            delay_cnt <= 32'd0;
                            state     <= S_ERR_W;
                        end else begin
                            error     <= 1'b0;
                            delay_cnt <= 32'd0;
                            state     <= S_CONT_W;
                        end
                    end
                end

                S_CONT_W: begin
                    if (delay_cnt >= T180MS) begin
                        delay_cnt <= 32'd0;
                        state     <= S_READ;
                    end else begin
                        delay_cnt <= delay_cnt + 32'd1;
                    end
                end

                S_READ: begin
                    i2c_rw    <= 1'b1;
                    i2c_wdata <= 8'd0;
                    i2c_start <= 1'b1;
                    state     <= S_READ_DONE;
                end

                S_READ_DONE: begin
                    if (i2c_done) begin
                        if (ack_err) begin
                            error     <= 1'b1;
                            delay_cnt <= 32'd0;
                            state     <= S_ERR_W;
                        end else begin
                            error      <= 1'b0;
                            raw        <= raw_next;
                            lux        <= lux_next;
                            data_valid <= 1'b1;
                            delay_cnt  <= 32'd0;
                            state      <= S_READ_W;
                        end
                    end
                end

                S_READ_W: begin
                    if (delay_cnt >= T200MS) begin
                        delay_cnt <= 32'd0;
                        state     <= S_READ;
                    end else begin
                        delay_cnt <= delay_cnt + 32'd1;
                    end
                end

                S_ERR: begin
                    delay_cnt <= 32'd0;
                    state     <= S_ERR_W;
                end

                S_ERR_W: begin
                    if (delay_cnt >= T500MS) begin
                        delay_cnt <= 32'd0;
                        state     <= S_PWR;
                    end else begin
                        delay_cnt <= delay_cnt + 32'd1;
                    end
                end

                default: state <= S_PWR;
            endcase
        end
    end

endmodule