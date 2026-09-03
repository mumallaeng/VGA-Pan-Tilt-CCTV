`timescale 1ns / 1ps

module servo_top (
    input  logic signed [9:0] frame_dx,
    input  logic signed [8:0] frame_dy,
    input  logic              frame_valid,
    input  logic              frame_done,
    input  logic              mode,
    input  logic signed [4:0] joy_dx,
    input  logic signed [4:0] joy_dy,
    input  logic              joy_done,
    output logic              pwm_pan,
    output logic              pwm_tilt
);

    logic signed [9:0] delta_x;
    logic signed [8:0] delta_y;
    logic              sel_done;

    ctrl_module_mux u_ctrl_module_mux (
        .frame_dx   (frame_dx),
        .frame_dy   (frame_dy),
        .frame_valid(frame_valid),
        .frame_done (frame_done),
        .mode       (mode),
        .joy_dx     (joy_dx),
        .joy_dy     (joy_dy),
        .joy_done   (joy_done),
        .delta_x    (delta_x),
        .delta_y    (delta_y),
        .sel_done   (sel_done)
    );

    axis_ctrl u_axis_ctrl (
        .delta_x   (delta_x),
        .delta_y   (delta_y),
        .update    (sel_done),
        .angle_pan (pwm_pan),
        .angle_tilt(pwm_tilt)
    );

    servo_pwm u_servo_pwm_pan (
        .clk  (clk),
        .rst  (rst),
        .angle(pwm_pan),
        .pwm  (pwm_pan)
    );

    servo_pwm u_servo_pwm_tilt (
        .clk  (clk),
        .rst  (rst),
        .angle(pwm_tilt),
        .pwm  (pwm_tilt)
    );

endmodule
