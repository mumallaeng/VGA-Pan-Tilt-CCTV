`timescale 1ns / 1ps
`default_nettype none

module ov7670_vga_green_top (
    input wire       clk,
    input wire       reset,
    input wire [1:0] vga_sw,
    input wire       filter_sw,
    input  wire        ov7670_pclk,
    input  wire        ov7670_vsync,
    input  wire        ov7670_href,
    input  wire  [7:0] ov7670_data,
    output logic       ov7670_xclk,
    output logic       SCL,
    inout  wire        SDA,
    output logic       h_sync,
    output logic       v_sync,
    output logic [3:0] r_port,
    output logic [3:0] g_port,
    output logic [3:0] b_port
);
    logic sccb_start;
    logic [7:0] sccb_reg_addr, sccb_reg_data;
    logic sccb_busy, sccb_done, sccb_ack_error, init_done;
    logic [6:0] init_index;
    (* ASYNC_REG = "TRUE" *) logic init_done_meta, init_done_pclk;
    logic capture_rst;
    logic fb_wr_en;
    logic [16:0] fb_wr_addr, fb_rd_addr;
    logic [15:0] fb_wr_data, fb_rd_data;
    logic vga_pclk, video_on, h_sync_raw, v_sync_raw;
    logic [9:0] x_pixel, y_pixel;
    logic [15:0] display_rgb565;
    logic display_pixel_valid, split_mode_aligned, quadrant_4_aligned;
    logic [3:0] reader_r, reader_g, reader_b;
    logic [3:0] original_r, original_g, original_b;
    logic [3:0] mask_r, mask_g, mask_b;
    logic green_mask, green_valid;
    (* ASYNC_REG = "TRUE" *) logic filter_sw_meta, filter_sw_sync;

    ov7670_xclk_gen U_OV7670_XCLK_GEN (
        .clk_100MHz(clk), .rst(reset), .ov_xclk(ov7670_xclk)
    );

    ov7670_sccb_master U_OV7670_SCCB_MASTER (
        .clk_100MHz(clk), .rst(reset), .start(sccb_start),
        .reg_addr(sccb_reg_addr), .reg_data(sccb_reg_data),
        .busy(sccb_busy), .done(sccb_done), .ack_error(sccb_ack_error),
        .ov_sioc(SCL), .ov_siod(SDA)
    );

    ov7670_reg_init U_OV7670_REG_INIT (
        .clk_100MHz(clk), .rst(reset), .sccb_start(sccb_start),
        .sccb_reg_addr(sccb_reg_addr), .sccb_reg_data(sccb_reg_data),
        .sccb_busy(sccb_busy), .sccb_done(sccb_done),
        .init_done(init_done), .init_index(init_index)
    );

    always_ff @(posedge ov7670_pclk or posedge reset) begin
        if (reset) begin
            init_done_meta <= 1'b0;
            init_done_pclk <= 1'b0;
            capture_rst    <= 1'b1;
        end else begin
            init_done_meta <= init_done;
            init_done_pclk <= init_done_meta;
            capture_rst    <= ~init_done_pclk;
        end
    end

    ov7670_capture #(
        .IMG_WIDTH(320), .IMG_HEIGHT(240), .ADDR_WIDTH(17),
        .VSYNC_ACTIVE(1'b1)
    ) U_OV7670_CAPTURE (
        .pclk(ov7670_pclk), .rst(capture_rst), .vsync(ov7670_vsync),
        .href(ov7670_href), .cam_data(ov7670_data), .fb_we(fb_wr_en),
        .fb_waddr(fb_wr_addr), .fb_wdata(fb_wr_data)
    );

    frame_buffer #(
        .IMG_WIDTH(320), .IMG_HEIGHT(240), .DATA_WIDTH(16), .ADDR_WIDTH(17)
    ) U_FRAME_BUFFER (
        .wr_clk(ov7670_pclk), .wr_en(fb_wr_en), .wr_addr(fb_wr_addr),
        .wr_data(fb_wr_data), .rd_clk(vga_pclk), .rd_addr(fb_rd_addr),
        .rd_data(fb_rd_data)
    );

    vga_core U_VGA_CORE (
        .clk(clk), .rst(reset), .pclk(vga_pclk), .h_sync(h_sync_raw),
        .v_sync(v_sync_raw), .DE(video_on), .x_pixel(x_pixel), .y_pixel(y_pixel)
    );

    always_ff @(posedge vga_pclk or posedge reset) begin
        if (reset) begin
            h_sync <= 1'b1;
            v_sync <= 1'b1;
        end else begin
            h_sync <= h_sync_raw;
            v_sync <= v_sync_raw;
        end
    end

    always_ff @(posedge vga_pclk or posedge reset) begin
        if (reset) begin
            filter_sw_meta <= 1'b0;
            filter_sw_sync <= 1'b0;
        end else begin
            filter_sw_meta <= filter_sw;
            filter_sw_sync <= filter_sw_meta;
        end
    end

    vga_frame_reader_v3 #(
        .IMG_WIDTH(320), .IMG_HEIGHT(240), .ADDR_WIDTH(17)
    ) U_VGA_FRAME_READER (
        .clk(vga_pclk), .rst(reset), .vga_sw(vga_sw),
        .vga_x(x_pixel), .vga_y(y_pixel), .video_on(video_on),
        .fb_raddr(fb_rd_addr), .fb_rdata(fb_rd_data),
        .vga_r(reader_r), .vga_g(reader_g), .vga_b(reader_b),
        .pixel_rgb565(display_rgb565), .pixel_valid(display_pixel_valid),
        .split_mode_aligned(split_mode_aligned),
        .quadrant_4_aligned(quadrant_4_aligned)
    );

    green_color_filter U_GREEN_COLOR_FILTER (
        .pixel_rgb565(display_rgb565), .pixel_valid(display_pixel_valid),
        .vga_r(reader_r), .vga_g(reader_g), .vga_b(reader_b),
        .green_mask(green_mask), .green_valid(green_valid),
        .original_r(original_r), .original_g(original_g), .original_b(original_b),
        .green_r(mask_r), .green_g(mask_g), .green_b(mask_b)
    );

    always_comb begin
        if (split_mode_aligned) begin
            if (quadrant_4_aligned) begin
                r_port = mask_r;
                g_port = mask_g;
                b_port = mask_b;
            end else begin
                r_port = original_r;
                g_port = original_g;
                b_port = original_b;
            end
        end else if (filter_sw_sync) begin
            r_port = mask_r;
            g_port = mask_g;
            b_port = mask_b;
        end else begin
            r_port = original_r;
            g_port = original_g;
            b_port = original_b;
        end
    end
endmodule

`default_nettype wire
