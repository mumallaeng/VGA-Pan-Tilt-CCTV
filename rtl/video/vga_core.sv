`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer:Jong.W.Park 
// Create Date: 2026/07/06 19:15:31
// Module Name: vga_core
//////////////////////////////////////////////////////////////////////////////////


module vga_core #(
    parameter int H_VISIBLE = 640,
    parameter int H_FRONT   = 16,
    parameter int H_SYNC    = 96,
    parameter int H_BACK    = 48,

    parameter int V_VISIBLE = 480,
    parameter int V_FRONT   = 10,
    parameter int V_SYNC    = 2,
    parameter int V_BACK    = 33
) (
    input logic clk,
    input logic rst,

    output logic       pclk,
    output logic       h_sync,
    output logic       v_sync,
    output logic       DE,
    output logic [9:0] x_pixel,
    output logic [9:0] y_pixel
);

    localparam H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
    localparam V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;


    logic [9:0] h_cnt;
    logic [9:0] v_cnt;

    pixel_clk_gen U_PIXEL_CLK_GEN (
        .clk (clk),
        .rst (rst),
        .pclk(pclk)
    );

    pixel_counter U_PIXEL_COUNTER (
        .pclk (pclk),
        .rst  (rst),
        .h_cnt(h_cnt),  //horizontal counter
        .v_cnt(v_cnt)   //vertical counter
    );


    pixel_decoder #(
        .H_VISIBLE(H_VISIBLE),
        .H_FRONT  (H_FRONT),
        .H_SYNC   (H_SYNC),
        .H_BACK   (H_BACK),
        .V_VISIBLE(V_VISIBLE),
        .V_FRONT  (V_FRONT),
        .V_SYNC   (V_SYNC),
        .V_BACK   (V_BACK)
    ) U_PIXEL_DECODER (
        .h_cnt  (h_cnt),
        .v_cnt  (v_cnt),
        .h_sync (h_sync),
        .v_sync (v_sync),
        .DE     (DE),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel)
    );

endmodule
