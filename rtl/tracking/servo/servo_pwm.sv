`timescale 1ns / 1ps

module servo_pwm #(
    parameter CLK_HZ = 50_000_000,
    parameter PERIOD = CLK_HZ / 50,
    parameter PWM_MIN = CLK_HZ / 1000,
    parameter PWM_MAX = CLK_HZ / 500,
    parameter CNT_PER_DEGREE = (PWM_MAX - PWM_MIN) / 180,
    // Mechanical travel limits, enforced here so the pulse stays inside them
    // whatever drives angle. axis_ctrl already clamps to 0..180, but a
    // calibration top writing servo_pwm directly bypasses that, and angle is
    // 8 bits wide so it can otherwise ask for up to 255.
    parameter ANGLE_MIN = 45,
    parameter ANGLE_MAX = 135
) (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] angle,
    output logic       pwm
);

    // Park at the centre, pulled inside the limits in case they exclude 90.
    localparam ANGLE_RESET = (90 < ANGLE_MIN) ? ANGLE_MIN :
                             (90 > ANGLE_MAX) ? ANGLE_MAX : 90;

    logic [7:0] angle_limited;
    assign angle_limited = (angle < ANGLE_MIN[7:0]) ? ANGLE_MIN[7:0] :
                           (angle > ANGLE_MAX[7:0]) ? ANGLE_MAX[7:0] : angle;

    logic [$clog2(PERIOD)-1:0] counter;
    logic [ $clog2(PWM_MAX):0] high = PWM_MIN + ANGLE_RESET * CNT_PER_DEGREE;

    // angle arrives from axis_ctrl, which updates on its own 50 Hz tick, and
    // this period counter is a second 50 Hz counter. Reading angle straight
    // into high at the period boundary would make the captured value depend on
    // which side of that boundary the two counters happen to land, so the
    // conversion is registered every cycle instead. The boundary then only
    // copies an already settled value, which also keeps the clamp and the
    // multiply off the path that has to close in the one cycle where
    // counter == 0.
    logic [$clog2(PWM_MAX):0] high_next;

    assign pwm = (counter < high) ? 1'b1 : 1'b0;  // PWM output signal

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter   <= 0;
            high      <= PWM_MIN + ANGLE_RESET * CNT_PER_DEGREE;  // centre position
            high_next <= PWM_MIN + ANGLE_RESET * CNT_PER_DEGREE;
        end else begin
            // Latch the converted width continuously.
            high_next <= PWM_MIN + angle_limited * CNT_PER_DEGREE;

            counter <= (counter == PERIOD - 1) ? 0 : counter + 1'b1;  // Counter for PWM period
            if (counter == 0) begin
                high <= high_next;  // adopt it only at a period boundary
            end
        end
    end
endmodule

