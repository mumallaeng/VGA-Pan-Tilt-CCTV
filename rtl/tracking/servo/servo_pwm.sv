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
    logic [ $clog2(PWM_MAX):0] high;

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

module servo_pwm_check_sw (
    input logic clk,  // W5, 100 MHz
    input logic rst,  // btnC (U18), 90 degrees
    input  logic [3:0] sw,       // SW3..SW0 = step index (0~12 → 0~180°, 15° 간격)
    output logic JA4,  // G2, servo signal line
    output logic [3:0] led  // switch status mirror
);
    logic [3:0] sw_ff1, sw_ff2;
    logic [7:0] angle_next, angle_r;

    always_ff @(posedge clk) begin  // switch 2-stage synchronization
        sw_ff1 <= sw;
        sw_ff2 <= sw_ff1;
    end

    always_comb begin  // index × 15, 12 exceeds 180 clamping
        if (sw_ff2 >= 4'd12) angle_next = 8'd180;
        else angle_next = {4'b0, sw_ff2} * 8'd15;
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) angle_r <= 8'd90;
        else angle_r <= angle_next;
    end

    assign led = sw_ff2;  // switch status mirror

    servo_pwm #(
        .CLK_HZ(100_000_000)
    ) u_pwm (
        .clk  (clk),
        .rst  (rst),
        .angle(angle_r),
        .pwm  (JA4)
    );
endmodule
