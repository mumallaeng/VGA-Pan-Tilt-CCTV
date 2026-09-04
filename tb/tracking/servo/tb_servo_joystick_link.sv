`timescale 1ns / 1ps

module tb_servo_joystick_link;
    logic clk = 1'b0;
    logic rst;
    logic signed [9:0] frame_dx;
    logic signed [8:0] frame_dy;
    logic frame_valid;
    logic frame_done;
    logic mode;
    logic signed [4:0] joy_dx;
    logic signed [4:0] joy_dy;
    logic joy_valid;
    logic joy_done;
    logic pwm_pan;
    logic pwm_tilt;
    integer errors = 0;
    time pwm_high_start;
    time pwm_high_width;

    always #5 clk = ~clk;

    servo_top #(
        .CLK_HZ(100_000_000),
        .MANUAL_CONTROL_HZ(10_000_000)
    ) dut (
        .clk(clk), .rst(rst),
        .frame_dx(frame_dx), .frame_dy(frame_dy),
        .frame_valid(frame_valid), .frame_done(frame_done),
        .mode(mode), .joy_dx(joy_dx), .joy_dy(joy_dy),
        .joy_valid(joy_valid), .joy_done(joy_done),
        .pwm_pan(pwm_pan), .pwm_tilt(pwm_tilt)
    );

    initial begin
        rst = 1'b1;
        frame_dx = '0;
        frame_dy = '0;
        frame_valid = 1'b0;
        frame_done = 1'b0;
        mode = 1'b1;
        joy_dx = 5'sd0;
        joy_dy = 5'sd0;
        joy_valid = 1'b0;
        joy_done = 1'b0;

        repeat (15) @(posedge clk);
        #1;
        if (dut.pan_angle !== 8'd90 || dut.tilt_angle !== 8'd90) begin
            errors = errors + 1;
            $error("reset angle failed: pan=%0d tilt=%0d",
                   dut.pan_angle, dut.tilt_angle);
        end

        @(negedge clk);
        rst = 1'b0;
        pwm_high_start = $time;
        @(negedge pwm_pan);
        pwm_high_width = $time - pwm_high_start;
        if (pwm_high_width < 1490000ns || pwm_high_width > 1510000ns) begin
            errors = errors + 1;
            $error("90-degree PWM width failed: got %0t, expected about 1.5 ms",
                   pwm_high_width);
        end

        @(negedge clk);
        joy_dx = 5'sd5;
        joy_dy = -5'sd5;
        joy_valid = 1'b1;
        joy_done = 1'b1;
        @(posedge clk);
        #1;
        joy_done = 1'b0;
        repeat (15) @(posedge clk);
        #1;
        if (dut.pan_angle !== 8'd120 || dut.tilt_angle !== 8'd68) begin
            errors = errors + 1;
            $error("positive/negative joystick move failed: pan=%0d tilt=%0d",
                   dut.pan_angle, dut.tilt_angle);
        end

        @(negedge clk);
        joy_dx = 5'sd0;
        joy_dy = 5'sd0;
        joy_done = 1'b1;
        @(posedge clk);
        #1;
        joy_done = 1'b0;
        repeat (15) @(posedge clk);
        #1;
        if (dut.pan_angle !== 8'd120 || dut.tilt_angle !== 8'd68) begin
            errors = errors + 1;
            $error("center hold failed: pan=%0d tilt=%0d",
                   dut.pan_angle, dut.tilt_angle);
        end

        @(negedge clk);
        joy_dx = -5'sd5;
        joy_dy = 5'sd5;
        joy_done = 1'b1;
        @(posedge clk);
        #1;
        joy_done = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        if (dut.pan_angle !== 8'd90 || dut.tilt_angle !== 8'd90) begin
            errors = errors + 1;
            $error("reverse joystick move failed: pan=%0d tilt=%0d",
                   dut.pan_angle, dut.tilt_angle);
        end

        if (errors == 0)
            $display("ALL SERVO-JOYSTICK LINK TESTS PASSED");
        else
            $fatal(1, "%0d servo-joystick link tests failed", errors);
        $finish;
    end
endmodule
