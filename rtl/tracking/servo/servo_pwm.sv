`timescale 1ns / 1ps

module servo_pwm #(
    parameter CLK_HZ = 50_000_000,
    parameter PERIOD = CLK_HZ / 50,
    parameter PWM_MIN = CLK_HZ / 1000,
    parameter PWM_MAX = CLK_HZ / 500,
    parameter CNT_PER_DEGREE = (PWM_MAX - PWM_MIN) / 180
) (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] angle,
    output logic       pwm
);

    logic [$clog2(PERIOD)-1:0] counter;
    logic [ $clog2(PWM_MAX):0] high = PWM_MIN + 90 * CNT_PER_DEGREE;

    assign pwm = (counter < high) ? 1'b1 : 1'b0;  // PWM output signal

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 0;
            high    <= PWM_MIN + 90 * CNT_PER_DEGREE;  // default to 90 degrees(1.5ms)
        end else begin
            counter <= (counter == PERIOD - 1) ? 0 : counter + 1'b1;  // Counter for PWM period
            if (counter == 0) begin
                high <= PWM_MIN + angle * CNT_PER_DEGREE;   // Update high value based on angle input
            end
        end
    end
endmodule

