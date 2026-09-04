`timescale 1ns / 1ps
// 3x3 majority filter (제로패딩 방식) - 노이즈 픽셀 제거
module noise_filter_3x3 #(
    parameter IMG_WIDTH  = 320,
    parameter IMG_HEIGHT = 240,
    parameter X_WIDTH = $clog2(IMG_WIDTH),
    parameter Y_WIDTH = $clog2(IMG_HEIGHT)
) (
    input  logic pclk,
    input  logic rst,

    input  logic               red_valid,
    input  logic               red_mask,
    input  logic [X_WIDTH-1:0] pixel_x,
    input  logic [Y_WIDTH-1:0] pixel_y,

    output logic                clean_mask,
    output logic [X_WIDTH-1:0]  clean_x,
    output logic [Y_WIDTH-1:0]  clean_y,
    output logic                out_valid
);

    logic line1_val;  // 1줄 전 값
    logic line2_val;  // 2줄 전 값

    line_buffer #(
        .IMG_WIDTH(IMG_WIDTH)
    ) U_LINE_BUFFER (
        .pclk       (pclk),
        .rst        (rst),
        .pixel_valid(red_valid),
        .pixel_x    (pixel_x),
        .data_in    (red_mask),
        .line1_out  (line1_val),
        .line2_out  (line2_val)
    );

    // 3x3 윈도우 (row2=위, row1=중앙, row0=아래)
    logic row0_a, row0_b, row0_c;
    logic row1_a, row1_b, row1_c;
    logic row2_a, row2_b, row2_c;

    logic [X_WIDTH-1:0] x_d1;
    logic [Y_WIDTH-1:0] y_d1;

    // line_buffer가 실제 데이터로 채워질 때까지(최소 2줄) 대기용 카운터
    logic [1:0] rows_seen;
    logic       rows_ready;

    logic valid_d1;  // out_valid 2클럭 지연 파이프라인용

    always_ff @(posedge pclk or posedge rst) begin
        if (rst) begin
            valid_d1  <= 1'b0;
            out_valid <= 1'b0;
            rows_seen <= 2'd0;

            row0_a <= 1'b0; row0_b <= 1'b0; row0_c <= 1'b0;
            row1_a <= 1'b0; row1_b <= 1'b0; row1_c <= 1'b0;
            row2_a <= 1'b0; row2_b <= 1'b0; row2_c <= 1'b0;
            x_d1    <= '0;
            y_d1    <= '0;
            clean_x <= '0;
            clean_y <= '0;

        end else begin
            if (red_valid) begin
                // 3x3 shift register 한 칸씩 밀기
                row2_a <= row2_b; row2_b <= row2_c; row2_c <= line2_val;
                row1_a <= row1_b; row1_b <= row1_c; row1_c <= line1_val;
                row0_a <= row0_b; row0_b <= row0_c; row0_c <= red_mask;

                // 좌표 지연 (row1=중앙 줄 번호에 맞춤)
                x_d1    <= pixel_x;
                y_d1    <= pixel_y;
                clean_x <= x_d1;
                clean_y <= (y_d1 == 0) ? 1'b0 : (y_d1 - 1'b1);

                if (pixel_x == IMG_WIDTH - 1 && rows_seen < 2'd2) begin
                    rows_seen <= rows_seen + 1'b1;
                end
            end

            // red_valid=0일 때도 흘러가야 out_valid가 정상적으로 0으로 떨어짐
            valid_d1  <= red_valid;
            out_valid <= valid_d1;
        end
    end

    assign rows_ready = (rows_seen >= 2'd2);

    // 제로패딩: 화면 밖 이웃은 존재하지 않는 것으로 처리
    logic left_valid, right_valid, top_valid, bottom_valid;
    assign left_valid   = (clean_x != 0);
    assign right_valid  = (clean_x != IMG_WIDTH - 1);
    assign top_valid    = (clean_y != 0);
    assign bottom_valid = (clean_y != IMG_HEIGHT - 1);

    // 9칸 중 존재하는 이웃만 합산 (대각선은 AND로 두 조건 결합)
    logic [3:0] neighbor_sum;
    assign neighbor_sum = (row2_a & left_valid  & top_valid)
                         + (row2_b & top_valid)
                         + (row2_c & right_valid & top_valid)
                         + (row1_a & left_valid)
                         + row1_b
                         + (row1_c & right_valid)
                         + (row0_a & left_valid  & bottom_valid)
                         + (row0_b & bottom_valid)
                         + (row0_c & right_valid & bottom_valid);

    // 워밍업 구간은 0 고정, 이후 과반수(>=5)면 1
    assign clean_mask = rows_ready ? (neighbor_sum >= 4'd5) : 1'b0;

endmodule