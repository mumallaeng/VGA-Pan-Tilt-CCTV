`timescale 1ns / 1ps

module coord_to_angle #(
    parameter integer PAN_DEADZONE  = 0,
    parameter integer TILT_DEADZONE = 0,
    // Largest angle one frame may command. Capping the result rather than
    // lowering the gain keeps small errors responsive: at 2/16 deg per pixel
    // an 8 px error still moves 1 deg and 16 px still moves 2 deg, while a
    // full-width error is held to MAX_STEP_DEG instead of 20.
    parameter integer MAX_STEP_DEG  = 10
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
    // One bit wider than delta_*_ext so the x2 gain cannot overflow at the
    // extremes of the input range.
    logic signed [11:0] scaled_pan_r;
    logic signed [11:0] scaled_tilt_r;
    logic               pan_deadzone_r;
    logic               tilt_deadzone_r;
    logic               stage1_valid_r;

    // Saturate the per-frame command. Values below the limit pass untouched,
    // so a 1 or 2 degree correction still gets through unchanged.
    function automatic logic signed [9:0] limit_step(input logic signed [11:0] value);
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
                // Gain is 2/16 deg per pixel: multiply by 2 here, divide by
                // 16 in stage 2. The geometric value would be 3/16 (60 deg
                // over 320 px), but that commands the whole observed error
                // every frame while the servo needs several frames to get
                // there, so the command winds up past the target. Two thirds
                // of it keeps the response quick without that.
                scaled_pan_r  <= delta_x_ext <<< 1;
                scaled_tilt_r <= delta_y_ext <<< 1;
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
                    pan_delta_angle <= limit_step((scaled_pan_r + 12'sd15) >>> 4);
                else pan_delta_angle <= limit_step(scaled_pan_r >>> 4);

                if (tilt_deadzone_r) tilt_delta_angle <= 10'sd0;
                else if (scaled_tilt_r < 0)
                    tilt_delta_angle <= limit_step((scaled_tilt_r + 12'sd15) >>> 4);
                else tilt_delta_angle <= limit_step(scaled_tilt_r >>> 4);
            end
        end
    end

endmodule
