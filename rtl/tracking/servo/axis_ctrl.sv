`timescale 1ns / 1ps

// Applies the incoming delta straight to the commanded angle: one arriving
// value moves the servo once, by exactly what coord_to_angle asked for.
//
// There is no slew-rate limit and no stored target. A large delta lands in one
// step, so the mechanical rate limit is the servo's own speed rather than
// anything imposed here.
module axis_ctrl #(
    parameter integer PAN_DEADZONE  = 0,
    parameter integer TILT_DEADZONE = 0
) (
    input  logic              clk,
    input  logic              reset,
    input  logic signed [9:0] delta_x,
    input  logic signed [8:0] delta_y,
    input  logic              update,
    output logic        [7:0] angle_pan,
    output logic        [7:0] angle_tilt
);

    logic signed [                  16:0] requested_pan;
    logic signed [                  16:0] requested_tilt;
    (* mark_debug = "true" *) logic signed [9:0] pan_delta_angle;
    (* mark_debug = "true" *) logic signed [9:0] tilt_delta_angle;
    (* mark_debug = "true" *) logic              angle_valid;
    logic                                 angle_valid_d;
    logic                                 angle_apply;

    coord_to_angle #(
        .PAN_DEADZONE (PAN_DEADZONE),
        .TILT_DEADZONE(TILT_DEADZONE)
    ) u_coord_to_angle (
        .clk             (clk),
        .rst             (reset),
        .in_valid        (update),
        .delta_x         (delta_x),
        .delta_y         (delta_y),
        .out_valid       (angle_valid),
        .pan_delta_angle (pan_delta_angle),
        .tilt_delta_angle(tilt_delta_angle)
    );

    // update comes from ctrl_mode_mux, where the AUTO path passes frame_done
    // through as a level. That pulse belongs to the 25 MHz vga_pclk domain, so
    // it is four clk cycles wide here and angle_valid inherits that width.
    // Detecting the edge is what makes one frame move the servo once instead
    // of applying the same delta four times over.
    assign angle_apply = angle_valid & ~angle_valid_d;

    function automatic logic [7:0] clamp_angle(input logic signed [16:0] value);
        if (value > 17'sd180) clamp_angle = 8'd180;
        else if (value < 17'sd0) clamp_angle = 8'd0;
        else clamp_angle = value[7:0];
    endfunction

    always_comb begin
        // Subtracted, not added: the servos are mounted so that a rising angle
        // turns the camera away from a positive delta. Inverting here rather
        // than at the sensor keeps AUTO and MANUAL consistent, since both
        // arrive through delta_x/delta_y. Flip back to + if the brackets or
        // the servo wiring change.
        requested_pan  = $signed({9'b0, angle_pan}) - pan_delta_angle;
        requested_tilt = $signed({9'b0, angle_tilt}) - tilt_delta_angle;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            angle_pan     <= 8'd90;
            angle_tilt    <= 8'd90;
            angle_valid_d <= 1'b0;
        end else begin
            angle_valid_d <= angle_valid;

            if (angle_apply) begin
                angle_pan  <= clamp_angle(requested_pan);
                angle_tilt <= clamp_angle(requested_tilt);
            end
        end
    end

endmodule
