`timescale 1ns / 1ps

module ctrl_mode_mux #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer MANUAL_CONTROL_HZ = 50
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
    (* mark_debug = "true" *) output logic       sel_done
);

    logic signed [9:0] scaled_joy_dx;
    logic signed [8:0] scaled_joy_dy;
    logic signed [9:0] joy_dx_ext;
    logic signed [8:0] joy_dy_ext;
    localparam integer CONTROL_TICK_CYCLES = CLK_HZ / MANUAL_CONTROL_HZ;
    localparam integer CONTROL_COUNTER_WIDTH =
        (CONTROL_TICK_CYCLES <= 1) ? 1 : $clog2(CONTROL_TICK_CYCLES);
    logic [CONTROL_COUNTER_WIDTH-1:0] control_counter;
    (* mark_debug = "true" *) logic control_tick;
    (* mark_debug = "true" *) logic joystick_ready;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            control_counter <= '0;
            control_tick    <= 1'b0;
            joystick_ready  <= 1'b0;
        end else begin
            if (CONTROL_TICK_CYCLES <= 1) begin
                control_counter <= '0;
                control_tick    <= 1'b1;
            end else if (control_counter == CONTROL_TICK_CYCLES - 1) begin
                control_counter <= '0;
                control_tick    <= 1'b1;
            end else begin
                control_counter <= control_counter + 1'b1;
                control_tick    <= 1'b0;
            end

            if (joy_done && joy_valid)
                joystick_ready <= 1'b1;
        end
    end

    assign joy_dx_ext = joy_dx;
    assign joy_dy_ext = joy_dy;

    assign scaled_joy_dx = joy_dx_ext <<< 1;  // gain: joy_dx*2 (coord_to_angle adds *3/16)
    assign scaled_joy_dy = joy_dy_ext <<< 1;  // gain: joy_dy*2

    assign delta_x = mode ? scaled_joy_dx : frame_dx;
    assign delta_y = mode ? scaled_joy_dy : frame_dy;
    // joy_done reports that fresh joystick data arrived. joy_dx/y retain that
    // data, while control_tick limits actual servo commands to 50 Hz.
    // BISECT (temp): joystick_ready dropped from manual-mode gate.
    assign sel_done = mode ? control_tick
                           : (frame_done & frame_valid);

endmodule
