`timescale 1ns / 1ps

// Observes what the 60 Hz frame rate does to a servo path that advances at
// 50 Hz, and what happens when the tracked object disappears.
//
// Real hardware runs at 100 MHz, which would need 50 million cycles per second
// of observation. The clock rate the design is *told* about is scaled down to
// 300 kHz instead, chosen so both rates stay exact integers and the ratio that
// actually matters is preserved:
//
//     frame period  = 300000/60 = 5000 cycles   (60 Hz image frames)
//     pwm refresh   = 300000/50 = 6000 cycles   (50 Hz servo_pwm reload)
//     ratio         = 6:5, identical to the real 100 MHz case
//
// axis_ctrl no longer has a move_tick of its own: it applies each arriving
// delta directly, so the angle now updates at the frame rate.
module tb_servo_rate_mismatch;

    localparam int SIM_CLK_HZ   = 300_000;
    localparam int FRAME_CYCLES = SIM_CLK_HZ / 60;  // 5000
    localparam int TICK_CYCLES  = SIM_CLK_HZ / 50;  // 6000

    logic clk = 1'b0;
    logic rst;
    logic signed [9:0] frame_dx;
    logic signed [8:0] frame_dy;
    logic frame_valid, frame_done;
    logic mode;
    logic signed [4:0] joy_dx, joy_dy;
    logic joy_valid, joy_done;
    logic pwm_pan, pwm_tilt;

    always #5 clk = ~clk;  // 100 MHz wall clock, 300 kHz as far as the design knows

    servo_top #(
        .CLK_HZ           (SIM_CLK_HZ),
        .MANUAL_CONTROL_HZ(50)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .frame_dx   (frame_dx),
        .frame_dy   (frame_dy),
        .frame_valid(frame_valid),
        .frame_done (frame_done),
        .mode       (mode),
        .joy_dx     (joy_dx),
        .joy_dy     (joy_dy),
        .joy_valid  (joy_valid),
        .joy_done   (joy_done),
        .pwm_pan    (pwm_pan),
        .pwm_tilt   (pwm_tilt)
    );

    // ---------------- instrumentation ----------------
    wire       angle_valid = dut.u_axis_ctrl.angle_valid;
    wire       angle_apply = dut.u_axis_ctrl.angle_apply;
    wire [7:0] angle_pan   = dut.u_axis_ctrl.angle_pan;

    int frame_count      = 0;   // frames handed to the DUT
    int update_count     = 0;   // clk cycles with angle_valid high
    int apply_count      = 0;   // cycles where a delta was applied
    int step_count       = 0;   // cycles where angle_pan actually changed

    logic [7:0] prev_pan;
    logic       trace_on = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            prev_pan <= 8'd90;
        end else begin
            if (angle_valid) update_count++;
            if (angle_apply) apply_count++;

            if (angle_pan !== prev_pan) begin
                step_count++;
                if (trace_on)
                    $display("    step %0d: pan %0d -> %0d (frame#%0d)",
                             step_count, prev_pan, angle_pan, frame_count);
            end

            prev_pan <= angle_pan;
        end
    end

    // One vga_pclk pulse is four clk cycles wide at 100 MHz, which is what
    // ctrl_mode_mux sees in AUTO mode.
    task automatic send_frame(input logic vld);
        @(negedge clk);
        frame_valid = vld;
        frame_done  = 1'b1;
        repeat (4) @(negedge clk);
        frame_done = 1'b0;
        frame_count++;
        repeat (FRAME_CYCLES - 5) @(negedge clk);
    endtask

    task automatic reset_counters;
        frame_count  = 0;
        update_count = 0;
        apply_count  = 0;
        step_count   = 0;
    endtask

    task automatic report(input string phase);
        $display("  %s: frames=%0d  deltas_applied=%0d  angle_steps=%0d",
                 phase, frame_count, apply_count, step_count);
        $display("    angle_valid cycles=%0d (4 per frame, edge detected to %0d)",
                 update_count, apply_count);
        $display("    final: angle_pan=%0d", angle_pan);
    endtask

    initial begin
        rst         = 1'b1;
        mode        = 1'b0;   // AUTO: frame path
        frame_dx    = '0;
        frame_dy    = '0;
        frame_valid = 1'b0;
        frame_done  = 1'b0;
        joy_dx      = '0;
        joy_dy      = '0;
        joy_valid   = 1'b0;
        joy_done    = 1'b0;

        repeat (10) @(negedge clk);
        rst = 1'b0;
        repeat (10) @(negedge clk);

        // =====================================================
        $display("\n=== Phase 1: object held at dx=+16 (delta_angle=+3), 30 frames @60Hz ===");
        // 16 px * 3/16 = 3 degrees requested per frame
        frame_dx = 10'sd16;
        frame_dy = 9'sd0;
        reset_counters();
        trace_on = 1'b1;
        repeat (30) send_frame(1'b1);
        trace_on = 1'b0;
        report("Phase 1");

        // =====================================================
        $display("\n=== Phase 2: object lost, frame_valid=0 for 20 frames ===");
        $display("    (frame_done still pulses every frame, as min_max_find does)");
        reset_counters();
        trace_on = 1'b1;
        repeat (20) send_frame(1'b0);
        trace_on = 1'b0;
        report("Phase 2");

        // =====================================================
        $display("\n=== Phase 3: object reappears on the other side, dx=-16, 20 frames ===");
        frame_dx = -10'sd16;
        reset_counters();
        trace_on = 1'b1;
        repeat (20) send_frame(1'b1);
        trace_on = 1'b0;
        report("Phase 3");

        // =====================================================
        // Phase 2 began with the angle already sitting on its target, so it
        // could only show a standstill. This one drops the object while a
        // large move is still in flight.
        $display("");
        $display("=== Phase 4: dx=+320 (delta=+60) once, then object lost mid-motion ===");
        frame_dx = 10'sd320;
        reset_counters();
        trace_on = 1'b1;
        send_frame(1'b1);              // one frame commands a 60 degree move
        repeat (10) send_frame(1'b0);  // object gone from here on
        trace_on = 1'b0;
        report("Phase 4");

        $display("\n=== done ===");
        $finish;
    end

endmodule
