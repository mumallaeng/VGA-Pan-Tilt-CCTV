`timescale 1ns / 1ps

module line_buffer #(
    parameter IMG_WIDTH = 320,                 // 한 줄의 픽셀 개수 (=라인버퍼 깊이)
    parameter X_WIDTH   = $clog2(IMG_WIDTH)    // pixel_x를 담는 데 필요한 최소 비트 수
) (
    input  logic                pclk,          // 사용처의 클럭 도메인에 맞춰 연결
    input  logic                pixel_valid,   // 지금 pixel_x/data_in이 유효한 픽셀인지
    input  logic [X_WIDTH-1:0]  pixel_x,       // 지금 들어온 픽셀의 x좌표
    input  logic                data_in,       // 지금 저장할 1비트 값 (용도 무관: 색상판정/박스판정 등)

    output logic                line1_out,     // 같은 x좌표의 "1줄 전" 값
    output logic                line2_out      // 같은 x좌표의 "2줄 전" 값
);

    // 실제 저장 공간
    logic buf1 [0:IMG_WIDTH-1];   
    logic buf2 [0:IMG_WIDTH-1];   

    assign line1_out = buf1[pixel_x];
    assign line2_out = buf2[pixel_x];

    always_ff @(posedge pclk) begin
        if (pixel_valid) begin
            buf2[pixel_x] <= buf1[pixel_x];   
            buf1[pixel_x] <= data_in;         
        end
    end

endmodule
