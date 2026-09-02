`timescale 1ns / 1ps

module tb_noise_filter_3x3;

    localparam IMG_WIDTH  = 8;
    localparam IMG_HEIGHT = 6;
    localparam X_WIDTH = $clog2(IMG_WIDTH);
    localparam Y_WIDTH = $clog2(IMG_HEIGHT);

    logic pclk = 0;
    logic rst;
    logic red_valid;
    logic red_mask;
    logic [X_WIDTH-1:0] pixel_x;
    logic [Y_WIDTH-1:0] pixel_y;

    logic clean_mask;
    logic [X_WIDTH-1:0] clean_x;
    logic [Y_WIDTH-1:0] clean_y;
    logic out_valid;              // ← clean_valid에서 변경

    always #5 pclk = ~pclk;

    noise_filter_3x3 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) DUT (
        .pclk       (pclk),
        .rst        (rst),
        .red_valid  (red_valid),
        .red_mask   (red_mask),
        .pixel_x    (pixel_x),
        .pixel_y    (pixel_y),
        .clean_mask (clean_mask),
        .clean_x    (clean_x),
        .clean_y    (clean_y),
        .out_valid  (out_valid)   // ← 포트 매핑도 변경
    );

    logic img [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic expected [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];

    int error_cnt = 0;
    int check_cnt = 0;

    initial begin
        img[0] = '{0,0,0,0,1,0,0,0};
        img[1] = '{0,0,0,0,0,0,0,0};
        img[2] = '{0,0,1,1,1,0,0,0};
        img[3] = '{0,1,1,1,1,0,0,0};
        img[4] = '{0,0,0,0,0,0,0,0};
        img[5] = '{0,0,0,0,0,0,0,0};

        foreach (expected[y]) expected[y] = '{default:0};
        expected[2][2] = 1; expected[2][3] = 1;
        expected[3][2] = 1; expected[3][3] = 1;
    end

    task automatic stream_frame();
        for (int y = 0; y < IMG_HEIGHT; y++) begin
            for (int x = 0; x < IMG_WIDTH; x++) begin
                @(posedge pclk);
                red_valid <= 1'b1;
                pixel_x   <= x[X_WIDTH-1:0];
                pixel_y   <= y[Y_WIDTH-1:0];
                red_mask  <= img[y][x];
            end
        end
        for (int i = 0; i < 4; i++) begin
            @(posedge pclk);
            red_valid <= 1'b1;
            red_mask  <= 1'b0;
        end
        @(posedge pclk);
        red_valid <= 1'b0;
    endtask

    // ---- out_valid 기준으로 체크 ----
    always @(posedge pclk) begin
        if (out_valid) begin
            check_cnt++;
            if (clean_mask !== expected[clean_y][clean_x]) begin
                error_cnt++;
                $display("[FAIL] (x=%0d,y=%0d) got=%b expected=%b",
                          clean_x, clean_y, clean_mask, expected[clean_y][clean_x]);
            end else begin
                $display("[PASS] (x=%0d,y=%0d) clean_mask=%b", clean_x, clean_y, clean_mask);
            end
        end
    end

    initial begin
        rst       <= 1;
        red_valid <= 0;
        red_mask  <= 0;
        pixel_x   <= 0;
        pixel_y   <= 0;
        repeat (3) @(posedge pclk);
        rst <= 0;

        stream_frame();

        repeat (5) @(posedge pclk);

        $display("==============================");
        $display("Total checked : %0d", check_cnt);
        $display("Total errors  : %0d", error_cnt);
        if (error_cnt == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> %0d TEST(S) FAILED <<<", error_cnt);
        $display("==============================");

        $finish;
    end

endmodule
