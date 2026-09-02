`timescale 1ns / 1ps

module tb_centroid_filter;

    logic pclk;
    logic rst;

    logic       clean_mask;
    logic       out_valid;
    logic [8:0] clean_x;
    logic [7:0] clean_y;

    logic              done;
    logic              target_valid_out;
    logic              valid;
    logic        [8:0] min_x;
    logic        [8:0] max_x;
    logic        [7:0] min_y;
    logic        [7:0] max_y;
    logic signed [8:0] rect_x;
    logic signed [7:0] rect_y;

    logic vga_screen [0:319][0:239];

    centroid_filter dut (.*);

    always #5 pclk = ~pclk;

    task automatic clear_screen;
        for (int y = 0; y < 240; y++) begin
            for (int x = 0; x < 320; x++) begin
                vga_screen[x][y] = 1'b0;
            end
        end
    endtask

    // x_h와 y_h는 영역에 포함되지 않는다.
    task automatic red_zone (
        input int x_l,
        input int x_h,
        input int y_l,
        input int y_h
    );
        for (int y = y_l; y < y_h; y++) begin
            for (int x = x_l; x < x_h; x++) begin
                vga_screen[x][y] = 1'b1;
            end
        end
    endtask

    task automatic send_frame;
        for (int y = 0; y < 240; y++) begin
            for (int x = 0; x < 320; x++) begin
                @(negedge pclk);
                out_valid  = 1'b1;
                clean_x    = x;
                clean_y    = y;
                clean_mask = vga_screen[x][y];
            end
        end

        // 마지막 픽셀은 다음 posedge에서 처리된다.
        @(negedge pclk);
        out_valid  = 1'b0;
        clean_mask = 1'b0;

        // bounding box 결과와 done이 출력될 때까지 기다린다.
        wait (done === 1'b1);
        #1;
    endtask

    task automatic check_done_returns_low;
        @(posedge pclk);
        #1;
        if (done !== 1'b0) begin
            $fatal(1, "FAIL: done did not return low after one pclk");
        end
    endtask

    initial begin
        pclk       = 1'b0;
        rst        = 1'b1;
        clean_mask = 1'b0;
        out_valid  = 1'b0;
        clean_x    = 9'd0;
        clean_y    = 8'd0;

        clear_screen();

        repeat (5) @(posedge pclk);
        @(negedge pclk);
        rst = 1'b0;

        if ((valid !== 1'b0) || (target_valid_out !== 1'b0)) begin
            $fatal(1, "FAIL: valid was asserted before the first frame");
        end

        // ------------------------------------------------------------
        // Frame 1: 화면 중심보다 오른쪽/아래쪽
        // bbox=(250,150)-(319,239), center=(284,194), error=(124,-74)
        // ------------------------------------------------------------
        clear_screen();
        red_zone(250, 320, 150, 240);
        send_frame();

        if (done !== 1'b1)
            $fatal(1, "FAIL F1: done was not asserted");
        if ((target_valid_out !== 1'b1) || (valid !== 1'b1))
            $fatal(1, "FAIL F1: target was not valid");
        if ((min_x !== 9'd250) || (max_x !== 9'd319) ||
            (min_y !== 8'd150) || (max_y !== 8'd239))
            $fatal(1, "FAIL F1: bbox=(%0d,%0d)-(%0d,%0d)",
                   min_x, min_y, max_x, max_y);
        if ((rect_x !== 9'sd124) || (rect_y !== -8'sd74))
            $fatal(1, "FAIL F1: error=(%0d,%0d), expected=(124,-74)",
                   $signed(rect_x), $signed(rect_y));

        $display("PASS F1: bbox=(%0d,%0d)-(%0d,%0d), error=(%0d,%0d)",
                 min_x, min_y, max_x, max_y,
                 $signed(rect_x), $signed(rect_y));

        check_done_returns_low();

        // ------------------------------------------------------------
        // Frame 2: 화면 중심보다 왼쪽/위쪽
        // bbox=(100,60)-(199,79), center=(149,69), error=(-11,51)
        // ------------------------------------------------------------
        clear_screen();
        red_zone(100, 200, 60, 80);
        send_frame();

        if (done !== 1'b1)
            $fatal(1, "FAIL F2: done was not asserted");
        if ((target_valid_out !== 1'b1) || (valid !== 1'b1))
            $fatal(1, "FAIL F2: target was not valid");
        if ((min_x !== 9'd100) || (max_x !== 9'd199) ||
            (min_y !== 8'd60) || (max_y !== 8'd79))
            $fatal(1, "FAIL F2: bbox=(%0d,%0d)-(%0d,%0d)",
                   min_x, min_y, max_x, max_y);
        if ((rect_x !== -9'sd11) || (rect_y !== 8'sd51))
            $fatal(1, "FAIL F2: error=(%0d,%0d), expected=(-11,51)",
                   $signed(rect_x), $signed(rect_y));

        $display("PASS F2: bbox=(%0d,%0d)-(%0d,%0d), error=(%0d,%0d)",
                 min_x, min_y, max_x, max_y,
                 $signed(rect_x), $signed(rect_y));

        check_done_returns_low();

        // ------------------------------------------------------------
        // Frame 3: 타깃 없음
        // ------------------------------------------------------------
        clear_screen();
        send_frame();

        if (done !== 1'b1)
            $fatal(1, "FAIL F3: done was not asserted");
        if ((target_valid_out !== 1'b0) || (valid !== 1'b0))
            $fatal(1, "FAIL F3: empty frame was reported as valid");
        if ((min_x !== 9'd0) || (max_x !== 9'd0) ||
            (min_y !== 8'd0) || (max_y !== 8'd0))
            $fatal(1, "FAIL F3: invalid bbox outputs were not zero");

        // rect_x/y는 valid=0일 때 사용하지 않는 값이므로 검사하지 않는다.
        $display("PASS F3: empty frame, valid=0");

        check_done_returns_low();

        $display("PASS: centroid_filter all tests completed");
        $finish;
    end

endmodule

