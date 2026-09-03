`timescale 1ns / 1ps

module axis_ctrl #(
    parameter integer PAN_GAIN_NUM    = 1,
    parameter integer PAN_GAIN_DEN    = 1,
    parameter integer TILT_GAIN_NUM   = 1,
    parameter integer TILT_GAIN_DEN   = 1,
    parameter integer PAN_DEADZONE    = 0,
    parameter integer TILT_DEADZONE   = 0,
    parameter integer MAX_STEP_ANGLE = 30
) (
    input  logic              clk,
    input  logic              reset,
    input  logic signed [9:0] delta_x,
    input  logic signed [8:0] delta_y,
    input  logic              update,
    input  logic              move_tick,
    output logic        [7:0] angle_pan,
    output logic        [7:0] angle_tilt
);

    localparam logic signed [16:0] MAX_STEP = MAX_STEP_ANGLE;

    logic        [7:0] target_pan;
    logic        [7:0] target_tilt;
    logic signed [16:0] requested_pan;
    logic signed [16:0] requested_tilt;
    logic        [7:0] new_target_pan;
    logic        [7:0] new_target_tilt;
    logic        [7:0] step_to_new_pan;
    logic        [7:0] step_to_new_tilt;
    logic        [7:0] step_to_target_pan;
    logic        [7:0] step_to_target_tilt;
    logic signed [9:0] pan_delta_angle;
    logic signed [9:0] tilt_delta_angle;

    coord_to_angle #(
        .PAN_GAIN_NUM  (PAN_GAIN_NUM),
        .PAN_GAIN_DEN  (PAN_GAIN_DEN),
        .TILT_GAIN_NUM (TILT_GAIN_NUM),
        .TILT_GAIN_DEN (TILT_GAIN_DEN),
        .PAN_DEADZONE  (PAN_DEADZONE),
        .TILT_DEADZONE (TILT_DEADZONE)
    ) u_coord_to_angle (
        .delta_x         (delta_x),
        .delta_y         (delta_y),
        .pan_delta_angle (pan_delta_angle),
        .tilt_delta_angle(tilt_delta_angle)
    );

    function automatic logic [7:0] clamp_angle(
        input logic signed [16:0] value
    );
        if (value > 17'sd180)
            clamp_angle = 8'd180;
        else if (value < 17'sd0)
            clamp_angle = 8'd0;
        else
            clamp_angle = value[7:0];
    endfunction

    function automatic logic [7:0] move_toward_target(
        input logic [7:0] current_angle,
        input logic [7:0] target_angle
    );
        logic signed [8:0] remaining;
        begin
            remaining = $signed({1'b0, target_angle})
                      - $signed({1'b0, current_angle});

            if (remaining > MAX_STEP)
                move_toward_target = current_angle + MAX_STEP_ANGLE;
            else if (remaining < -MAX_STEP)
                move_toward_target = current_angle - MAX_STEP_ANGLE;
            else
                // Apply the final remainder even when it is below 30 degrees.
                move_toward_target = target_angle;
        end
    endfunction

    always_comb begin
        requested_pan  = $signed({9'b0, angle_pan}) + pan_delta_angle;
        requested_tilt = $signed({9'b0, angle_tilt}) + tilt_delta_angle;
        new_target_pan  = clamp_angle(requested_pan);
        new_target_tilt = clamp_angle(requested_tilt);

        // update stores the complete target and applies the first step on the
        // same edge. Later move_tick pulses continue toward the saved target.
        step_to_new_pan     = move_toward_target(angle_pan, new_target_pan);
        step_to_new_tilt    = move_toward_target(angle_tilt, new_target_tilt);
        step_to_target_pan  = move_toward_target(angle_pan, target_pan);
        step_to_target_tilt = move_toward_target(angle_tilt, target_tilt);
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            target_pan  <= 8'd90;
            target_tilt <= 8'd90;
            angle_pan   <= 8'd90;
            angle_tilt  <= 8'd90;
        end else if (update) begin
            target_pan  <= new_target_pan;
            target_tilt <= new_target_tilt;
            angle_pan   <= step_to_new_pan;
            angle_tilt  <= step_to_new_tilt;
        end else if (move_tick) begin
            angle_pan  <= step_to_target_pan;
            angle_tilt <= step_to_target_tilt;
        end
    end

endmodule
