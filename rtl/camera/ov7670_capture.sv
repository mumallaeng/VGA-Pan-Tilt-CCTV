`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Jong.W.Park 
// Create Date: 2026/07/10 17:59:24
// Module Name: ov7670_capture
//////////////////////////////////////////////////////////////////////////////////

module ov7670_capture #(
    parameter IMG_WIDTH = 320,
    parameter IMG_HEIGHT = 240,
    parameter ADDR_WIDTH = 17,
    parameter VSYNC_ACTIVE = 1'b1
) (
    input logic       pclk,
    input logic       rst,
    input logic       vsync,
    input logic       href,
    input logic [7:0] cam_data,

    output logic                    fb_we,
    output logic [ADDR_WIDTH - 1:0] fb_waddr,
    output logic [            15:0] fb_wdata
);

    localparam TOTAL_PIXEL = IMG_HEIGHT * IMG_WIDTH;

    typedef enum logic [2:0] {
        S_IDLE,
        S_WATE_LINE,
        S_BYTE_HIGH,
        S_BYTE_LOW,
        S_WAIT_LINE_END
    } capture_state_e;

    capture_state_e state, n_state;

    logic [7:0] high_byte, n_high_byte;

    logic [9:0] x_cnt, n_x_cnt;
    logic [9:0] y_cnt, n_y_cnt;

    logic [ADDR_WIDTH-1:0] addr_cnt;
    logic [ADDR_WIDTH-1:0] n_addr_cnt;

    logic                  n_fb_we;
    logic [ADDR_WIDTH-1:0] n_fb_waddr;
    logic [          15:0] n_fb_wdata;

    logic                  frame_sync;
    assign frame_sync = (vsync == VSYNC_ACTIVE);

    always_ff @(posedge pclk or posedge rst) begin : state_register
        if (rst) begin
            state     <= S_IDLE;
            high_byte <= 8'd0;

            x_cnt     <= 10'd0;
            y_cnt     <= 9'd0;
            addr_cnt  <= '0;

            fb_we     <= 1'b0;
            fb_waddr  <= '0;
            fb_wdata  <= 16'd0;
        end else begin
            state     <= n_state;
            high_byte <= n_high_byte;

            x_cnt     <= n_x_cnt;
            y_cnt     <= n_y_cnt;
            addr_cnt  <= n_addr_cnt;

            fb_we     <= n_fb_we;
            fb_waddr  <= n_fb_waddr;
            fb_wdata  <= n_fb_wdata;
        end
    end

    always_comb begin : datapath
        n_state     = state;
        n_high_byte = high_byte;

        n_x_cnt     = x_cnt;
        n_y_cnt     = y_cnt;
        n_addr_cnt  = addr_cnt;

        n_fb_we     = 1'b0;  //initial value is 0

        n_fb_waddr  = fb_waddr;
        n_fb_wdata  = fb_wdata;

        if (frame_sync) begin
            n_state = S_IDLE;
            n_x_cnt    = 10'd0;
            n_y_cnt    = 9'd0;
            n_addr_cnt = '0;

            n_fb_we    = 1'b0;
            n_fb_waddr = '0;
            n_fb_wdata = 16'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    n_x_cnt    = 10'd0;
                    n_y_cnt    = 9'd0;
                    n_addr_cnt = '0;

                    n_state = S_WATE_LINE;
                end
                S_WATE_LINE: begin
                    // Capture the first byte on the first PCLK edge for
                    // which HREF is high. Otherwise one byte is lost on
                    // every line and only 319 pixels are written.
                    if (href) begin
                        n_high_byte = cam_data;
                        n_state     = S_BYTE_LOW;
                    end
                end
                S_BYTE_HIGH: begin
                    if (!href) begin
                        n_x_cnt = 10'd0;
                        if (y_cnt < IMG_HEIGHT - 1) n_y_cnt = y_cnt + 1'b1;
                        n_state = S_WATE_LINE;
                    end else begin
                        n_high_byte = cam_data;
                        n_state = S_BYTE_LOW;
                    end
                end
                S_BYTE_LOW: begin
                    if (!href) begin
                        n_x_cnt = 10'd0;
                        if (y_cnt < IMG_HEIGHT - 1) n_y_cnt = y_cnt + 1'b1;
                        n_state = S_WATE_LINE;
                    end else begin
                        if((x_cnt<IMG_WIDTH) && (y_cnt < IMG_HEIGHT)&& (addr_cnt < TOTAL_PIXEL)) begin
                            n_fb_we = 1'b1;
                            n_fb_waddr = addr_cnt;
                            n_fb_wdata = {high_byte, cam_data};

                            n_addr_cnt = addr_cnt + 1'b1;
                        end
                        if (x_cnt < IMG_WIDTH - 1) begin
                            n_x_cnt = x_cnt + 1'b1;
                            n_state = S_BYTE_HIGH;
                        end else begin
                            n_x_cnt = 10'd0;
                            if (y_cnt < IMG_HEIGHT - 1) n_y_cnt = y_cnt + 1'b1;
                            // If the camera is still in VGA mode it sends
                            // 1280 bytes per physical line. Ignore everything
                            // after IMG_WIDTH pixels until HREF goes low.
                            n_state = S_WAIT_LINE_END;
                        end
                    end

                end
                S_WAIT_LINE_END: begin
                    n_x_cnt = 10'd0;
                    if (!href) n_state = S_WATE_LINE;
                end
                default: n_state = S_IDLE;
            endcase
        end
    end
endmodule
