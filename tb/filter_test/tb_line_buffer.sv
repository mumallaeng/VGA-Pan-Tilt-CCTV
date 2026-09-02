`timescale 1ns / 1ps

module tb_line_buffer;

    localparam IMG_WIDTH = 8;
    localparam X_WIDTH = $clog2(IMG_WIDTH);

    logic pclk = 0;
    logic red_valid;
    logic [X_WIDTH-1:0] pixel_x;
    logic red_mask;
    logic line1_out, line2_out;

    always #5 pclk = ~pclk;

    line_buffer #(
        .IMG_WIDTH(IMG_WIDTH)
    ) DUT (
        .pclk     (pclk),
        .red_valid(red_valid),
        .pixel_x  (pixel_x),
        .red_mask (red_mask),
        .line1_out(line1_out),
        .line2_out(line2_out)
    );

    int error_cnt = 0;

    initial begin
        // 초기값도 논블로킹으로 (일관성 유지)
        red_valid <= 0;
        pixel_x   <= 0;
        red_mask  <= 0;
        repeat(2) @(posedge pclk);

        // ---- 1번째 줄: x=3 위치에 1을 저장 ----
        // 이 엣지에서 DUT는 반드시 "옛날 값(red_valid=0)"을 읽음 → write 안 일어남
        @(posedge pclk);
        red_valid <= 1;
        pixel_x   <= 3;
        red_mask  <= 1;

        // 이 엣지에서 DUT가 비로소 새 값(red_valid=1, red_mask=1)을 읽어서
        // buf1[3] <= 1  실행됨 (write 발생)
        @(posedge pclk);
        red_valid <= 0;

        repeat(2) @(posedge pclk);

        // ---- 2번째 줄: 같은 x=3 위치 다시 방문 ----
        @(posedge pclk);
        red_valid <= 1;
        pixel_x   <= 3;
        red_mask  <= 0;

        // 이 엣지에서 DUT가 write를 수행하기 "직전" 상태를 보고 싶으므로,
        // 논블로킹 대입 특성상 이 엣지 시점엔 buf1[3]이 아직 "이전 값(1)"을 유지함
        // → #1로 살짝 기다려서 combinational 출력이 안정된 후 체크
        #1;
        if (line1_out !== 1'b1) begin
            error_cnt++;
            $display("[FAIL] line1_out = %b, expected 1", line1_out);
        end else begin
            $display("[PASS] line1_out = %b (1줄 전 값 정확히 읽힘)", line1_out);
        end

        @(posedge pclk);
        red_valid <= 0;
        repeat(2) @(posedge pclk);

        // ---- 3번째 줄: 같은 x=3 위치 세 번째 방문 ----
        @(posedge pclk);
        red_valid <= 1;
        pixel_x   <= 3;
        red_mask  <= 0;

        #1;
        if (line1_out !== 1'b0) begin
            error_cnt++;
            $display("[FAIL] line1_out = %b, expected 0", line1_out);
        end else begin
            $display("[PASS] line1_out = %b (2줄 전 값이 1줄 전 자리로 이동함)", line1_out);
        end

        if (line2_out !== 1'b1) begin
            error_cnt++;
            $display("[FAIL] line2_out = %b, expected 1", line2_out);
        end else begin
            $display("[PASS] line2_out = %b (1번째 줄 값이 2줄 전 자리로 이동함)", line2_out);
        end

        $display("==============================");
        if (error_cnt == 0) $display(">>> LINE BUFFER TEST PASSED <<<");
        else $display(">>> %0d TEST(S) FAILED <<<", error_cnt);
        $display("==============================");

        $finish;
    end

endmodule
