`timescale 1ns / 1ps

module servo_top (
    input  logic              clk,
    input  logic              rst,
    input  logic signed [9:0] frame_dx,
    input  logic signed [8:0] frame_dy,
    input  logic              frame_valid,
    input  logic              frame_done,
    input  logic              mode,
    input  logic signed [4:0] joy_dx,
    input  logic signed [4:0] joy_dy,
    output logic              pwm_pan,
    output logic              pwm_tilt
);

    logic signed [9:0] delta_x;
    logic signed [8:0] delta_y;
    logic signed [7:0] pan_angle;
    logic signed [7:0] tilt_angle;
    logic              sel_done;

    ctrl_mode_mux u_ctrl_mode_mux (
        .frame_dx   (frame_dx),
        .frame_dy   (frame_dy),
        .frame_valid(frame_valid),
        .frame_done (frame_done),
        .mode       (mode),
        .joy_dx     (joy_dx),
        .joy_dy     (joy_dy),
        .delta_x    (delta_x),
        .delta_y    (delta_y),
        .sel_done   (sel_done)
    );

    axis_ctrl u_axis_ctrl (
        .clk       (clk),
        .reset     (rst),
        .delta_x   (delta_x),
        .delta_y   (delta_y),
        .update    (sel_done),
        .angle_pan (pan_angle),
        .angle_tilt(tilt_angle)
    );

    servo_pwm u_servo_pwm_pan (
        .clk  (clk),
        .rst  (rst),
        .angle(pan_angle),
        .pwm  (pwm_pan)
    );

    servo_pwm u_servo_pwm_tilt (
        .clk  (clk),
        .rst  (rst),
        .angle(tilt_angle),
        .pwm  (pwm_tilt)
    );

endmodule


module servo_joystick_top (
    input logic clk,
    input logic rst,

    input logic vauxp6,
    input logic vauxn6,
    input logic vauxp14,
    input logic vauxn14,
    input logic joy_btn,

    output logic pwm_pan,
    output logic pwm_tilt
);

    logic signed [4:0] joy_dx;
    logic signed [4:0] joy_dy;
    logic              manual_en;

    joystick_top u_joystick (
        .clk        (clk),
        .rst        (rst),
        .vauxp6     (vauxp6),
        .vauxn6     (vauxn6),
        .vauxp14    (vauxp14),
        .vauxn14    (vauxn14),
        .joy_btn    (joy_btn),
        .joy_motor_x(joy_dx),
        .joy_motor_y(joy_dy),
        .manual_en  (manual_en)
    );

    servo_top u_servo (
        .clk(clk),
        .rst(rst),

        .frame_dx   ('0),
        .frame_dy   ('0),
        .frame_valid(1'b0),
        .frame_done (1'b0),

        // ctrl_mode_mux의 수동 모드
        .mode(1'b1),

        .joy_dx(joy_dx),
        .joy_dy(joy_dy),

        .pwm_pan (pwm_pan),
        .pwm_tilt(pwm_tilt)
    );

endmodule
