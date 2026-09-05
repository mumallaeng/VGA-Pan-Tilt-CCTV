`timescale 1ns / 1ps

// Closed-loop check: does the servo path actually converge on a target, or
// does it run away?
//
// The open-loop testbenches only prove the angle register moves. They cannot
// show tracking, because tracking depends on the camera physically turning and
// the pixel error shrinking as a result. That feedback is modelled here:
//
//   cam_bearing   where the camera is actually pointing, degrees from centre.
//                 Follows angle_pan at the servo's real slew rate.
//   error_deg     obj_bearing - cam_bearing, the angle the object sits off
//                 the optical axis.
//   frame_dx      error_deg converted back to pixels at the same 3/16 deg/px
//                 the RTL assumes, then clamped to the 320 px frame.
//
// SERVO_DIR is the unknown the hardware decides: whether a rising angle_pan
// turns the camera toward positive bearing (+1) or away from it (-1). Both are
// run side by side, so the log shows which one the RTL's current sign matches.
//
// Time is compressed 100x: 1 ms of real time is 1000 clk cycles here rather
// than 100000. Frame rate, servo speed and loop gain all keep their real
// relative proportions.
module tb_servo_closed_loop;

    localparam int  MS_CYCLES    = 1000;              // 1 ms of modelled time
    localparam int  FRAME_CYCLES = (167 * MS_CYCLES) / 10;  // 16.7 ms, 60 fps
    localparam real DEG_PER_PX   = 3.0 / 16.0;        // coord_to_angle gain
    localparam real SERVO_DEG_MS = 0.6;               // SG90, ~600 deg/s
    localparam real OBJ_BEARING  = 30.0;              // object 30 deg off axis

    logic clk = 1'b0;
    logic rst;
    always #5 clk = ~clk;

    // ---------------- two plants, one per possible servo direction --------
    real cam_bearing [2];   // [0] = SERVO_DIR +1, [1] = SERVO_DIR -1
    real error_deg   [2];
    int  dir         [2] = '{1, -1};

    logic signed [9:0] frame_dx [2];
    logic signed [8:0] frame_dy [2];
    logic frame_valid, frame_done;
    logic [7:0] angle_pan [2];

    genvar g;
    generate
        for (g = 0; g < 2; g++) begin : g_path
            logic pwm_pan, pwm_tilt, tx;
            servo_top dut (
                .clk        (clk),
                .rst        (rst),
                .frame_dx   (frame_dx[g]),
                .frame_dy   (frame_dy[g]),
                .frame_valid(frame_valid),
                .frame_done (frame_done),
                .mode       (1'b0),          // AUTO
                .joy_dx     (5'sd0),
                .joy_dy     (5'sd0),
                .joy_valid  (1'b0),
                .joy_done   (1'b0),
                .pwm_pan    (pwm_pan),
                .pwm_tilt   (pwm_tilt),
                .tx         (tx)
            );
            assign angle_pan[g] = dut.pan_angle;
        end
    endgenerate

    // ---------------- servo dynamics -------------------------------------
    // Every 0.1 ms the camera creeps toward the commanded angle at the real
    // slew rate, which is what makes the command outrun the mechanism.
    real cmd_bearing;
    real step;
    initial begin
        cam_bearing[0] = 0.0;
        cam_bearing[1] = 0.0;
        forever begin
            repeat (MS_CYCLES / 10) @(posedge clk);
            for (int i = 0; i < 2; i++) begin
                cmd_bearing = dir[i] * (real'(angle_pan[i]) - 90.0);
                step = SERVO_DEG_MS / 10.0;              // per 0.1 ms
                if (cam_bearing[i] + step < cmd_bearing) cam_bearing[i] += step;
                else if (cam_bearing[i] - step > cmd_bearing) cam_bearing[i] -= step;
                else cam_bearing[i] = cmd_bearing;
            end
        end
    end

    // ---------------- camera: bearing error back to pixels ----------------
    function automatic logic signed [9:0] to_px(input real deg);
        real px;
        begin
            px = deg / DEG_PER_PX;
            if (px > 160.0) px = 160.0;
            if (px < -160.0) px = -160.0;
            to_px = $rtoi(px);
        end
    endfunction

    task automatic send_frame;
        for (int i = 0; i < 2; i++) begin
            error_deg[i] = OBJ_BEARING - cam_bearing[i];
            frame_dx[i]  = to_px(error_deg[i]);
            frame_dy[i]  = 9'sd0;
        end
        @(negedge clk);
        frame_done = 1'b1;
        repeat (4) @(negedge clk);          // one vga_pclk pulse
        frame_done = 1'b0;
        repeat (FRAME_CYCLES - 5) @(negedge clk);
    endtask

    initial begin
        rst         = 1'b1;
        frame_valid = 1'b1;
        frame_done  = 1'b0;
        frame_dx[0] = '0; frame_dx[1] = '0;
        frame_dy[0] = '0; frame_dy[1] = '0;
        repeat (20) @(negedge clk);
        rst = 1'b0;
        repeat (20) @(negedge clk);

        $display("Object sits %0.1f deg off axis. Tracking works if err -> 0.", OBJ_BEARING);
        $display("");
        $display("            SERVO_DIR = +1              SERVO_DIR = -1");
        $display("frame   dx   pan   cam    err     dx   pan   cam    err");
        $display("-----  ----  ---  -----  -----   ----  ---  -----  -----");

        for (int f = 0; f < 60; f++) begin
            send_frame();
            if (f % 3 == 0 || f < 6)
                $display("%5d  %4d  %3d  %5.1f  %5.1f   %4d  %3d  %5.1f  %5.1f",
                         f,
                         frame_dx[0], angle_pan[0], cam_bearing[0], error_deg[0],
                         frame_dx[1], angle_pan[1], cam_bearing[1], error_deg[1]);
        end

        $display("");
        for (int i = 0; i < 2; i++) begin
            $display("SERVO_DIR=%0d final: pan=%0d cam=%0.1f err=%0.1f  -> %s",
                     dir[i], angle_pan[i], cam_bearing[i], error_deg[i],
                     ((error_deg[i] < 2.0) && (error_deg[i] > -2.0)) ? "TRACKED" :
                     ((angle_pan[i] == 0 || angle_pan[i] == 180) ? "RAN TO THE RAIL"
                                                                 : "NOT SETTLED"));
        end

        $finish;
    end

endmodule
