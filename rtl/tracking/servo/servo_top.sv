`timescale 1ns / 1ps

module servo_top #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer MANUAL_CONTROL_HZ = 50,
    parameter integer AUTO_CONTROL_HZ = 6,
    // One pair of mechanical limits per axis. axis_ctrl clamps its accumulator
    // to them and servo_pwm clamps the pulse to them; if the two ever disagree
    // the wider one becomes silent integrator windup, so both get the same
    // parameter here rather than their own defaults.
    //
    // These were 45..135 on both axes, which turned out to be the dominant
    // limit in flight: a target at the edge of the frame is 30 deg off
    // boresight, so from anywhere but dead centre the loop ran into a rail and
    // sat there. Pan is base rotation and gets close to the servo's full
    // sweep; tilt is held back because the camera swings into the bracket.
    parameter integer PAN_ANGLE_MIN = 15,
    parameter integer PAN_ANGLE_MAX = 165,
    parameter integer TILT_ANGLE_MIN = 25,
    parameter integer TILT_ANGLE_MAX = 155
) (
    input  logic              clk,
    input  logic              rst,
    input  logic signed [9:0] frame_dx,
    input  logic signed [8:0] frame_dy,
    input  logic              frame_valid,
    input  logic              frame_done,
    input  logic              mode,
    input  logic signed [4:0] joy_dx,
    input  logic signed [4:0] joy_dy,
    input  logic              joy_valid,
    input  logic              joy_done,
    output logic              pwm_pan,
    output logic              pwm_tilt,
    output logic              tx        // 9600 baud debug link
);

    logic signed [9:0] delta_x;
    logic signed [8:0] delta_y;
    logic        [7:0] pan_angle;
    logic        [7:0] tilt_angle;
    logic              sel_done;

    ctrl_mode_mux #(
        .CLK_HZ           (CLK_HZ),
        .MANUAL_CONTROL_HZ(MANUAL_CONTROL_HZ),
        .AUTO_CONTROL_HZ  (AUTO_CONTROL_HZ)
    ) u_ctrl_mode_mux (
        .clk        (clk),
        .rst        (rst),
        .frame_dx   (frame_dx),
        .frame_dy   (frame_dy),
        .frame_valid(frame_valid),
        .frame_done (frame_done),
        .mode       (mode),
        .joy_dx     (joy_dx),
        .joy_dy     (joy_dy),
        .joy_valid  (joy_valid),
        .joy_done   (joy_done),
        .delta_x    (delta_x),
        .delta_y    (delta_y),
        .sel_done   (sel_done)
    );

    axis_ctrl #(
        .PAN_ANGLE_MIN (PAN_ANGLE_MIN),
        .PAN_ANGLE_MAX (PAN_ANGLE_MAX),
        .TILT_ANGLE_MIN(TILT_ANGLE_MIN),
        .TILT_ANGLE_MAX(TILT_ANGLE_MAX)
    ) u_axis_ctrl (
        .clk       (clk),
        .reset     (rst),
        .delta_x   (delta_x),
        .delta_y   (delta_y),
        .update    (sel_done),
        .angle_pan (pan_angle),
        .angle_tilt(tilt_angle)
    );

    servo_pwm #(
        .CLK_HZ   (CLK_HZ),
        .ANGLE_MIN(PAN_ANGLE_MIN),
        .ANGLE_MAX(PAN_ANGLE_MAX)
    ) u_servo_pwm_pan (
        .clk  (clk),
        .rst  (rst),
        .angle(pan_angle),
        .pwm  (pwm_pan)
    );

    servo_pwm #(
        .CLK_HZ   (CLK_HZ),
        .ANGLE_MIN(TILT_ANGLE_MIN),
        .ANGLE_MAX(TILT_ANGLE_MAX)
    ) u_servo_pwm_tilt (
        .clk  (clk),
        .rst  (rst),
        .angle(tilt_angle),
        .pwm  (pwm_tilt)
    );

    // Debug: one ASCII line per sampled frame carrying the whole chain, from
    // the raw frame error through the mux output to the commanded angles.
    servo_debug_uart #(
        .DECIMATION(6)
    ) u_servo_debug_uart (
        .clk        (clk),
        .rst        (rst),
        .frame_dx   (frame_dx),
        .frame_dy   (frame_dy),
        .frame_valid(frame_valid),
        .frame_done (frame_done),
        .delta_x    (delta_x),
        .delta_y    (delta_y),
        .pan_angle  (pan_angle),
        .tilt_angle (tilt_angle),
        .tx         (tx)
    );

endmodule


module servo_joystick_top #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer MANUAL_CONTROL_HZ = 100  // #1: 2x sample rate, faster reversal response
) (
    input logic clk,
    input logic rst,

    input logic vauxp6,
    input logic vauxn6,
    input logic vauxp14,
    input logic vauxn14,
    input logic joy_btn,

    output logic pwm_pan,
    output logic pwm_tilt,
    output logic tx
);

    logic signed [4:0] joy_dx;
    logic signed [4:0] joy_dy;
    logic              joy_valid;
    logic              joy_done;
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
        .joy_valid  (joy_valid),
        .joy_done   (joy_done),
        .manual_en  (manual_en)
    );

    servo_top #(
        .CLK_HZ           (CLK_HZ),
        .MANUAL_CONTROL_HZ(MANUAL_CONTROL_HZ)
    ) u_servo (
        .clk(clk),
        .rst(rst),

        .frame_dx   ('0),
        .frame_dy   ('0),
        .frame_valid(1'b0),
        .frame_done (1'b0),

        // manual mode enable comes from the joystick button toggle
        .mode(manual_en),

        .joy_dx(joy_dx),
        .joy_dy(joy_dy),
        .joy_valid(joy_valid),
        .joy_done(joy_done),

        .pwm_pan (pwm_pan),
        .pwm_tilt(pwm_tilt),
        .tx      (tx)
    );

endmodule
