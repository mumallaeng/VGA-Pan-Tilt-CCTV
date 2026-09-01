`timescale 1ns / 1ps

module joystick_xadc_processor (
    input  logic        clk,
    input  logic        rst,
    input  logic [ 4:0] channel_addr,
    input  logic [11:0] xadc_data,
    input  logic        xadc_drdy,
    input  logic        xadc_eoc,
    output logic [11:0] o_filtered_x,
    output logic [11:0] o_filtered_y,
    output logic        o_filtered_data_valid
);

    (* mark_debug = "true" *) logic        w_xadc_data_valid;
    (* mark_debug = "true" *) logic [11:0] w_xadc_x;
    (* mark_debug = "true" *) logic [11:0] w_xadc_y;

    xadc_xy_reader U_XADC_XY_READER (
        .clk              (clk),
        .rst              (rst),
        .channel_addr     (channel_addr),
        .xadc_data        (xadc_data),
        .xadc_drdy        (xadc_drdy),
        .xadc_eoc         (xadc_eoc),
        .o_xadc_x         (w_xadc_x),
        .o_xadc_y         (w_xadc_y),
        .o_xadc_data_valid(w_xadc_data_valid)
    );

    xadc_noise_filter U_XADC_NOISE_FILTER (
        .clk                  (clk),
        .rst                  (rst),
        .i_xadc_data_valid    (w_xadc_data_valid),
        .i_xadc_x             (w_xadc_x),
        .i_xadc_y             (w_xadc_y),
        .o_filtered_x         (o_filtered_x),
        .o_filtered_y         (o_filtered_y),
        .o_filtered_data_valid(o_filtered_data_valid)
    );
endmodule
