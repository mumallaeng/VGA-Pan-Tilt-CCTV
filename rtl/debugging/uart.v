`timescale 1ns / 1ps

module uart_loopback (
    input  clk,
    input  rst,
    input  rx,
    output tx
);
    wire w_tx_start;
    wire [7:0] w_rx_data;

    uart U_UART_TOP (
        .clk(clk),
        .rst(rst),
        .tx_start(w_tx_start),
        .tx_data(w_rx_data),
        .rx(rx),

        .rx_data(w_rx_data),
        .rx_done(w_tx_start),
        .tx_busy(),
        .tx(tx)
    );
endmodule


module uart (
    input        clk,
    input        rst,
    input        tx_start,
    input  [7:0] tx_data,
    input        rx,
    output [7:0] rx_data,
    output       rx_done,
    output       tx_busy,
    output       tx
);

    // baud tick generator output to uart tx & rx input
    wire w_b_tick;

    // BAUD Tick generator
    // ======================================================
    baud_tick_gen U_BAUD_TICK_GEN (
        .clk     (clk),
        .rst     (rst),
        .o_b_tick(w_b_tick)
    );
    // ======================================================

    // TX module
    // ======================================================
    uart_tx U_UART_TX (
        .clk     (clk),
        .rst     (rst),
        .b_tick  (w_b_tick),
        .tx_start(tx_start),
        .tx_data (tx_data),   // ASCII Code 0
        .tx_busy (tx_busy),
        .tx      (tx)
    );
    // ======================================================

    // RX module
    // ======================================================
    uart_rx U_UART_RX (
        .clk    (clk),
        .rst    (rst),
        .b_tick (w_b_tick),
        .rx     (rx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );
    // ======================================================

endmodule

// UART RX module
// ======================================================
module uart_rx (
    input            clk,
    input            rst,
    input            b_tick,
    input            rx,
    output reg [7:0] rx_data,
    output           rx_done
);

    // State
    parameter [1:0] IDLE = 0;
    parameter [1:0] START = 1;
    parameter [1:0] DATA = 2;
    parameter [1:0] STOP = 3;

    reg [1:0] c_state, n_state;

    // register to count tick
    reg [4:0] b_tick_cnt_reg, b_tick_cnt_next;
    // register to count input bit num
    reg [2:0] bit_cnt_reg, bit_cnt_next;
    // register to receive data
    reg [7:0] data_reg, data_next, rx_data_next;
    // register to make rx done signal
    reg rx_done_reg, rx_done_next;
    assign rx_done = rx_done_reg;

    // Update Logic (SL)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            c_state        <= IDLE;
            b_tick_cnt_reg <= 5'b0_0000;
            bit_cnt_reg    <= 3'b000;
            data_reg       <= 8'b0000_0000;
            rx_done_reg    <= 1'b0;
            rx_data        <= 0;
        end else begin
            c_state        <= n_state;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;
            data_reg       <= data_next;
            rx_done_reg    <= rx_done_next;
            rx_data        <= rx_data_next;
        end
    end

    // Next State & Output Logic (CL)
    always @(*) begin
        n_state         = c_state;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        data_next       = data_reg;
        rx_done_next    = rx_done_reg;
        rx_data_next    = rx_data;

        case (c_state)
            IDLE: begin
                rx_done_next = 1'b0;
                if (b_tick && ~rx) begin
                    //if (~rx) begin
                    b_tick_cnt_next = 0;
                    n_state         = START;
                end
            end

            START: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 7) begin
                        b_tick_cnt_next = 0;
                        bit_cnt_next    = 0;
                        n_state         = DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            DATA: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        data_next       = {rx, data_reg[7:1]};
                        b_tick_cnt_next = 0;
                        if (bit_cnt_reg == 7) begin
                            b_tick_cnt_next = 0;
                            n_state         = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            STOP: begin
                if (b_tick) begin
                    if ((b_tick_cnt_reg == 23) || (b_tick_cnt_reg > 15 && ~rx)) begin
                        n_state = IDLE;
                        rx_done_next = 1'b1;
                        rx_data_next = data_reg;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end

endmodule
// ======================================================

// UART TX module
// ======================================================
module uart_tx (
    input        clk,
    input        rst,
    input        b_tick,
    input        tx_start,  // start trigger
    input  [7:0] tx_data,
    output       tx_busy,
    output       tx
);
    // 

    // State
    parameter [1:0] IDLE = 0;
    parameter [1:0] START = 1;
    parameter [1:0] DATA = 2;
    parameter [1:0] STOP = 3;

    reg [1:0] c_state, n_state;

    // output register
    reg tx_reg, tx_next;
    assign tx = tx_reg;
    // register to maintain input tx_data
    reg [7:0] data_reg, data_next;
    // register to count tick to baud frequency
    reg [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    // register to count value according to the baud tick
    reg [2:0] bit_cnt_reg, bit_cnt_next;
    // register to get tx busy value
    reg tx_busy_reg, tx_busy_next;
    assign tx_busy = tx_busy_reg;

    // Update logic (SL)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            c_state        <= IDLE;
            tx_reg         <= 1'b1;
            data_reg       <= 8'b0000_0000;
            b_tick_cnt_reg <= 0;
            bit_cnt_reg    <= 3'b000;
            tx_busy_reg    <= 0;
        end else begin
            c_state        <= n_state;
            tx_reg         <= tx_next;
            data_reg       <= data_next;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;
            tx_busy_reg    <= tx_busy_next;
        end
    end

    // Next state & Output logic (CL)
    always @(*) begin
        n_state         = c_state;
        tx_next         = tx_reg;
        data_next       = data_reg;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        tx_busy_next    = tx_busy_reg;

        case (c_state)
            IDLE: begin
                tx_next      = 1'b1;
                tx_busy_next = 1'b0;
                if (tx_start) begin
                    n_state         = START;
                    data_next       = tx_data;
                    b_tick_cnt_next = 0;
                    tx_busy_next    = 1'b1;
                end
            end
            START: begin
                tx_next = 1'b0;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        n_state         = DATA;
                        bit_cnt_next    = 3'b000;
                        b_tick_cnt_next = 4'b0000;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            DATA: begin
                tx_next = data_reg[0];

                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 4'b0000;
                        if (bit_cnt_reg == 7) begin
                            n_state = STOP;
                        end else begin
                            // shift operation to input data
                            data_next    = {1'b0, data_reg[7:1]};
                            bit_cnt_next = bit_cnt_reg + 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            STOP: begin
                tx_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        n_state         = IDLE;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end

endmodule
// ======================================================

// tick generator according to baudrate
// ======================================================
module baud_tick_gen (
    input      clk,
    input      rst,
    output reg o_b_tick
);

    // Parameter for Baudrate and Count value
    // BAUDRATE x 16 to rx can receive data safely
    parameter BAUDRATE = 9600 * 16;
    parameter F_COUNT = 100_000_000 / BAUDRATE;
    parameter BIT_WIDTH = $clog2(F_COUNT);

    // Inner counter
    reg [BIT_WIDTH-1:0] counter_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
            o_b_tick    <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 1;
            o_b_tick    <= 1'b0;
            if (counter_reg == (F_COUNT - 1)) begin
                counter_reg <= 0;
                o_b_tick    <= 1'b1;
            end
        end
    end

endmodule
// ======================================================
