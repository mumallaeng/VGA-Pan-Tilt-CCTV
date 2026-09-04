`timescale 1ns / 1ps

// Integration testbench: ctrl_mode_mux -> axis_ctrl, wired the same way
// servo_top connects them (sel_done drives update). MANUAL mode is used
// throughout, with joy_dx/joy_dy constrained to the -10..10 range.
module tb_ctrl_mode_mux_axis_ctrl;

    localparam time CLK_PERIOD = 10ns;

    logic clk = 1'b0;
    logic reset;

    // ctrl_mode_mux inputs
    logic              mode;
    logic signed [9:0] frame_dx;
    logic signed [8:0] frame_dy;
    logic              frame_valid;
    logic              frame_done;
    logic signed [4:0] joy_dx;
    logic signed [4:0] joy_dy;

    // ctrl_mode_mux -> axis_ctrl
    logic signed [9:0] delta_x;
    logic signed [8:0] delta_y;
    logic              sel_done;

    // axis_ctrl outputs
    logic [7:0] angle_pan;
    logic [7:0] angle_tilt;

    int test_count  = 0;
    int error_count = 0;

    always #(CLK_PERIOD / 2) clk = ~clk;

    ctrl_mode_mux u_ctrl_mode_mux (
        .mode       (mode),
        .frame_dx   (frame_dx),
        .frame_dy   (frame_dy),
        .frame_valid(frame_valid),
        .frame_done (frame_done),
        .joy_dx     (joy_dx),
        .joy_dy     (joy_dy),
        .delta_x    (delta_x),
        .delta_y    (delta_y),
        .sel_done   (sel_done)
    );

    axis_ctrl #(
        .CLK_HZ        (100_000_000),  // matches CLK_PERIOD = 10ns
        .MOVE_TICK_HZ  (50),           // SG90 PWM refresh: 20ms period
        .PAN_DEADZONE  (0),
        .TILT_DEADZONE (0),
        .MAX_STEP_ANGLE(30)
    ) dut (
        .clk       (clk),
        .reset     (reset),
        .delta_x   (delta_x),
        .delta_y   (delta_y),
        .update    (sel_done),
        .angle_pan (angle_pan),
        .angle_tilt(angle_tilt)
    );

    // MANUAL mode selects joy_dx/joy_dy at all times, so sel_done must stay
    // asserted and the frame_* path must stay unused.
    always @(posedge clk) begin
        if (!reset) begin
            if (sel_done !== 1'b1) begin
                error_count++;
                $error("sel_done deasserted while mode=MANUAL (t=%0t)", $time);
            end
            if ((angle_pan > 8'd180) || (angle_tilt > 8'd180)) begin
                error_count++;
                $error("Angle out of the 0..180 servo range: pan=%0d tilt=%0d (t=%0t)",
                        angle_pan, angle_tilt, $time);
            end
        end
    end

    task automatic check_angles(
        input logic [7:0] expected_pan,
        input logic [7:0] expected_tilt,
        input string      test_name
    );
        test_count++;
        if ((angle_pan !== expected_pan) || (angle_tilt !== expected_tilt)) begin
            error_count++;
            $error("%s: expected pan=%0d tilt=%0d, got pan=%0d tilt=%0d",
                   test_name, expected_pan, expected_tilt,
                   angle_pan, angle_tilt);
        end else begin
            $display("PASS: %s (pan=%0d, tilt=%0d)",
                     test_name, angle_pan, angle_tilt);
        end
    endtask

    // Drives a joystick vector, clamped to -10..10, and holds it while the
    // target keeps converging (or until max_cycles elapse), then checks the
    // final pan/tilt angle.
    task automatic drive_joy_until(
        input logic signed [4:0] dx,
        input logic signed [4:0] dy,
        input logic        [7:0] expected_pan,
        input logic        [7:0] expected_tilt,
        input int                max_cycles,
        input string              test_name
    );
        int cycles;
        begin
            if ((dx < -5'sd10) || (dx > 5'sd10) || (dy < -5'sd10) || (dy > 5'sd10))
                $error("%s: joystick request dx=%0d dy=%0d outside -10..10", test_name, dx, dy);

            @(negedge clk);
            joy_dx = dx;
            joy_dy = dy;

            cycles = 0;
            while (((angle_pan !== expected_pan) || (angle_tilt !== expected_tilt)) &&
                   (cycles < max_cycles)) begin
                @(posedge clk);
                #1;
                cycles++;
            end
            check_angles(expected_pan, expected_tilt, test_name);
        end
    endtask

    task automatic apply_reset;
        #2 reset = 1'b1;
        #1;
        reset = 1'b0;
    endtask

    initial begin
        reset       = 1'b0;
        mode        = 1'b1;  // MANUAL: ctrl_mode_mux selects joy_dx/joy_dy
        frame_dx    = '0;
        frame_dy    = '0;
        frame_valid = 1'b0;
        frame_done  = 1'b0;
        joy_dx      = '0;
        joy_dy      = '0;

        apply_reset();
        check_angles(8'd90, 8'd90, "reset initializes both axes");

        // Directed: full positive pan deflection saturates at 180.
        drive_joy_until(5'sd10, 5'sd0, 8'd180, 8'd90, 20,
                         "joy_dx=+10 saturates pan at 180");

        // Directed: full negative pan deflection returns to 0.
        drive_joy_until(-5'sd10, 5'sd0, 8'd0, 8'd90, 20,
                         "joy_dx=-10 saturates pan at 0");

        // Directed: full positive tilt deflection saturates at 180.
        drive_joy_until(5'sd0, 5'sd10, 8'd0, 8'd180, 20,
                         "joy_dy=+10 saturates tilt at 180");

        // Directed: full negative tilt deflection returns to 0.
        drive_joy_until(5'sd0, -5'sd10, 8'd0, 8'd0, 20,
                         "joy_dy=-10 saturates tilt at 0");

        // Directed: zero deflection holds the current angles.
        drive_joy_until(5'sd0, 5'sd0, 8'd0, 8'd0, 5,
                         "joy_dx=joy_dy=0 holds position");

        // Random smoke test: joy_dx/joy_dy always within -10..10; the
        // per-cycle monitor above enforces the 0..180 servo bound and that
        // sel_done stays high for the whole run.
        for (int i = 0; i < 30; i++) begin
            automatic logic signed [4:0] rdx = $urandom_range(20) - 10;
            automatic logic signed [4:0] rdy = $urandom_range(20) - 10;
            @(negedge clk);
            joy_dx = rdx;
            joy_dy = rdy;
            repeat ($urandom_range(4) + 1) @(posedge clk);
        end
        #1;
        test_count++;
        $display("PASS: random -10..10 joystick sweep completed without bound violations");

        if (error_count == 0)
            $display("ALL %0d TESTS PASSED", test_count);
        else
            $fatal(1, "%0d of %0d tests failed", error_count, test_count);

        $finish;
    end

endmodule