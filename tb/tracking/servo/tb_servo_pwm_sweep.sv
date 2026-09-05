`timescale 1ns / 1ps

// Measures the pulse width servo_pwm actually produces as angle rises.
//
// dut_fast keeps every width-related parameter at the real 100 MHz values
// (PWM_MIN, PWM_MAX and CNT_PER_DEGREE are all derived from CLK_HZ) and only
// shortens PERIOD, which the width mapping does not depend on. That makes a
// full sweep cheap to simulate while every measured width stays bit-identical
// to the deployed configuration.
//
// dut_real then runs one untouched 20 ms period to confirm the shortening did
// not distort anything.
module tb_servo_pwm_sweep;

    localparam int CLK_HZ = 100_000_000;
    localparam int SHORT_PERIOD = 220_000;   // 2.2 ms, still clears PWM_MAX

    logic clk = 1'b0;
    logic rst;
    logic [7:0] angle_fast, angle_real;
    logic pwm_fast, pwm_real;

    always #5 clk = ~clk;  // 100 MHz, 10 ns per cycle

    servo_pwm #(
        .CLK_HZ(CLK_HZ),
        .PERIOD(SHORT_PERIOD)
    ) dut_fast (
        .clk(clk), .rst(rst), .angle(angle_fast), .pwm(pwm_fast)
    );

    servo_pwm #(
        .CLK_HZ(CLK_HZ)
    ) dut_real (
        .clk(clk), .rst(rst), .angle(angle_real), .pwm(pwm_real)
    );

    // Counts clk cycles the pulse stays high, so the result is in real time
    // units regardless of the shortened period.
    task automatic measure_fast(input logic [7:0] a, output int cycles);
        begin
            angle_fast = a;
            // The angle is latched at counter == 0, so let one boundary pass
            // before timing the pulse it produced.
            @(posedge pwm_fast);
            @(negedge pwm_fast);
            @(posedge pwm_fast);
            cycles = 0;
            while (pwm_fast) begin
                @(posedge clk);
                cycles++;
            end
        end
    endtask

    int cyc;
    real us, prev_us, step_us;

    initial begin
        rst        = 1'b1;
        angle_fast = 8'd90;
        angle_real = 8'd90;
        repeat (10) @(negedge clk);
        rst = 1'b0;

        $display("servo_pwm at CLK_HZ = %0d", CLK_HZ);
        $display("  PERIOD         = %0d cycles", CLK_HZ / 50);
        $display("  PWM_MIN        = %0d cycles", CLK_HZ / 1000);
        $display("  PWM_MAX        = %0d cycles", CLK_HZ / 500);
        $display("  CNT_PER_DEGREE = %0d cycles", ((CLK_HZ / 500) - (CLK_HZ / 1000)) / 180);
        $display("");
        $display("angle   high(cycles)   width(us)   step from prev");
        $display("-----   ------------   ---------   --------------");

        prev_us = 0.0;
        foreach_angle : begin
            int angles [11] = '{0, 1, 2, 30, 45, 60, 90, 120, 135, 179, 180};
            for (int i = 0; i < 11; i++) begin
                measure_fast(angles[i][7:0], cyc);
                us = cyc * 0.01;              // 10 ns per cycle -> us
                step_us = us - prev_us;
                if (i == 0)
                    $display("%5d   %12d   %9.2f   %s", angles[i], cyc, us, "-");
                else
                    $display("%5d   %12d   %9.2f   %9.2f us over %0d deg",
                             angles[i], cyc, us, step_us, angles[i] - angles[i-1]);
                prev_us = us;
            end
        end

        // One untouched period, to prove the shortened one did not skew things.
        $display("");
        $display("Checking the real (unshortened) instance at angle 90 ...");
        angle_real = 8'd90;
        @(posedge pwm_real);
        @(negedge pwm_real);
        begin
            time t_rise, t_fall, t_next;
            @(posedge pwm_real); t_rise = $time;
            @(negedge pwm_real); t_fall = $time;
            @(posedge pwm_real); t_next = $time;
            $display("  width  = %0.3f ms", (t_fall - t_rise) / 1000000.0);
            $display("  period = %0.3f ms  (%0.1f Hz)",
                     (t_next - t_rise) / 1000000.0,
                     1000000000.0 / (t_next - t_rise));
        end

        $finish;
    end

endmodule
