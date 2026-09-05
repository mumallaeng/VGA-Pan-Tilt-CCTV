`timescale 1ns / 1ps

module ctrl_mode_mux #(
    parameter integer CLK_HZ = 100_000_000,
    // MANUAL is open loop - the operator is the feedback - so it can run as
    // fast as the servo accepts commands.
    parameter integer MANUAL_CONTROL_HZ = 50,
    // AUTO is closed loop, and the loop around it is slow: one frame to
    // detect (16.8 ms), the centre_error average, this tick, the servo_pwm
    // period boundary and the shaft's own travel add up to roughly 100 ms
    // before a command shows up in the next measurement. Commanding faster
    // than that issues the same error several times over before any of it is
    // observed, which is what drove the loop into the mechanical limits.
    parameter integer AUTO_CONTROL_HZ = 6
) (
    input  logic              clk,
    input  logic              rst,
    // 0: AUTO(frame), 1: MANUAL(joystick)
    input  logic              mode,
    input  logic signed [9:0] frame_dx,
    input  logic signed [8:0] frame_dy,
    input  logic              frame_valid,
    input  logic              frame_done,
    input  logic signed [4:0] joy_dx,
    input  logic signed [4:0] joy_dy,
    input  logic              joy_valid,
    input  logic              joy_done,
    output logic signed [9:0] delta_x,
    output logic signed [8:0] delta_y,
    output logic              sel_done
);

    logic signed [9:0] scaled_joy_dx;
    logic signed [8:0] scaled_joy_dy;
    logic signed [9:0] joy_dx_ext;
    logic signed [8:0] joy_dy_ext;
    localparam integer MANUAL_TICK_CYCLES = CLK_HZ / MANUAL_CONTROL_HZ;
    localparam integer MANUAL_COUNTER_WIDTH =
        (MANUAL_TICK_CYCLES <= 1) ? 1 : $clog2(MANUAL_TICK_CYCLES);
    localparam integer AUTO_TICK_CYCLES = CLK_HZ / AUTO_CONTROL_HZ;
    localparam integer AUTO_COUNTER_WIDTH =
        (AUTO_TICK_CYCLES <= 1) ? 1 : $clog2(AUTO_TICK_CYCLES);

    logic [MANUAL_COUNTER_WIDTH-1:0] manual_counter;
    logic [  AUTO_COUNTER_WIDTH-1:0] auto_counter;
    logic manual_tick;
    logic auto_tick;
    logic joystick_ready;

    // AUTO path, held to the same 50 Hz tick as MANUAL.
    //
    // A frame result cannot simply be ANDed with auto_tick: frame_done is a
    // vga_pclk pulse four clk cycles wide while auto_tick is one cycle in many
    // millions, so they would essentially never coincide. Instead a frame arms
    // frame_pending and the next tick releases it. Frames arrive at 59.5 Hz
    // and are consumed at AUTO_CONTROL_HZ, so most are superseded before their
    // tick, which is intended: the tick always acts on the newest result.
    // centroid_filter keeps frame_dx/frame_dy driven after the pulse
    // (rect_x_hold), so the data is still valid when the tick fires.
    logic frame_req, frame_req_d, frame_pulse;
    logic frame_pending;
    assign frame_req   = frame_done & frame_valid;
    assign frame_pulse = frame_req & ~frame_req_d;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            manual_counter <= '0;
            manual_tick    <= 1'b0;
            auto_counter   <= '0;
            auto_tick      <= 1'b0;
            joystick_ready <= 1'b0;
            frame_req_d    <= 1'b0;
            frame_pending  <= 1'b0;
        end else begin
            frame_req_d <= frame_req;

            // Consuming tick re-arms only if a frame lands on that same cycle.
            if (auto_tick && frame_pending) frame_pending <= frame_pulse;
            else if (frame_pulse) frame_pending <= 1'b1;

            if (MANUAL_TICK_CYCLES <= 1) begin
                manual_counter <= '0;
                manual_tick    <= 1'b1;
            end else if (manual_counter == MANUAL_TICK_CYCLES - 1) begin
                manual_counter <= '0;
                manual_tick    <= 1'b1;
            end else begin
                manual_counter <= manual_counter + 1'b1;
                manual_tick    <= 1'b0;
            end

            if (AUTO_TICK_CYCLES <= 1) begin
                auto_counter <= '0;
                auto_tick    <= 1'b1;
            end else if (auto_counter == AUTO_TICK_CYCLES - 1) begin
                auto_counter <= '0;
                auto_tick    <= 1'b1;
            end else begin
                auto_counter <= auto_counter + 1'b1;
                auto_tick    <= 1'b0;
            end

            if (joy_done && joy_valid) joystick_ready <= 1'b1;
        end
    end

    assign joy_dx_ext = joy_dx;
    assign joy_dy_ext = joy_dy;

    // Passed through unscaled. coord_to_angle now applies 5/16 deg per count,
    // so full joystick deflection (+-10) is about 3 deg per tick; at 50 Hz
    // that is ~150 deg/s, which the servo can actually follow. The old <<< 1
    // was there to compensate for the smaller 2/16 gain.
    assign scaled_joy_dx = joy_dx_ext;
    assign scaled_joy_dy = joy_dy_ext;

    assign delta_x = mode ? scaled_joy_dx : frame_dx;
    assign delta_y = mode ? scaled_joy_dy : frame_dy;
    // joy_done reports that fresh joystick data arrived. joy_dx/y retain that
    // data, while manual_tick limits actual servo commands to MANUAL_CONTROL_HZ.
    // BISECT (temp): joystick_ready dropped from manual-mode gate.
    assign sel_done = mode ? manual_tick : (auto_tick & frame_pending);

endmodule
