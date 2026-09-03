`timescale 1ns / 1ps

module servo_top #(
    parameter integer CLK_HZ             = 100_000_000,
    parameter integer MOVE_TICK_HZ       = 50,
    parameter integer PAN_GAIN_NUM       = 0,
    parameter integer PAN_GAIN_DEN       = 1,
    parameter integer TILT_GAIN_NUM      = 0,
    parameter integer TILT_GAIN_DEN      = 1,
    parameter integer PAN_DEADZONE       = 0,
    parameter integer TILT_DEADZONE      = 0,
    parameter integer MAX_STEP_ANGLE     = 30
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
    input  logic              joy_done,
    output logic              pwm_pan,
    output logic              pwm_tilt
);

    logic signed [9:0] delta_x;
    logic signed [8:0] delta_y;
    logic              sel_done;
    logic              move_tick;
    logic        [7:0] angle_pan;
    logic        [7:0] angle_tilt;

    localparam integer MOVE_TICK_COUNT = CLK_HZ / MOVE_TICK_HZ;
    localparam integer MOVE_CNT_WIDTH  = $clog2(MOVE_TICK_COUNT);
    logic [MOVE_CNT_WIDTH-1:0] move_counter;

    ctrl_mode_mux u_ctrl_mode_mux (
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

    // Continue a saved long movement independently of new source updates.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            move_counter <= '0;
            move_tick    <= 1'b0;
        end else if (move_counter == MOVE_TICK_COUNT - 1) begin
            move_counter <= '0;
            move_tick    <= 1'b1;
        end else begin
            move_counter <= move_counter + 1'b1;
            move_tick    <= 1'b0;
        end
    end

    axis_ctrl #(
        .PAN_GAIN_NUM  (PAN_GAIN_NUM),
        .PAN_GAIN_DEN  (PAN_GAIN_DEN),
        .TILT_GAIN_NUM (TILT_GAIN_NUM),
        .TILT_GAIN_DEN (TILT_GAIN_DEN),
        .PAN_DEADZONE  (PAN_DEADZONE),
        .TILT_DEADZONE (TILT_DEADZONE),
        .MAX_STEP_ANGLE(MAX_STEP_ANGLE)
    ) u_axis_ctrl (
        .clk       (clk),
        .reset     (rst),
        .delta_x   (delta_x),
        .delta_y   (delta_y),
        .update    (sel_done),
        .move_tick (move_tick),
        .angle_pan (angle_pan),
        .angle_tilt(angle_tilt)
    );

    servo_pwm #(
        .CLK_HZ(CLK_HZ)
    ) u_servo_pwm_pan (
        .clk  (clk),
        .rst  (rst),
        .angle(angle_pan),
        .pwm  (pwm_pan)
    );

    servo_pwm #(
        .CLK_HZ(CLK_HZ)
    ) u_servo_pwm_tilt (
        .clk  (clk),
        .rst  (rst),
        .angle(angle_tilt),
        .pwm  (pwm_tilt)
    );

endmodule
