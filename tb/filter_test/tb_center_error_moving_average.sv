`timescale 1ns / 1ps

module tb_center_error_moving_average;
    localparam int NUM_FRAMES = 15;
    localparam int BASE_ERR_X = 20;
    localparam int BASE_ERR_Y = 15;
    localparam int JITTER_MAX = 4;

    logic pclk = 1'b0;
    logic rst;
    logic frame_done;
    logic target_valid_out;
    logic [8:0] target_x;
    logic [7:0] target_y;
    logic valid;
    logic signed [8:0] rect_x;
    logic signed [7:0] rect_y;

    int raw_x [0:NUM_FRAMES-1];
    int raw_y [0:NUM_FRAMES-1];
    int model_x [0:4];
    int model_y [0:4];
    int model_count;
    int max_dev_x;
    int max_dev_y;
    int total_dev_x;
    int total_dev_y;
    int seed;

    always #5 pclk = ~pclk;

    center_error dut (
        .pclk             (pclk),
        .rst              (rst),
        .frame_done       (frame_done),
        .target_valid_out (target_valid_out),
        .target_x         (target_x),
        .target_y         (target_y),
        .valid            (valid),
        .rect_x           (rect_x),
        .rect_y           (rect_y)
    );

    function automatic int abs_int(input int value);
        abs_int = (value < 0) ? -value : value;
    endfunction

    function automatic int expected_average_x(input int new_value);
        int sum;
        int count;
        begin
            sum = new_value;
            count = (model_count < 4) ? model_count + 1 : 5;
            for (int i = 0; i < model_count; i++)
                sum += model_x[i];
            expected_average_x = sum / count;
        end
    endfunction

    function automatic int expected_average_y(input int new_value);
        int sum;
        int count;
        begin
            sum = new_value;
            count = (model_count < 4) ? model_count + 1 : 5;
            for (int i = 0; i < model_count; i++)
                sum += model_y[i];
            expected_average_y = sum / count;
        end
    endfunction

    task automatic push_model(input int new_x, input int new_y);
        begin
            for (int i = 4; i > 0; i--) begin
                model_x[i] = model_x[i-1];
                model_y[i] = model_y[i-1];
            end
            model_x[0] = new_x;
            model_y[0] = new_y;
            if (model_count < 4)
                model_count++;
        end
    endtask

    task automatic apply_frame(input int frame_no, input int err_x, input int err_y);
        int expected_x;
        int expected_y;
        int dev_x;
        int dev_y;
        begin
            expected_x = expected_average_x(err_x);
            expected_y = expected_average_y(err_y);

            @(negedge pclk);
            target_x         = 160 + err_x;
            target_y         = 120 - err_y;
            target_valid_out = 1'b1;
            frame_done       = 1'b1;
            #1;

            if (($signed(rect_x) !== expected_x) ||
                ($signed(rect_y) !== expected_y)) begin
                $fatal(1,
                    "FAIL frame %0d: raw=(%0d,%0d), filtered=(%0d,%0d), expected=(%0d,%0d)",
                    frame_no, err_x, err_y, $signed(rect_x), $signed(rect_y),
                    expected_x, expected_y);
            end

            dev_x = abs_int($signed(rect_x) - BASE_ERR_X);
            dev_y = abs_int($signed(rect_y) - BASE_ERR_Y);
            total_dev_x += dev_x;
            total_dev_y += dev_y;
            if (dev_x > max_dev_x) max_dev_x = dev_x;
            if (dev_y > max_dev_y) max_dev_y = dev_y;

            $display(
                "FRAME %02d | raw=(%4d,%4d) | avg5=(%4d,%4d) | deviation=(%3d,%3d)%s",
                frame_no, err_x, err_y, $signed(rect_x), $signed(rect_y),
                dev_x, dev_y,
                ((abs_int(err_x-BASE_ERR_X) > JITTER_MAX) ||
                 (abs_int(err_y-BASE_ERR_Y) > JITTER_MAX)) ? "  <OUTLIER>" : "");

            @(posedge pclk);
            push_model(err_x, err_y);
            @(negedge pclk);
            frame_done = 1'b0;
        end
    endtask

    initial begin
        rst              = 1'b1;
        frame_done       = 1'b0;
        target_valid_out = 1'b0;
        target_x         = 9'd160;
        target_y         = 8'd120;
        model_count      = 0;
        max_dev_x        = 0;
        max_dev_y        = 0;
        total_dev_x      = 0;
        total_dev_y      = 0;
        seed             = 32'h26_09_04_15;
        seed             = $urandom(seed);

        for (int i = 0; i < 5; i++) begin
            model_x[i] = 0;
            model_y[i] = 0;
        end

        // Small random jitter around (20,15) on every frame.
        for (int i = 0; i < NUM_FRAMES; i++) begin
            raw_x[i] = BASE_ERR_X + $urandom_range(0, 2*JITTER_MAX) - JITTER_MAX;
            raw_y[i] = BASE_ERR_Y + $urandom_range(0, 2*JITTER_MAX) - JITTER_MAX;
        end

        // Deterministic seed, randomly selected frames and signed large jumps.
        for (int n = 0; n < 3; n++) begin
            int outlier_frame;
            int spike_x;
            int spike_y;
            outlier_frame = $urandom_range(2, NUM_FRAMES-1);
            spike_x = $urandom_range(30, 65);
            spike_y = $urandom_range(25, 55);
            raw_x[outlier_frame] += $urandom_range(0, 1) ? spike_x : -spike_x;
            raw_y[outlier_frame] += $urandom_range(0, 1) ? spike_y : -spike_y;
        end

        repeat (4) @(posedge pclk);
        @(negedge pclk);
        rst = 1'b0;

        $display("---------------------------------------------------------------");
        $display("Reference error=(%0d,%0d), frames=%0d, moving-average window=5",
                 BASE_ERR_X, BASE_ERR_Y, NUM_FRAMES);
        $display("---------------------------------------------------------------");

        for (int frame_idx = 0; frame_idx < NUM_FRAMES; frame_idx++)
            apply_frame(frame_idx + 1, raw_x[frame_idx], raw_y[frame_idx]);

        $display("---------------------------------------------------------------");
        $display("RESULT | max deviation=(%0d,%0d)", max_dev_x, max_dev_y);
        $display("RESULT | mean absolute deviation=(%0d.%02d,%0d.%02d)",
                 total_dev_x / NUM_FRAMES,
                 (total_dev_x % NUM_FRAMES) * 100 / NUM_FRAMES,
                 total_dev_y / NUM_FRAMES,
                 (total_dev_y % NUM_FRAMES) * 100 / NUM_FRAMES);
        $display("PASS: all RTL outputs matched the five-frame reference model");
        $finish;
    end

endmodule
