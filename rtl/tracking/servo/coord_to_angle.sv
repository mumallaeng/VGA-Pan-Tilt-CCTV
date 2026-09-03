`timescale 1ns / 1ps

module coord_to_angle #(
    parameter integer PAN_DEADZONE  = 0,
    parameter integer TILT_DEADZONE = 0
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
    logic signed [10:0] scaled_pan_r;
    logic signed [10:0] scaled_tilt_r;
    logic               pan_deadzone_r;
    logic               tilt_deadzone_r;
    logic               stage1_valid_r;

    assign delta_x_ext = delta_x;
    assign delta_y_ext = delta_y;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scaled_pan_r     <= 11'sd0;
            scaled_tilt_r    <= 11'sd0;
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
                // 60/320 = 45/240 = 3/16: multiply by 3 in stage 1.
                scaled_pan_r <= (delta_x_ext <<< 1) + delta_x_ext;
                scaled_tilt_r <= (delta_y_ext <<< 1) + delta_y_ext;
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
                    pan_delta_angle <= (scaled_pan_r + 11'sd15) >>> 4;
                else pan_delta_angle <= scaled_pan_r >>> 4;

                if (tilt_deadzone_r) tilt_delta_angle <= 10'sd0;
                else if (scaled_tilt_r < 0)
                    tilt_delta_angle <= (scaled_tilt_r + 11'sd15) >>> 4;
                else tilt_delta_angle <= scaled_tilt_r >>> 4;
            end
        end
    end

endmodule
