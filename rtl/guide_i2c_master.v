// I2C 主机，100 kHz @ 50 MHz（sys_clk）。移植自用户的 bh1750_fpga_demo/i2c_master.v，
// 只在模块名和注释上做了改动，协议/时序原样保留：
//   写：START + addr/W + 1 字节 + STOP
//   读：START + addr/R + 2 字节（第 1 字节回 ACK、第 2 字节回 NAK）+ STOP
// SCL 推挽、SDA 开漏（靠 GY-302 板上的 4.7k 上拉到 3.3V）。
module guide_i2c_master(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [6:0] dev_addr,
    input  wire       rw,
    input  wire [7:0] wr_data,
    output reg  [7:0] rd_hi,
    output reg  [7:0] rd_lo,
    output reg        busy,
    output reg        done,
    output reg        ack_err,
    output wire       scl,
    inout  wire       sda
);

    localparam PHASE_CYCLES = 125;

    localparam [2:0] S_IDLE  = 3'd0;
    localparam [2:0] S_START = 3'd1;
    localparam [2:0] S_SEND  = 3'd2;
    localparam [2:0] S_ACK   = 3'd3;
    localparam [2:0] S_RD    = 3'd4;
    localparam [2:0] S_MACK  = 3'd5;
    localparam [2:0] S_MNAK  = 3'd6;
    localparam [2:0] S_STOP  = 3'd7;

    reg [7:0] div;
    reg [1:0] phase;
    reg [2:0] state;
    reg [7:0] shift;
    reg [2:0] bitcnt;
    reg       addr_phase;
    reg       is_read;
    reg       byte_idx;
    reg       ack_bit;
    reg       scl_r;
    reg       sda_oe;

    wire tick   = (div == PHASE_CYCLES - 1);
    wire sda_in = sda;

    assign scl = scl_r;
    assign sda = sda_oe ? 1'b0 : 1'bz;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div        <= 8'd0;
            phase      <= 2'd0;
            state      <= S_IDLE;
            shift      <= 8'd0;
            bitcnt     <= 3'd0;
            addr_phase <= 1'b0;
            is_read    <= 1'b0;
            byte_idx   <= 1'b0;
            ack_bit    <= 1'b0;
            scl_r      <= 1'b1;
            sda_oe     <= 1'b0;
            busy       <= 1'b0;
            done       <= 1'b0;
            ack_err    <= 1'b0;
            rd_hi      <= 8'd0;
            rd_lo      <= 8'd0;
        end else begin
            done <= 1'b0;

            if ((state == S_IDLE) && start) begin
                busy       <= 1'b1;
                ack_err    <= 1'b0;
                addr_phase <= 1'b1;
                is_read    <= rw;
                shift      <= {dev_addr, rw};
                bitcnt     <= 3'd0;
                byte_idx   <= 1'b0;
                phase      <= 2'd0;
                div        <= 8'd0;
                scl_r      <= 1'b1;
                sda_oe     <= 1'b0;
                state      <= S_START;
            end else if (tick) begin
                div   <= 8'd0;
                phase <= phase + 2'd1;

                case (state)
                    S_IDLE: begin
                        scl_r  <= 1'b1;
                        sda_oe <= 1'b0;
                        busy   <= 1'b0;
                    end

                    S_START: begin
                        case (phase)
                            2'd0: begin
                                scl_r  <= 1'b1;
                                sda_oe <= 1'b0;
                            end
                            2'd1: begin
                                sda_oe <= 1'b1;
                            end
                            2'd2: begin
                                scl_r <= 1'b0;
                            end
                            2'd3: begin
                                sda_oe <= 1'b0;
                                bitcnt <= 3'd0;
                                state  <= S_SEND;
                            end
                        endcase
                    end

                    S_SEND: begin
                        case (phase)
                            2'd0: begin
                                scl_r  <= 1'b0;
                                sda_oe <= ~shift[7];
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                            end
                            2'd2: begin
                                scl_r <= 1'b1;
                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                shift <= {shift[6:0], 1'b0};
                                if (bitcnt == 3'd7) begin
                                    bitcnt <= 3'd0;
                                    state  <= S_ACK;
                                end else begin
                                    bitcnt <= bitcnt + 3'd1;
                                end
                            end
                        endcase
                    end

                    S_ACK: begin
                        case (phase)
                            2'd0: begin
                                scl_r  <= 1'b0;
                                sda_oe <= 1'b0;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                            end
                            2'd2: begin
                                ack_bit <= sda_in;
                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                if (ack_bit) ack_err <= 1'b1;
                                if (addr_phase) begin
                                    addr_phase <= 1'b0;
                                    if (ack_bit) begin
                                        state <= S_STOP;
                                    end else if (is_read) begin
                                        bitcnt   <= 3'd0;
                                        byte_idx <= 1'b0;
                                        shift    <= 8'd0;
                                        state    <= S_RD;
                                    end else begin
                                        bitcnt <= 3'd0;
                                        shift  <= wr_data;
                                        state  <= S_SEND;
                                    end
                                end else begin
                                    state <= S_STOP;
                                end
                            end
                        endcase
                    end

                    S_RD: begin
                        case (phase)
                            2'd0: begin
                                scl_r  <= 1'b0;
                                sda_oe <= 1'b0;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                            end
                            2'd2: begin
                                shift <= {shift[6:0], sda_in};
                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                if (bitcnt == 3'd7) begin
                                    bitcnt <= 3'd0;
                                    if (byte_idx == 1'b0) state <= S_MACK;
                                    else                  state <= S_MNAK;
                                end else begin
                                    bitcnt <= bitcnt + 3'd1;
                                end
                            end
                        endcase
                    end

                    S_MACK: begin
                        case (phase)
                            2'd0: begin
                                scl_r  <= 1'b0;
                                sda_oe <= 1'b1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                            end
                            2'd2: begin
                                scl_r <= 1'b1;
                            end
                            2'd3: begin
                                scl_r    <= 1'b0;
                                sda_oe   <= 1'b0;
                                rd_hi    <= shift;
                                byte_idx <= 1'b1;
                                bitcnt   <= 3'd0;
                                shift    <= 8'd0;
                                state    <= S_RD;
                            end
                        endcase
                    end

                    S_MNAK: begin
                        case (phase)
                            2'd0: begin
                                scl_r  <= 1'b0;
                                sda_oe <= 1'b0;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                            end
                            2'd2: begin
                                scl_r <= 1'b1;
                            end
                            2'd3: begin
                                scl_r  <= 1'b0;
                                rd_lo  <= shift;
                                state  <= S_STOP;
                            end
                        endcase
                    end

                    S_STOP: begin
                        case (phase)
                            2'd0: begin
                                scl_r  <= 1'b0;
                                sda_oe <= 1'b1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                            end
                            2'd2: begin
                                sda_oe <= 1'b0;
                            end
                            2'd3: begin
                                scl_r <= 1'b0;
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                state <= S_IDLE;
                            end
                        endcase
                    end

                    default: state <= S_IDLE;
                endcase
            end else begin
                div <= div + 8'd1;
            end
        end
    end

endmodule