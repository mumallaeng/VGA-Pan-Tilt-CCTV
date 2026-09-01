`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: ov7670_vga_top
// Description: OV7670 QVGA RGB565 capture to a 640x480 VGA display.
//////////////////////////////////////////////////////////////////////////////////

module ov7670_vga_top (
    input logic       clk,
    input logic       reset,
    input logic [1:0] vga_sw,

    input  logic       ov7670_pclk,
    input  logic       ov7670_vsync,
    input  logic       ov7670_href,
    input  logic [7:0] ov7670_data,
    output logic       ov7670_xclk,
    output logic       SCL,
    inout  wire        SDA,

    output logic       h_sync,
    output logic       v_sync,
    output logic [3:0] r_port,
    output logic [3:0] g_port,
    output logic [3:0] b_port
);

    logic        sccb_start;
    logic [ 7:0] sccb_reg_addr;
    logic [ 7:0] sccb_reg_data;
    logic        sccb_busy;
    logic        sccb_done;
    logic        sccb_ack_error;
    logic        init_done;
    logic [ 6:0] init_index;

    logic        init_done_meta;
    logic        init_done_pclk;
    logic        capture_rst;

    logic        fb_wr_en;
    logic [16:0] fb_wr_addr;
    logic [15:0] fb_wr_data;
    logic [16:0] fb_rd_addr;
    logic [15:0] fb_rd_data;

    logic        vga_pclk;
    logic        video_on;
    logic [ 9:0] x_pixel;
    logic [ 9:0] y_pixel;

    ov7670_xclk_gen U_OV7670_XCLK_GEN (
        .clk_100MHz(clk),
        .rst       (reset),
        .ov_xclk   (ov7670_xclk)
    );

    ov7670_sccb_master U_OV7670_SCCB_MASTER (
        .clk_100MHz(clk),
        .rst       (reset),
        .start     (sccb_start),
        .reg_addr  (sccb_reg_addr),
        .reg_data  (sccb_reg_data),
        .busy      (sccb_busy),
        .done      (sccb_done),
        .ack_error (sccb_ack_error),
        .ov_sioc   (SCL),
        .ov_siod   (SDA)
    );

    ov7670_reg_init U_OV7670_REG_INIT (
        .clk_100MHz   (clk),
        .rst          (reset),
        .sccb_start   (sccb_start),
        .sccb_reg_addr(sccb_reg_addr),
        .sccb_reg_data(sccb_reg_data),
        .sccb_busy    (sccb_busy),
        .sccb_done    (sccb_done),
        .init_done    (init_done),
        .init_index   (init_index)
    );

    // Synchronize the initialization flag before releasing the PCLK logic.
    always_ff @(posedge ov7670_pclk or posedge reset) begin
        if (reset) begin
            init_done_meta <= 1'b0;
            init_done_pclk <= 1'b0;
        end else begin
            init_done_meta <= init_done;
            init_done_pclk <= init_done_meta;
        end
    end

    assign capture_rst = reset | ~init_done_pclk;

    ov7670_capture #(
        .IMG_WIDTH   (320),
        .IMG_HEIGHT  (240),
        .ADDR_WIDTH  (17),
        .VSYNC_ACTIVE(1'b1)
    ) U_OV7670_CAPTURE (
        .pclk    (ov7670_pclk),
        .rst     (capture_rst),
        .vsync   (ov7670_vsync),
        .href    (ov7670_href),
        .cam_data(ov7670_data),
        .fb_we   (fb_wr_en),
        .fb_waddr(fb_wr_addr),
        .fb_wdata(fb_wr_data)
    );

    frame_buffer #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240),
        .DATA_WIDTH(16),
        .ADDR_WIDTH(17)
    ) U_FRAME_BUFFER (
        .wr_clk (ov7670_pclk),
        .wr_en  (fb_wr_en),
        .wr_addr(fb_wr_addr),
        .wr_data(fb_wr_data),
        .rd_clk (vga_pclk),
        .rd_addr(fb_rd_addr),
        .rd_data(fb_rd_data)
    );

    vga_core U_VGA_CORE (
        .clk    (clk),
        .rst    (reset),
        .pclk   (vga_pclk),
        .h_sync (h_sync),
        .v_sync (v_sync),
        .DE     (video_on),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel)
    );

    vga_frame_reader #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240),
        .ADDR_WIDTH(17)
    ) U_VGA_FRAME_READER (
        .clk     (vga_pclk),
        .rst     (reset),
        .vga_sw  (vga_sw),
        .vga_x   (x_pixel),
        .vga_y   (y_pixel),
        .video_on(video_on),
        .fb_raddr(fb_rd_addr),
        .fb_rdata(fb_rd_data),
        .vga_r   (r_port),
        .vga_g   (g_port),
        .vga_b   (b_port)
    );

endmodule
