`timescale 1ns / 1ps

// Standalone axis-control calibration top using the existing Basys 3 switch,
// LED, and servo PWM constraints.
module servo_cal #(
    parameter integer CLK_HZ = 100_000_000,
    // Default 500 ms between consecutive 30-degree motion steps so each
    // intermediate position can be observed during calibration.
    parameter integer MOVE_INTERVAL_CYCLES = CLK_HZ / 2
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [15:0] sw,
    output logic        JA4,
    output logic        JA10,
    output logic [15:0] led
);

    localparam integer MOVE_COUNTER_WIDTH =
        (MOVE_INTERVAL_CYCLES <= 1) ? 1 : $clog2(MOVE_INTERVAL_CYCLES);

    logic [15:0] sw_meta;
    logic [15:0] sw_sync;
    logic        apply_toggle_d;
    logic        update;
    logic [7:0]  selected_angle;
    logic signed [9:0] delta_x;
    logic signed [8:0] delta_y;
    logic [7:0]  angle_pan;
    logic [7:0]  angle_tilt;
    logic [MOVE_COUNTER_WIDTH-1:0] move_counter;
    logic        move_tick;

    // SW1..SW5 select 30, 50, 80, 100, and 130 degrees respectively.
    // If several are on, the highest-numbered switch has priority.
    always_comb begin
        if (sw_sync[5])
            selected_angle = 8'd130;
        else if (sw_sync[4])
            selected_angle = 8'd100;
        else if (sw_sync[3])
            selected_angle = 8'd80;
        else if (sw_sync[2])
            selected_angle = 8'd50;
        else if (sw_sync[1])
            selected_angle = 8'd30;
        else
            selected_angle = 8'd90;

        // SW14 selects the axis: 0=Pan, 1=Tilt. The selected absolute test
        // angle is converted to a signed difference from the current angle.
        delta_x = 10'sd0;
        delta_y = 9'sd0;
        if (sw_sync[14])
            delta_y = $signed({1'b0, selected_angle})
                    - $signed({1'b0, angle_tilt});
        else
            delta_x = $signed({1'b0, selected_angle})
                    - $signed({1'b0, angle_pan});
    end

    // Synchronize all physical switches. Toggling SW15 applies the selected
    // target once; both rising and falling changes generate one update pulse.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sw_meta        <= 16'd0;
            sw_sync        <= 16'd0;
            apply_toggle_d <= 1'b0;
        end else begin
            sw_meta        <= sw;
            sw_sync        <= sw_meta;
            apply_toggle_d <= sw_sync[15];
        end
    end

    assign update = sw_sync[15] ^ apply_toggle_d;
    assign led    = sw_sync;

    // Generate a clock-enable pulse for each following 30-degree step.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            move_counter <= '0;
            move_tick    <= 1'b0;
        end else if (MOVE_INTERVAL_CYCLES <= 1) begin
            move_counter <= '0;
            move_tick    <= 1'b1;
        end else if (move_counter == MOVE_INTERVAL_CYCLES - 1) begin
            move_counter <= '0;
            move_tick    <= 1'b1;
        end else begin
            move_counter <= move_counter + 1'b1;
            move_tick    <= 1'b0;
        end
    end

    // Identity gain is intentional in this calibration top: delta_x/y above
    // already represent the angle difference to the selected test target.
    axis_ctrl #(
        .PAN_GAIN_NUM  (1),
        .PAN_GAIN_DEN  (1),
        .TILT_GAIN_NUM (1),
        .TILT_GAIN_DEN (1),
        .MAX_STEP_ANGLE(30)
    ) u_axis_ctrl (
        .clk       (clk),
        .reset     (rst),
        .delta_x   (delta_x),
        .delta_y   (delta_y),
        .update    (update),
        .move_tick (move_tick),
        .angle_pan (angle_pan),
        .angle_tilt(angle_tilt)
    );

    servo_pwm #(.CLK_HZ(CLK_HZ)) u_pwm_tilt (
        .clk(clk), .rst(rst), .angle(angle_tilt), .pwm(JA4)
    );

    servo_pwm #(.CLK_HZ(CLK_HZ)) u_pwm_pan (
        .clk(clk), .rst(rst), .angle(angle_pan), .pwm(JA10)
    );

endmodule
