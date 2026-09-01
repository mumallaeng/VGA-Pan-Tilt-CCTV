`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer:Jong.W.Park 
// Create Date: 2026/07/03 08:46:55
// Module Name: pixel_decoder
//////////////////////////////////////////////////////////////////////////////////


module pixel_decoder #(
    //horizontal
     parameter int H_VISIBLE = 640,
    parameter int H_FRONT   = 16,
    parameter int H_SYNC    = 96,
    parameter int H_BACK    = 48,
    //vertical
    parameter int V_VISIBLE = 480,
    parameter int V_FRONT   = 10,
    parameter int V_SYNC    = 2,
    parameter int V_BACK    = 33
) (
    input  logic [9:0] h_cnt,
    input  logic [9:0] v_cnt,
    output logic       h_sync,
    output logic       v_sync,
    output logic       DE,
    output logic [9:0] x_pixel,
    output logic [9:0] y_pixel
);

    localparam int H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
    localparam int V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

    localparam int H_SYNC_START = H_VISIBLE + H_FRONT;
    localparam int H_SYNC_END   = H_SYNC_START + H_SYNC;

    localparam int V_SYNC_START = V_VISIBLE + V_FRONT;
    localparam int V_SYNC_END   = V_SYNC_START + V_SYNC;
    

    assign h_sync = ~((h_cnt >= H_SYNC_START) && (h_cnt < H_SYNC_END));  //96 pixel
    assign v_sync = ~((v_cnt >= V_SYNC_START) && (v_cnt < V_SYNC_END));  //480 pixel

    assign DE = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

    assign x_pixel = h_cnt;
    assign y_pixel = v_cnt;

endmodule
