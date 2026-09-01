`timescale 1ps / 1ps

module ov7670_sccb_master #(
    parameter integer CLK_FREQ_HZ  = 100_000_000,
    parameter integer SCCB_FREQ_HZ = 100_000,
    parameter integer CHECK_ACK    = 0
) (
    //global signals
    input  logic       clk_100MHz,
    input  logic       rst,
    //data signals
    input  logic       start,
    input  logic [7:0] reg_addr,
    input  logic [7:0] reg_data,
    //sccb singals
    output logic       busy,
    output logic       done,
    output logic       ack_error,
    output logic       ov_sioc,
    inout  wire        ov_siod
);

    localparam logic [7:0] DEVICE_WRITE_ADDR = 8'h42;

    //SIOC's H_L continue time
    //100MHz / (100KHz *2) = 500clk
    localparam integer HALF_PERIOD_CNT = CLK_FREQ_HZ / (SCCB_FREQ_HZ * 2);

    typedef enum logic [3:0] {
        S_IDLE,
        S_START_SETUP,
        S_START_HOLD,
        S_BIT_LOW,
        S_BIT_HIGH,
        S_ACK_LOW,
        S_ACK_HIGH,
        S_STOP_LOW,
        S_STOP_HIGH,
        S_STOP_RELEASE
    } state_e;
    state_e        state;


    logic   [31:0] clock_cnt;
    logic          sccb_tick;

    logic   [23:0] tx_shift;
    logic   [ 2:0] bit_cnt;
    logic   [ 1:0] byte_cnt;

    logic          siod_drive_low;
    //SIOD -> Open Drain
    assign ov_siod = siod_drive_low ? 1'b0 : 1'bz;

    always_ff @(posedge clk_100MHz or posedge rst) begin : HALF_PERIOD_tick_gen
        if (rst) begin
            clock_cnt <= '0;
            sccb_tick <= 1'b0;
        end else begin
            sccb_tick <= 1'b0;

            if (!busy) begin
                clock_cnt <= 32'd0;
            end else if (clock_cnt == HALF_PERIOD_CNT - 1) begin
                clock_cnt <= 32'd0;
                sccb_tick <= 1'b1;
            end else begin
                clock_cnt <= clock_cnt + 1'b1;
            end
        end
    end

    always_comb begin : SIOC_SIOD_Comb_logic
        ov_sioc        = 1'b1;
        siod_drive_low = 1'b0;
        case (state)
            S_IDLE, S_START_SETUP: begin
                ov_sioc        = 1'b1;
                siod_drive_low = 1'b0;
            end
            //when siod == high -> siod high2low
            S_START_HOLD: begin
                ov_sioc        = 1'b1;
                siod_drive_low = 1'b1;
            end
            S_BIT_LOW: begin
                ov_sioc        = 1'b0;
                siod_drive_low = ~tx_shift[23];
            end
            S_BIT_HIGH: begin
                ov_sioc        = 1'b1;
                siod_drive_low = ~tx_shift[23];
            end
            //ACK -> SIOD release
            S_ACK_LOW: begin
                ov_sioc        = 1'b0;
                siod_drive_low = 1'b0;
            end
            S_ACK_HIGH: begin
                ov_sioc        = 1'b1;
                siod_drive_low = 1'b0;
            end
            S_STOP_LOW: begin
                ov_sioc        = 1'b0;
                siod_drive_low = 1'b1;
            end
            S_STOP_HIGH: begin
                ov_sioc        = 1'b1;
                siod_drive_low = 1'b1;
            end
            //when sioc high -> SIOD LOW to HIGH
            S_STOP_RELEASE: begin
                ov_sioc        = 1'b1;
                siod_drive_low = 1'b0;
            end
            default: begin
                ov_sioc        = 1'b1;
                siod_drive_low = 1'b0;
            end
        endcase
    end


    always_ff @(posedge clk_100MHz or posedge rst) begin : FSM
        if (rst) begin
            state     <= S_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            ack_error <= 1'b0;

            tx_shift  <= 24'd0;
            bit_cnt   <= 3'd0;
            byte_cnt  <= 2'd0;
        end else begin
            done <= 1'b0;
            if (state == S_IDLE) begin
                busy <= 1'b0;

                if (start) begin
                    tx_shift <= {DEVICE_WRITE_ADDR, reg_addr, reg_data};
                    bit_cnt   <= 3'd7;
                    byte_cnt  <= 2'd0;
                    busy      <= 1'b1;
                    ack_error <= 1'b0;
                    state     <= S_START_SETUP;
                end
            end else if (sccb_tick) begin
                case (state)
                    S_START_SETUP: begin
                        state <= S_START_HOLD;
                    end
                    S_START_HOLD: begin
                        state <= S_BIT_LOW;
                    end
                    S_BIT_LOW: begin
                        state <= S_BIT_HIGH;
                    end
                    S_BIT_HIGH: begin
                        if (bit_cnt == 3'd0) begin
                            state <= S_ACK_LOW;
                        end else begin
                            tx_shift <= tx_shift << 1;
                            bit_cnt <= bit_cnt - 1'b1;
                            state <= S_BIT_LOW;
                        end
                    end
                    S_ACK_LOW: begin
                        state <= S_ACK_HIGH;
                    end
                    S_ACK_HIGH: begin
                        // SCCB defines the ninth write bit as Don't-Care.
                        // CHECK_ACK is available only for I2C-like devices.
                        if (CHECK_ACK && (ov_siod != 1'b0)) begin
                            ack_error <= 1'b1;
                        end

                        if (byte_cnt == 2'd2) begin
                            state <= S_STOP_LOW;
                        end else begin
                            tx_shift <= tx_shift << 1;
                            byte_cnt <= byte_cnt + 1'b1;
                            bit_cnt  <= 3'd7;
                            state    <= S_BIT_LOW;
                        end
                    end
                    S_STOP_LOW: begin
                        state <= S_STOP_HIGH;
                    end
                    S_STOP_HIGH: begin
                        state <= S_STOP_RELEASE;
                    end
                    S_STOP_RELEASE: begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                    default: begin
                        state <= S_IDLE;
                        busy  <= 1'b0;
                    end
                endcase
            end
        end
    end
endmodule
