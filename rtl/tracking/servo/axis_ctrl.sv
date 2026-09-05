`timescale 1ns / 1ps

// Applies the incoming delta straight to the commanded angle: one arriving
// value moves the servo once, by exactly what coord_to_angle asked for.
//
// There is no slew-rate limit and no stored target. A large delta lands in one
// step, so the mechanical rate limit is the servo's own speed rather than
// anything imposed here.
module axis_ctrl #(
    parameter integer PAN_DEADZONE  = 0,
    parameter integer TILT_DEADZONE = 0,
    // Each pair must match the corresponding servo_pwm exactly. Clamping to a
    // wider range here is an integrator windup: the command keeps accumulating
    // past what the shaft can reach, nothing reports that saturation back into
    // the loop, and when the error finally reverses the servo stands still for
    // however long it takes the excess to unwind. servo_top passes one pair
    // per axis to both modules so they cannot drift apart.
    //
    // The limits are per axis because the two have different mechanical
    // travel: pan is base rotation with little to hit, while tilt swings the
    // camera into the bracket at both ends. They also have to be wide enough
    // for the job - at 0.1875 deg per pixel a target at the edge of the frame
    // is 30 deg off boresight, so a range narrower than about +-45 deg from
    // centre leaves edge targets permanently unreachable and parks the loop
    // against the rail.
    parameter integer PAN_ANGLE_MIN  = 15,
    parameter integer PAN_ANGLE_MAX  = 165,
    parameter integer TILT_ANGLE_MIN = 25,
    parameter integer TILT_ANGLE_MAX = 155
) (
    input  logic              clk,
    input  logic              reset,
    input  logic signed [9:0] delta_x,
    input  logic signed [8:0] delta_y,
    input  logic              update,
    output logic        [7:0] angle_pan,
    output logic        [7:0] angle_tilt
);

    // Park at the centre, pulled inside the limits in case they exclude 90.
    localparam integer PAN_RESET = (90 < PAN_ANGLE_MIN) ? PAN_ANGLE_MIN :
                                   (90 > PAN_ANGLE_MAX) ? PAN_ANGLE_MAX : 90;
    localparam integer TILT_RESET = (90 < TILT_ANGLE_MIN) ? TILT_ANGLE_MIN :
                                    (90 > TILT_ANGLE_MAX) ? TILT_ANGLE_MAX : 90;

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

    function automatic logic [7:0] clamp_angle(input logic signed [16:0] value,
                                               input integer lo,
                                               input integer hi);
        if (value > hi) clamp_angle = hi[7:0];
        else if (value < lo) clamp_angle = lo[7:0];
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
            angle_pan     <= PAN_RESET[7:0];
            angle_tilt    <= TILT_RESET[7:0];
            angle_valid_d <= 1'b0;
        end else begin
            angle_valid_d <= angle_valid;

            if (angle_apply) begin
                angle_pan  <= clamp_angle(requested_pan,
                                          PAN_ANGLE_MIN, PAN_ANGLE_MAX);
                angle_tilt <= clamp_angle(requested_tilt,
                                          TILT_ANGLE_MIN, TILT_ANGLE_MAX);
            end
        end
    end

endmodule
