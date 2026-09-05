`timescale 1ns / 1ps

module joystick_mapper(
    input  logic               clk,
    input  logic               rst,
    input  logic               i_filtered_data_valid,
    input  logic        [11:0] i_filtered_x,
    input  logic        [11:0] i_filtered_y,
    output logic signed [ 4:0] joy_motor_x,
    output logic signed [ 4:0] joy_motor_y
    );

    logic signed [4:0] delta_x;
    logic signed [4:0] delta_y;

    parameter int unsigned DELTA_MAX = 12'd10;

    // 파형 측정값에서 +- 10
    parameter int unsigned X_MIN     = 12'd21;
    parameter int unsigned X_DZ_LOW  = 12'd476;
    parameter int unsigned X_DZ_HIGH = 12'd521;
    parameter int unsigned X_MAX     = 12'd1205; // 1215 - 10
    
    parameter int unsigned Y_MIN     = 12'd23;
    parameter int unsigned Y_DZ_LOW  = 12'd470;
    parameter int unsigned Y_DZ_HIGH = 12'd503;
    parameter int unsigned Y_MAX     = 12'd1218;

    // 소수 비율 값을 정수로 표현하기 위한 고정소수점 확대 배수
    // Q12 : 1/12 비율로 scaling
    localparam int unsigned Q_BITS  = 12;
    localparam int unsigned Q_SCALE = 4096;
    // negative slack 방지를 위한 비율 계산 local parameter
    // 충분한 계산을 위한 int type 사용
    localparam int unsigned X_LEFT_RANGE  = X_DZ_LOW - X_MIN;
    localparam int unsigned X_RIGHT_RANGE = X_MAX - X_DZ_HIGH;
    localparam int unsigned Y_LOW_RANGE   = Y_DZ_LOW - Y_MIN;
    localparam int unsigned Y_HIGH_RANGE  = Y_MAX - Y_DZ_HIGH;

    // RANGE / 2를 더하는건 반올림을 하기 위함 , 맵핑 정확도 향상
    localparam int unsigned X_LEFT_GAIN  = ((DELTA_MAX * Q_SCALE) + (X_LEFT_RANGE / 2)) / X_LEFT_RANGE;
    localparam int unsigned X_RIGHT_GAIN = ((DELTA_MAX * Q_SCALE) + (X_RIGHT_RANGE / 2)) / X_RIGHT_RANGE;
    localparam int unsigned Y_LOW_GAIN   = ((DELTA_MAX * Q_SCALE) + (Y_LOW_RANGE / 2)) / Y_LOW_RANGE;
    localparam int unsigned Y_HIGH_GAIN  = ((DELTA_MAX * Q_SCALE) + (Y_HIGH_RANGE / 2)) / Y_HIGH_RANGE;

    // 곱하는 두 값이 12비트라서 24비트로 설정
    logic [23:0] x_product;
    logic [23:0] y_product;

    always_comb begin
        delta_x  = 5'sd0;
        x_product = 24'd0;
        if (i_filtered_x <= X_MIN) begin
            delta_x = -5'sd10;
        end else if ((i_filtered_x > X_MIN) && (i_filtered_x < X_DZ_LOW)) begin
            x_product = (X_DZ_LOW - i_filtered_x) * X_LEFT_GAIN;
            delta_x  = -$signed(x_product[16:12]);
        end else if ((i_filtered_x >= X_DZ_LOW) && (i_filtered_x <= X_DZ_HIGH)) begin
            delta_x = 5'sd0;
        end else if ((i_filtered_x > X_DZ_HIGH) && (i_filtered_x < X_MAX)) begin
            x_product = (i_filtered_x - X_DZ_HIGH) * X_RIGHT_GAIN;
            delta_x  = $signed(x_product[16:12]);
        end else begin
            delta_x = 5'sd10;
        end
    end

    always_comb begin
        delta_y  = 5'sd0;
        y_product = 24'd0;
        // Y inverted (2026-09-05): stick-up previously drove tilt to 180, now drives to 0
        if (i_filtered_y <= Y_MIN) begin
            delta_y = -5'sd10;
        end else if ((i_filtered_y > Y_MIN) && (i_filtered_y < Y_DZ_LOW)) begin
            y_product = (Y_DZ_LOW - i_filtered_y) * Y_LOW_GAIN;
            delta_y  = -$signed(y_product[16:12]);
        end else if ((i_filtered_y >= Y_DZ_LOW) && (i_filtered_y <= Y_DZ_HIGH)) begin
            delta_y = 5'sd0;
        end else if ((i_filtered_y > Y_DZ_HIGH) && (i_filtered_y < Y_MAX)) begin
            y_product = (i_filtered_y - Y_DZ_HIGH) * Y_HIGH_GAIN;
            delta_y = $signed(y_product[16:12]);
        end else begin
            delta_y = 5'sd10;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            joy_motor_x <= 5'sd0;
            joy_motor_y <= 5'sd0;
        end else begin
            if (i_filtered_data_valid) begin
                joy_motor_x <= delta_x;
                joy_motor_y <= delta_y;
            end
        end
    end

endmodule
