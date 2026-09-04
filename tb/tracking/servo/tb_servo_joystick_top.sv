`timescale 1ns / 1ps

// Simulation model for the vendor XADC Wizard only. All project-owned
// joystick RTL is compiled from the real source files.
module xadc_wiz_0 (
    input logic dclk_in, input logic reset_in,
    input logic vauxp6, input logic vauxn6,
    input logic vauxp14, input logic vauxn14,
    output logic [4:0] channel_out,
    output logic [15:0] do_out,
    output logic drdy_out,
    input logic [15:0] di_in,
    input logic [6:0] daddr_in,
    output logic eoc_out,
    input logic den_in, input logic dwe_in,
    input logic vp_in, input logic vn_in,
    output logic alarm_out, output logic eos_out, output logic busy_out
);
    logic [1:0] phase;
    logic [11:0] x_sample, y_sample;

    always_comb begin
        if (vauxp6) x_sample = 12'd900;
        else if (vauxn6) x_sample = 12'd100;
        else x_sample = 12'd500;
        if (vauxp14) y_sample = 12'd900;
        else if (vauxn14) y_sample = 12'd100;
        else y_sample = 12'd485;
    end

    always_ff @(posedge dclk_in or posedge reset_in) begin
        if (reset_in) begin
            phase <= 2'd0; channel_out <= 5'h16; do_out <= 16'd0;
            drdy_out <= 1'b0; eoc_out <= 1'b0; eos_out <= 1'b0;
            alarm_out <= 1'b0; busy_out <= 1'b0;
        end else begin
            phase <= phase + 1'b1;
            drdy_out <= 1'b0; eoc_out <= 1'b0; eos_out <= 1'b0;
            case (phase)
                2'd0: begin channel_out <= 5'h16; eoc_out <= 1'b1; end
                2'd1: begin do_out <= {x_sample, 4'b0000}; drdy_out <= 1'b1; end
                2'd2: begin channel_out <= 5'h1e; eoc_out <= 1'b1; end
                2'd3: begin
                    do_out <= {y_sample, 4'b0000};
                    drdy_out <= 1'b1; eos_out <= 1'b1;
                end
            endcase
        end
    end
endmodule

module tb_servo_joystick_top;
    logic clk = 1'b0, rst;
    logic vauxp6, vauxn6, vauxp14, vauxn14, joy_btn;
    logic pwm_pan, pwm_tilt;
    integer errors = 0;

    always #5 clk = ~clk;

    servo_joystick_top #(
        .CLK_HZ(100_000_000),
        .MANUAL_CONTROL_HZ(10_000_000)
    ) dut (
        .clk(clk), .rst(rst), .vauxp6(vauxp6), .vauxn6(vauxn6),
        .vauxp14(vauxp14), .vauxn14(vauxn14), .joy_btn(joy_btn),
        .pwm_pan(pwm_pan), .pwm_tilt(pwm_tilt)
    );

    initial begin
        rst = 1'b1;
        vauxp6 = 1'b0; vauxn6 = 1'b0;
        vauxp14 = 1'b0; vauxn14 = 1'b0;
        joy_btn = 1'b1;
        repeat (3) @(posedge clk);
        #1;
        if (dut.u_servo.pan_angle !== 8'd90 ||
            dut.u_servo.tilt_angle !== 8'd90) begin
            errors = errors + 1;
            $error("reset failed: pan=%0d tilt=%0d",
                   dut.u_servo.pan_angle, dut.u_servo.tilt_angle);
        end

        rst = 1'b0;
        repeat (30) @(posedge clk);
        #1;
        if (!dut.joy_valid || dut.joy_dx !== 5'sd0 || dut.joy_dy !== 5'sd0) begin
            errors = errors + 1;
            $error("real joystick RTL center failed: valid=%0b x=%0d y=%0d",
                   dut.joy_valid, dut.joy_dx, dut.joy_dy);
        end

        vauxp6 = 1'b1;
        vauxp14 = 1'b1;
        // Let the moving-average filter replace the preceding samples and
        // provide enough simulated control ticks to cross the center angle.
        repeat (120) @(posedge clk);
        #1;
        if (dut.joy_dx <= 0 || dut.joy_dy >= 0 ||
            $unsigned(dut.u_servo.pan_angle) <= 90 ||
            $unsigned(dut.u_servo.tilt_angle) >= 90) begin
            errors = errors + 1;
            $error("real joystick-to-servo forward path failed: x=%0d y=%0d pan=%0d tilt=%0d",
                   dut.joy_dx, dut.joy_dy,
                   dut.u_servo.pan_angle, dut.u_servo.tilt_angle);
        end

        vauxp6 = 1'b0; vauxp14 = 1'b0;
        vauxn6 = 1'b1; vauxn14 = 1'b1;
        repeat (120) @(posedge clk);
        #1;
        if (dut.joy_dx >= 0 || dut.joy_dy <= 0 ||
            $unsigned(dut.u_servo.pan_angle) >= 90 ||
            $unsigned(dut.u_servo.tilt_angle) <= 90) begin
            errors = errors + 1;
            $error("real joystick RTL reverse mapping failed: x=%0d y=%0d pan=%0d tilt=%0d",
                   dut.joy_dx, dut.joy_dy,
                   dut.u_servo.pan_angle, dut.u_servo.tilt_angle);
        end

        if (errors == 0)
            $display("ALL REAL JOYSTICK_TOP TO SERVO TESTS PASSED");
        else
            $fatal(1, "%0d real joystick-to-servo tests failed", errors);
        $finish;
    end
endmodule
