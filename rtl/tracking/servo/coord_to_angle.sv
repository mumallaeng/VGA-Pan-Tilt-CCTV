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
    input                     clk,
    input                     rst,
    input  logic signed [9:0] delta_x,
    input  logic signed [8:0] delta_y,
    output logic signed [9:0] pan_delta_angle,
    output logic signed [9:0] tilt_delta_angle
);

    reg signed [9:0] pan_delta_angle_next;
    reg signed [9:0] tilt_delta_angle_next;

    logic signed [31:0] scaled_pan, scaled_pan_next;
    logic signed [31:0] scaled_tilt, scaled_tilt_next;

    always_comb begin
        scaled_pan_next  = delta_x * PAN_GAIN_NUM;
        scaled_tilt_next = delta_y * TILT_GAIN_NUM;

        if ((delta_x >= -PAN_DEADZONE) && (delta_x <= PAN_DEADZONE))
            pan_delta_angle_next = 10'sd0;
        else pan_delta_angle_next = scaled_pan / PAN_GAIN_DEN;

        if ((delta_y >= -TILT_DEADZONE) && (delta_y <= TILT_DEADZONE))
            tilt_delta_angle_next = 10'sd0;
        else tilt_delta_angle_next = scaled_tilt / TILT_GAIN_DEN;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scaled_pan       <= 32'sd0;
            scaled_tilt      <= 32'sd0;
            pan_delta_angle  <= 10'sd0;
            tilt_delta_angle <= 10'sd0;
        end else begin
            scaled_pan       <= scaled_pan_next;
            scaled_tilt      <= scaled_tilt_next;
            pan_delta_angle  <= pan_delta_angle_next;
            tilt_delta_angle <= tilt_delta_angle_next;
        end
    end

endmodule
