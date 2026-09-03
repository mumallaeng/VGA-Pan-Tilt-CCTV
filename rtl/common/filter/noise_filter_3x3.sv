`timescale 1ns / 1ps

module noise_filter_3x3 #(
    parameter IMG_WIDTH  = 320,
    parameter IMG_HEIGHT = 240,
    parameter X_WIDTH = $clog2(IMG_WIDTH),    // 9 (0~319를 담는 데 필요한 비트 수)
    parameter Y_WIDTH = $clog2(IMG_HEIGHT)    // 8 (0~239를 담는 데 필요한 비트 수)
) (
    input  logic                pclk,
    input  logic                rst,          // active-high, 비동기 리셋

    input  logic                red_valid,    // color_filter 출력이 유효한 타이밍 (1클럭 펄스)
    input  logic                red_mask,     // color_filter 출력 (1비트, 색상 매칭 여부)
    input  logic [X_WIDTH-1:0]  pixel_x,      // 현재 픽셀 x좌표 (0~319)
    input  logic [Y_WIDTH-1:0]  pixel_y,      // 현재 픽셀 y좌표 (0~239)

    output logic                clean_mask,   // 노이즈 제거 후 최종 판정 결과
    output logic [X_WIDTH-1:0]  clean_x,      // clean_mask가 실제로 가리키는 x좌표
    output logic [Y_WIDTH-1:0]  clean_y,      // clean_mask가 실제로 가리키는 y좌표
    output logic                out_valid     // clean_mask/clean_x/clean_y가 유효한지
);

    logic line1_val;  
    logic line2_val;   

line_buffer #(.IMG_WIDTH(IMG_WIDTH)) U_LINE_BUFFER(
    .pclk     (pclk),
    .pixel_valid(red_valid),
    .pixel_x  (pixel_x),
    .data_in (red_mask),
    .line1_out(line1_val),
    .line2_out(line2_val)
);

    logic row0_a, row0_b, row0_c;   // 현재 줄에서 최근 3칸
    logic row1_a, row1_b, row1_c;   // 1줄 전에서 최근 3칸
    logic row2_a, row2_b, row2_c;   // 2줄 전에서 최근 3칸

    // 3. 좌표 지연 파이프라인
    logic [X_WIDTH-1:0] x_d1;
    logic [Y_WIDTH-1:0] y_d1;

    // 4. 라인 진행 상태 추적 카운터
    //    3x3 윈도우가 아직 다 채워지지 않은 "초반 구간"(맨 위 2줄, 각 줄을 구분해내기 위한 카운터)
    logic [X_WIDTH-1:0] row_fill_cnt;    // 이번 줄에서 지금까지 몇 열을 처리했는지
    logic [Y_WIDTH-1:0] valid_row_cnt;   // 지금까지 몇 줄이 완전히 지나갔는지

    logic window_ready;   // 3x3 윈도우가 온전히 채워졌는지
    logic edge_pixel;     // 화면 가장자리 또는 윈도우 미완성 -> 노이즈로 취급해야 하는지

    // 5. out_valid 지연 파이프라인
    logic valid_d1;   // 1단계 지연

	always_ff @(posedge pclk or posedge rst) begin
	    if (rst) begin
	        row_fill_cnt  <= '0;
	        valid_row_cnt <= '0;
	        valid_d1      <= 1'b0;
	        out_valid     <= 1'b0;
	
	    end else begin
	        if (red_valid) begin
            // 1) 3x3 shift register 갱신
	            row2_a <= row2_b; row2_b <= row2_c; row2_c <= line2_val;
	            row1_a <= row1_b; row1_b <= row1_c; row1_c <= line1_val;
	            row0_a <= row0_b; row0_b <= row0_c; row0_c <= red_mask;
	
            // 2) 좌표 지연
	            x_d1    <= pixel_x;
	            y_d1    <= pixel_y;
	            clean_x <= x_d1;
	            clean_y <= (y_d1 == 0) ? 1'b0 : (y_d1 - 1'b1);
	
            // 3) 이번 줄 진행 카운트
	            if (pixel_x == IMG_WIDTH - 1) begin
	                row_fill_cnt  <= 1'b0;
	                valid_row_cnt <= valid_row_cnt + 1'b1;
	            end else begin
	                row_fill_cnt <= row_fill_cnt + 1'b1;
	            end
	        end
	
	        // valid 파이프라인은 red_valid와 무관하게 매 클럭 항상 흘러감
	        valid_d1  <= red_valid;
	        out_valid <= valid_d1;
	    end
	end

    // =========================================================================
    // 6. 경계 판정 (조합논리)
    // =========================================================================
    assign window_ready = (valid_row_cnt >= 2) && (row_fill_cnt >= 2);

    assign edge_pixel   = !window_ready
                        || (clean_x == 0) || (clean_x == IMG_WIDTH - 1)
                        || (clean_y == 0) || (clean_y == IMG_HEIGHT - 1);

    // =========================================================================
    // 7. Majority(다수결) 판정
    // =========================================================================
    logic [3:0] neighbor_sum;
    assign neighbor_sum = row0_a + row0_b + row0_c
                         + row1_a + row1_b + row1_c
                         + row2_a + row2_b + row2_c;

    always_comb begin
        if (edge_pixel) begin
            clean_mask = 1'b0;
        end else begin
            clean_mask = (neighbor_sum >= 4'd5);
        end
    end

endmodule
