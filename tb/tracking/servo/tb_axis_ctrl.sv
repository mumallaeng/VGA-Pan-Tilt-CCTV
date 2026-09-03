`timescale 1ns / 1ps

module tb_axis_ctrl;

    localparam time CLK_PERIOD = 20ns;

    logic clk = 1'b0;
    logic reset;
    logic signed [9:0] delta_x;
    logic signed [8:0] delta_y;
    logic update;
    logic [7:0] angle_pan;
    logic [7:0] angle_tilt;

    int test_count  = 0;
    int error_count = 0;

    always #(CLK_PERIOD / 2) clk = ~clk;

    axis_ctrl #(
        .CLK_HZ(1),
        .MOVE_TICK_HZ(1),
        .PAN_GAIN_NUM(1),
        .PAN_GAIN_DEN(1),
        .TILT_GAIN_NUM(1),
        .TILT_GAIN_DEN(1),
        .MAX_STEP_ANGLE(30)
    ) dut (
        .clk       (clk),
        .reset     (reset),
        .delta_x   (delta_x),
        .delta_y   (delta_y),
        .update    (update),
        .angle_pan (angle_pan),
        .angle_tilt(angle_tilt)
    );

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

    task automatic apply_request(
        input logic signed [9:0] dx,
        input logic signed [8:0] dy
    );
        @(negedge clk);
        delta_x = dx;
        delta_y = dy;
        update   = 1'b1;
        @(posedge clk);
        #1 update = 1'b0;
    endtask

    task automatic advance_step;
        @(posedge clk);
        #1;
    endtask

    task automatic apply_reset;
        #2 reset = 1'b1;
        #1;
        reset = 1'b0;
    endtask

    initial begin
        reset     = 1'b0;
        delta_x = '0;
        delta_y = '0;
        update    = 1'b0;

        apply_reset();
        check_angles(8'd90, 8'd90, "reset initializes both axes");

        // A 40-degree request must retain its final 10-degree remainder.
        apply_request(10'sd40, 9'sd0);
        check_angles(8'd120, 8'd90, "40-degree request: first 30");
        advance_step();
        check_angles(8'd130, 8'd90, "40-degree request: final 10");

        // Return Pan to zero in three 30-degree steps.
        apply_request(-10'sd130, 9'sd0);
        check_angles(8'd100, 8'd90, "negative request: first 30");
        advance_step();
        check_angles(8'd70, 8'd90, "negative request: second 30");
        advance_step();
        check_angles(8'd40, 8'd90, "negative request: third 30");
        advance_step();
        check_angles(8'd10, 8'd90, "negative request: fourth 30");
        advance_step();
        check_angles(8'd0, 8'd90, "negative request: final 10");

        // Exact requested sequence: 130 = 30+30+30+30+10.
        apply_request(10'sd130, 9'sd0);
        check_angles(8'd30, 8'd90, "130-degree request: first 30");
        advance_step();
        check_angles(8'd60, 8'd90, "130-degree request: second 30");
        advance_step();
        check_angles(8'd90, 8'd90, "130-degree request: third 30");
        advance_step();
        check_angles(8'd120, 8'd90, "130-degree request: fourth 30");
        advance_step();
        check_angles(8'd130, 8'd90, "130-degree request: final 10");

        // Below is negative and above is positive for the Y coordinate.
        apply_request(10'sd0, -9'sd40);
        check_angles(8'd130, 8'd60, "Y below moves in negative direction");
        advance_step();
        check_angles(8'd130, 8'd50, "Y negative final remainder");
        apply_request(10'sd0, 9'sd70);
        check_angles(8'd130, 8'd80, "Y above moves in positive direction");
        advance_step();
        check_angles(8'd130, 8'd110, "Y positive second step");
        advance_step();
        check_angles(8'd130, 8'd120, "Y positive final remainder");

        // Once the target is reached, internal movement ticks hold the angle.
        repeat (3) @(posedge clk);
        #1 check_angles(8'd130, 8'd120, "idle cycles hold current angles");

        // Target generation remains bounded to the servo's 0..180 range.
        apply_request(10'sd400, 9'sd0);
        advance_step();
        check_angles(8'd180, 8'd120, "upper target saturation");

        if (error_count == 0)
            $display("ALL %0d TESTS PASSED", test_count);
        else
            $fatal(1, "%0d of %0d tests failed", error_count, test_count);

        $finish;
    end

endmodule
