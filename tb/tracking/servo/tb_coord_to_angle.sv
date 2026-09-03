`timescale 1ns / 1ps

module tb_coord_to_angle;
    logic signed [9:0] delta_x;
    logic signed [8:0] delta_y;
    logic signed [9:0] pan_delta_angle;
    logic signed [9:0] tilt_delta_angle;
    int errors = 0;

    // Measurement example only: HFOV=60 degrees, VFOV=45 degrees.
    // Replace these parameters with measured values later.
    coord_to_angle #(
        .PAN_GAIN_NUM(60),
        .PAN_GAIN_DEN(320),
        .TILT_GAIN_NUM(45),
        .TILT_GAIN_DEN(240),
        .PAN_DEADZONE(0),
        .TILT_DEADZONE(0)
    ) dut (.*);

    task automatic check(
        input logic signed [9:0] x,
        input logic signed [8:0] y,
        input logic signed [9:0] expected_pan,
        input logic signed [9:0] expected_tilt
    );
        delta_x = x;
        delta_y = y;
        #1;
        if ((pan_delta_angle !== expected_pan) ||
            (tilt_delta_angle !== expected_tilt)) begin
            errors++;
            $error("x=%0d y=%0d: expected pan=%0d tilt=%0d, got pan=%0d tilt=%0d",
                   x, y, expected_pan, expected_tilt,
                   pan_delta_angle, tilt_delta_angle);
        end else begin
            $display("PASS: x=%0d y=%0d -> pan=%0d tilt=%0d",
                     x, y, pan_delta_angle, tilt_delta_angle);
        end
    endtask

    initial begin
        check( 10'sd0,    9'sd0,    10'sd0,    10'sd0);
        check( 10'sd160,  9'sd120,  10'sd30,   10'sd22);
        check(-10'sd160, -9'sd120, -10'sd30,  -10'sd22);
        check( 10'sd80,   9'sd60,   10'sd15,   10'sd11);
        check(-10'sd40,   9'sd40,  -10'sd7,    10'sd7);

        if (errors == 0)
            $display("ALL COORD_TO_ANGLE TESTS PASSED");
        else
            $fatal(1, "%0d coord_to_angle tests failed", errors);
        $finish;
    end
endmodule
