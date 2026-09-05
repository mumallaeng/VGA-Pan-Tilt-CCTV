`timescale 1ns / 1ps

module coord_to_angle #(
    parameter integer PAN_DEADZONE  = 0,
    parameter integer TILT_DEADZONE = 0,
    // Largest angle one command may ask for. This is a rate limit, not a
    // travel limit: axis_ctrl accumulates, so the real ceiling is
    // MAX_STEP_DEG * AUTO_CONTROL_HZ. At 20 deg and 6 Hz that is 120 deg/s,
    // comfortably inside what a loaded SG90 manages (~300 deg/s), where the
    // old 10 deg at 50 Hz asked for 500 deg/s and the shaft simply fell
    // behind the command.
    parameter integer MAX_STEP_DEG  = 20
) (
    input  logic              clk,
    input  logic              rst,
    input  logic              in_valid,
    input  logic signed [9:0] delta_x,
    input  logic signed [8:0] delta_y,
    output logic              out_valid,
    output logic signed [9:0] pan_delta_angle,
    output logic signed [9:0] tilt_delta_angle
);

    logic signed [10:0] delta_x_ext;
    logic signed [10:0] delta_y_ext;
    // Three bits wider than delta_*_ext so the x5 gain cannot overflow at the
    // extremes of the input range (+-511 * 5 = +-2555 needs 13 bits signed).
    logic signed [13:0] scaled_pan_r;
    logic signed [13:0] scaled_tilt_r;
    logic               pan_deadzone_r;
    logic               tilt_deadzone_r;
    logic               stage1_valid_r;

    // Saturate the per-frame command. Values below the limit pass untouched,
    // so a 1 or 2 degree correction still gets through unchanged.
    function automatic logic signed [9:0] limit_step(input logic signed [13:0] value);
        if (value > MAX_STEP_DEG) limit_step = MAX_STEP_DEG[9:0];
        else if (value < -MAX_STEP_DEG) limit_step = -MAX_STEP_DEG[9:0];
        else limit_step = value[9:0];
    endfunction

    assign delta_x_ext = delta_x;
    assign delta_y_ext = delta_y;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scaled_pan_r     <= 12'sd0;
            scaled_tilt_r    <= 12'sd0;
            pan_deadzone_r   <= 1'b0;
            tilt_deadzone_r  <= 1'b0;
            stage1_valid_r   <= 1'b0;
            out_valid        <= 1'b0;
            pan_delta_angle  <= 10'sd0;
            tilt_delta_angle <= 10'sd0;
        end else begin
            stage1_valid_r <= in_valid;
            out_valid      <= stage1_valid_r;

            if (in_valid) begin
                // Gain is 5/16 deg per pixel: multiply by 5 here, divide by
                // 16 in stage 2. The geometric value is 3/16 (60 deg over
                // 320 px), so this is deliberately above deadbeat - what
                // stabilises the loop is the slow AUTO tick, not a small
                // gain, and once a command is allowed to finish before the
                // next one is issued the extra gain buys back the settling
                // time the slow tick costs. It also drops the truncation
                // dead zone from |dx| < 8 px to |dx| < 4 px.
                scaled_pan_r  <= (delta_x_ext <<< 2) + delta_x_ext;
                scaled_tilt_r <= (delta_y_ext <<< 2) + delta_y_ext;
                pan_deadzone_r <=
                    (delta_x >= -PAN_DEADZONE) &&
                    (delta_x <=  PAN_DEADZONE);
                tilt_deadzone_r <=
                    (delta_y >= -TILT_DEADZONE) &&
                    (delta_y <=  TILT_DEADZONE);
            end

            if (stage1_valid_r) begin
                if (pan_deadzone_r) pan_delta_angle <= 10'sd0;
                else if (scaled_pan_r < 0)
                    pan_delta_angle <= limit_step((scaled_pan_r + 14'sd15) >>> 4);
                else pan_delta_angle <= limit_step(scaled_pan_r >>> 4);

                if (tilt_deadzone_r) tilt_delta_angle <= 10'sd0;
                else if (scaled_tilt_r < 0)
                    tilt_delta_angle <= limit_step((scaled_tilt_r + 14'sd15) >>> 4);
                else tilt_delta_angle <= limit_step(scaled_tilt_r >>> 4);
            end
        end
    end

endmodule
