`timescale 1ns / 1ps

module joystick_mapper(
    input  logic               clk,
    input  logic               rst,
    input  logic               i_filtered_data_valid,
    input  logic        [11:0] i_filtered_x,
    input  logic        [11:0] i_filtered_y,
    output logic signed [ 8:0] joy_motor_x,
    output logic signed [ 7:0] joy_motor_y
    );

    logic signed [8:0] mapped_x;
    logic signed [7:0] mapped_y;

    parameter int unsigned X_MIN     = 4;
    parameter int unsigned X_DZ_LOW  = 480;
    parameter int unsigned X_DZ_HIGH = 520;
    parameter int unsigned X_MAX     = 1220;
    
    parameter int unsigned Y_MIN     = 4;
    parameter int unsigned Y_DZ_LOW  = 470;
    parameter int unsigned Y_DZ_HIGH = 510;
    parameter int unsigned Y_MAX     = 1225;

    always_comb begin
        if (i_filtered_x <= X_MIN) begin
            mapped_x = -9'sd160;
        end else if ((i_filtered_x > X_MIN) && (i_filtered_x < X_DZ_LOW)) begin
            mapped_x = -(((X_DZ_LOW - i_filtered_x) * 160) / (X_DZ_LOW - X_MIN));
        end else if ((i_filtered_x >= X_DZ_LOW) && (i_filtered_x <= X_DZ_HIGH)) begin
            mapped_x = 9'sd0;
        end else if ((i_filtered_x > X_DZ_HIGH) && (i_filtered_x < X_MAX)) begin
            mapped_x = (((i_filtered_x - X_DZ_HIGH) * 160) / (X_MAX - X_DZ_HIGH));
        end else begin
            mapped_x = 9'sd160;
        end
    end

    always_comb begin
        if (i_filtered_y <= Y_MIN) begin
            mapped_y = -8'sd120;
        end else if ((i_filtered_y > Y_MIN) && (i_filtered_y < Y_DZ_LOW)) begin
            mapped_y = -(((Y_DZ_LOW - i_filtered_y) * 120) / (Y_DZ_LOW - Y_MIN));
        end else if ((i_filtered_y >= Y_DZ_LOW) && (i_filtered_y <= Y_DZ_HIGH)) begin
            mapped_y = 8'sd0;
        end else if ((i_filtered_y > Y_DZ_HIGH) && (i_filtered_y < Y_MAX)) begin
            mapped_y = (((i_filtered_y - Y_DZ_HIGH) * 120) / (Y_MAX - Y_DZ_HIGH));
        end else begin
            mapped_y = 8'sd120;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            joy_motor_x <= 9'sd0;
            joy_motor_y <= 8'sd0;
        end else begin
            if (i_filtered_data_valid) begin
                joy_motor_x <= mapped_x;
                joy_motor_y <= mapped_y;
            end
        end
    end

endmodule
