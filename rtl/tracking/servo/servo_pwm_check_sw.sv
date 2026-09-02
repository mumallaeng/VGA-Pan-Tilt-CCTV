`timescale 1ns / 1ps

module servo_pwm_check_sw (
    input logic clk,  // W5, 100 MHz
    input logic rst,  // btnC (U18), 90 degrees
    input logic [15:0] sw,
    output logic JA4,  // G2, Tilt servo signal line
    output logic JA10,  // G3, Pan servo signal line
    output logic [15:0] led  // switch status mirror
);
    logic [15:0] sw_ff1, sw_ff2;
    logic [7:0] tilt_angle_next, tilt_angle_r;
    logic [7:0] pan_angle_next, pan_angle_r;

    always_ff @(posedge clk) begin  // switch 2-stage synchronization
        sw_ff1 <= sw;
        sw_ff2 <= sw_ff1;
    end

    always_comb begin  // index x 15, 12 exceeds 180 clamping
        if (sw_ff2[3:0] >= 4'd12) begin
            tilt_angle_next = 8'd180;
        end else begin
            tilt_angle_next = {4'b0, sw_ff2[3:0]} * 8'd15;
        end

        if (sw_ff2[15:12] >= 4'd12) begin
            pan_angle_next = 8'd180;
        end else begin
            pan_angle_next = {4'b0, sw_ff2[15:12]} * 8'd15;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tilt_angle_r <= 8'd90;
            pan_angle_r  <= 8'd90;
        end else begin
            tilt_angle_r <= tilt_angle_next;
            pan_angle_r  <= pan_angle_next;
        end
    end

    assign led = sw_ff2;  // switch status mirror

    servo_pwm #(
        .CLK_HZ(100_000_000)
    ) U_PWM_TILT (
        .clk  (clk),
        .rst  (rst),
        .angle(tilt_angle_r),
        .pwm  (JA4)
    );

    servo_pwm #(
        .CLK_HZ(100_000_000)
    ) U_PWM_PAN (
        .clk  (clk),
        .rst  (rst),
        .angle(pan_angle_r),
        .pwm  (JA10)
    );
endmodule
