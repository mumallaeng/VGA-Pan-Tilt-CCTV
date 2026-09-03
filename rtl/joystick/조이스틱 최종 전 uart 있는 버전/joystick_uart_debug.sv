`timescale 1ns / 1ps

module joystick_uart_debug #(
    parameter integer CLK_FREQ  = 100_000_000,
    parameter integer BAUD_RATE = 115200,
    parameter integer REPORT_HZ = 50
)(
    input  logic               clk,
    input  logic               rst,

    input  logic        [11:0] i_raw_x,
    input  logic        [11:0] i_raw_y,

    input  logic        [11:0] i_filtered_x,
    input  logic        [11:0] i_filtered_y,

    input  logic signed [ 4:0] i_joy_motor_x,
    input  logic signed [ 4:0] i_joy_motor_y,
    input  logic               i_manual_en,

    output logic               o_uart_tx,
    output logic               o_debug_busy
);

    logic       b_tick;

    logic       sender_start;
    logic       sender_busy;

    logic [7:0] tx_data;
    logic       tx_start;
    logic       tx_busy;

    localparam integer REPORT_COUNT = CLK_FREQ / REPORT_HZ;
    localparam integer REPORT_WIDTH = (REPORT_COUNT <= 1) ? 1 : $clog2(REPORT_COUNT);

    logic [REPORT_WIDTH-1:0] report_counter;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            report_counter <= '0;
            sender_start   <= 1'b0;
        end else begin
            sender_start <= 1'b0;

            if (report_counter == REPORT_COUNT - 1) begin
                report_counter <= '0;
                sender_start   <= 1'b1;
            end else begin
                report_counter <= report_counter + 1'b1;
            end
        end
    end

    baud_tick_gen #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) U_BTICK_GEN (
        .clk     (clk),
        .rst     (rst),
        .o_b_tick(b_tick)
    );

    uart_sender U_UART_SENDER (
        .clk             (clk),
        .rst             (rst),
        .i_sender_start  (sender_start),

        .i_raw_x         (i_raw_x),
        .i_raw_y         (i_raw_y),

        .i_filtered_x    (i_filtered_x),
        .i_filtered_y    (i_filtered_y),

        .i_joy_motor_x   (i_joy_motor_x),
        .i_joy_motor_y   (i_joy_motor_y),
        .i_manual_en     (i_manual_en),

        .i_tx_busy       (tx_busy),
        .o_tx_data       (tx_data),
        .o_tx_start      (tx_start),
        .o_sender_busy   (sender_busy)
    );

    uart_tx U_UART_TX (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .b_tick  (b_tick),
        .tx_busy (tx_busy),
        .tx      (o_uart_tx)
    );

    assign o_debug_busy = sender_busy | tx_busy;

endmodule

module baud_tick_gen #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
) (
    input  logic clk,
    input  logic rst,
    output logic o_b_tick
);

    localparam F_COUNT   = CLK_FREQ / (BAUD_RATE * 16);
    localparam CNT_WIDTH = $clog2(F_COUNT) - 1;

    reg [CNT_WIDTH:0] counter_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
            o_b_tick <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == F_COUNT - 1) begin
                counter_reg <= 0;
                o_b_tick <= 1'b1;
            end else begin
                o_b_tick <= 1'b0;
            end
        end
    end
endmodule
