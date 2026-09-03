`timescale 1ns / 1ps

module coord_to_angle #(
    // angle = coordinate * GAIN_NUM / GAIN_DEN
    // Set these four parameters from camera measurement results.
    parameter integer PAN_GAIN_NUM  = 0,
    parameter integer PAN_GAIN_DEN  = 1,
    parameter integer TILT_GAIN_NUM = 0,
    parameter integer TILT_GAIN_DEN = 1,
    parameter integer PAN_DEADZONE  = 0,
    parameter integer TILT_DEADZONE = 0
) (
    input  logic signed [9:0] delta_x,
    input  logic signed [8:0] delta_y,
    output logic signed [9:0] pan_delta_angle,
    output logic signed [9:0] tilt_delta_angle
);

    logic signed [31:0] scaled_pan;
    logic signed [31:0] scaled_tilt;

    always_comb begin
        scaled_pan  = delta_x * PAN_GAIN_NUM;
        scaled_tilt = delta_y * TILT_GAIN_NUM;

        if (($signed(delta_x) >= -PAN_DEADZONE) &&
            ($signed(delta_x) <=  PAN_DEADZONE))
            pan_delta_angle = 10'sd0;
        else
            pan_delta_angle = scaled_pan / PAN_GAIN_DEN;

        if (($signed(delta_y) >= -TILT_DEADZONE) &&
            ($signed(delta_y) <=  TILT_DEADZONE))
            tilt_delta_angle = 10'sd0;
        else
            tilt_delta_angle = scaled_tilt / TILT_GAIN_DEN;
    end

endmodule
