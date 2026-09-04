`timescale 1ns / 1ps

module top (
    input        clk,
    input        rst,
    input  [1:0] vga_sw,
    input        red_filter_en,  // need to check RED filtering is working
    // Camera
    input        ov7670_pclk,
    input        ov7670_vsync,
    input        ov7670_href,
    input  [7:0] ov7670_data,
    output       ov7670_xclk,
    // I2C module
    output       scl,
    inout        sda,
    // VGA
    output       h_sync,
    output       v_sync,
    output [3:0] r_port,
    output [3:0] g_port,
    output [3:0] b_port
);
    // ov7670 camera related module & wire
    // =============================================
    // XCLK Generator for ov7670 camera
    // ---------------------------------------------
    ov7670_xclk_gen U_OV7670_XCLK_GEN (
        .clk_100MHz(clk),
        .rst       (rst),
        .ov_xclk   (ov7670_xclk)
    );

    // SCCB controller? maybe?
    // ---------------------------------------------
    wire sccb_start;
    wire [7:0] sccb_reg_addr;
    wire [7:0] sccb_reg_data;
    wire sccb_busy, sccb_done;
    wire init_done;

    ov7670_reg_init U_OV7670_REG_INIT (
        .clk_100MHz   (clk),
        .rst          (rst),
        .sccb_start   (sccb_start),
        .sccb_reg_addr(sccb_reg_addr),
        .sccb_reg_data(sccb_reg_data),
        .sccb_busy    (sccb_busy),
        .sccb_done    (sccb_done),
        .init_done    (init_done),
        .init_index   ()
    );

    // SCCB to setup camera
    // ---------------------------------------------
    ov7670_sccb_master U_OV7670_SCCB_MASTER (
        .clk_100MHz(clk),
        .rst       (rst),
        .start     (sccb_start),
        .reg_addr  (sccb_reg_addr),
        .reg_data  (sccb_reg_data),
        .busy      (sccb_busy),
        .done      (sccb_done),
        .ack_error (sccb_ack_error),
        .ov_sioc   (scl),
        .ov_siod   (sda)
    );

    // Synchronize the initialization flag before releasing the PCLK logic.
    // ---------------------------------------------
    reg init_done_meta, init_done_pclk, capture_rst;
    always_ff @(posedge ov7670_pclk or posedge rst) begin
        if (rst) begin
            init_done_meta <= 1'b0;
            init_done_pclk <= 1'b0;
            capture_rst    <= 1'b1;
        end else begin
            init_done_meta <= init_done;
            init_done_pclk <= init_done_meta;
            // Keep assertion asynchronous through the rst pin above, but
            // release capture only on an OV7670 PCLK edge.
            capture_rst    <= ~init_done_pclk;
        end
    end

    // control frame buffer write operation according to ov7670
    // ---------------------------------------------
    wire fb_wr_en;
    wire [16:0] fb_wr_addr;
    wire [15:0] fb_wr_data;

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
    // =============================================

    // Frame buffer (CDC)
    // =============================================
    wire vga_pclk;
    wire [16:0] fb_rd_addr;
    wire [15:0] fb_rd_data;

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
    // =============================================

    // VGA part
    // =============================================
    // VGA core
    // ---------------------------------------------
    wire video_on;
    wire h_sync_raw, v_sync_raw;
    wire [9:0] x_pixel;
    wire [9:0] y_pixel;

    vga_core U_VGA_CORE (
        .clk    (clk),
        .rst    (rst),
        .pclk   (vga_pclk),
        .h_sync (h_sync_raw),
        .v_sync (v_sync_raw),
        .DE     (video_on),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel)
    );

    // VGA Frame Reader
    // ---------------------------------------------
    wire box_en_raw;
    reg box_en_aligned;
    wire [8:0] img_x;
    wire [7:0] img_y;
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire [3:0] original_r;
    wire [3:0] original_g;
    wire [3:0] original_b;
    wire [15:0] display_rgb565;
    wire display_pixel_valid;
    wire split_mode_aligned;
    wire quadrant_4_aligned;

    vga_frame_reader_v4 U_VGA_FRAME_READER (
        .clk               (vga_pclk),
        .rst               (rst),
        .vga_sw            (vga_sw),
        .vga_x             (x_pixel),
        .vga_y             (y_pixel),
        .video_on          (video_on),
        .box_en            (box_en_aligned),
        .fb_raddr          (fb_rd_addr),
        .fb_rdata          (fb_rd_data),
        .img_x             (img_x),
        .img_y             (img_y),
        .vga_r             (vga_r),
        .vga_g             (vga_g),
        .vga_b             (vga_b),
        .pixel_rgb565      (display_rgb565),
        .pixel_valid       (display_pixel_valid),
        .split_mode_aligned(split_mode_aligned),
        .quadrant_4_aligned(quadrant_4_aligned)
    );

    // Red filter
    // ---------------------------------------------
    wire [3:0] red_r;
    wire [3:0] red_g;
    wire [3:0] red_b;
    green_color_filter U_RED_COLOR_FILTER (
        .pixel_rgb565(display_rgb565),
        .pixel_valid (display_pixel_valid),
        .vga_r       (vga_r),
        .vga_g       (vga_g),
        .vga_b       (vga_b),
        .green_mask  (red_mask),
        .green_valid (red_valid),
        .original_r  (original_r),
        .original_g  (original_g),
        .original_b  (original_b),
        .green_r     (red_r),
        .green_g     (red_g),
        .green_b     (red_b)
    );


    // Noise filter
    // ---------------------------------------------
    wire clean_mask;
    wire [8:0] clean_x;
    wire [7:0] clean_y;
    wire out_valid;
    noise_filter_3x3 U_NOISE_FILTER (
        .pclk      (vga_pclk),
        .rst       (rst),
        .red_valid (red_valid),
        .red_mask  (red_mask),
        .pixel_x   (img_x),
        .pixel_y   (img_y),
        .clean_mask(clean_mask),
        .clean_x   (clean_x),
        .clean_y   (clean_y),
        .out_valid (out_valid)
    );

    // Min/Max filter? calculate?
    // ---------------------------------------------
    wire target_valid_in, done;
    wire [8:0] max_x, min_x;
    wire [7:0] max_y, min_y;
    min_max_find U_MIN_MAX_FIND (
        .pclk           (vga_pclk),
        .rst            (rst),
        .clean_mask     (clean_mask),
        .out_valid      (out_valid),
        .clean_x        (clean_x),
        .clean_y        (clean_y),
        .target_valid_in(target_valid_in),
        .min_x          (min_x),
        .max_x          (max_x),
        .min_y          (min_y),
        .max_y          (max_y),
        .done           (done)
    );

    // Draw bounding box logic
    // ---------------------------------------------
    draw_box U_DRAW_BOX (
        .pclk           (vga_pclk),
        .rst            (rst),
        .target_valid_in(target_valid_in),
        .done           (done),
        .x_pixel        (x_pixel),
        .y_pixel        (y_pixel),
        .max_x          (max_x),
        .min_x          (min_x),
        .max_y          (max_y),
        .min_y          (min_y),
        .box_en         (box_en_raw)
    );

    // Realign box_en with the 1-clock BRAM read latency that fb_rdata/
    // pixel_valid_d (and img_x/img_y) already carry inside
    // vga_frame_reader_v4. Without this the border lands one pixel_clk
    // ahead of the image data it is supposed to sit on top of.
    always_ff @(posedge vga_pclk or posedge rst) begin
        if (rst) box_en_aligned <= 1'b0;
        else box_en_aligned <= box_en_raw;
    end

    // Synchronizer to match timing or solve CDC problem
    // Align VGA synchronization with the one-clock frame-buffer read path.
    localparam LATENCY = 2;
    reg [LATENCY-1:0] h_sync_reg, v_sync_reg;
    always_ff @(posedge vga_pclk or posedge rst) begin
        if (rst) begin
            h_sync_reg <= 0;
            v_sync_reg <= 0;
        end else begin
            h_sync_reg <= {h_sync_reg[LATENCY-2:0], h_sync_raw};
            v_sync_reg <= {v_sync_reg[LATENCY-2:0], v_sync_raw};
        end
    end

    assign h_sync = h_sync_reg[LATENCY-1];
    assign v_sync = v_sync_reg[LATENCY-1];


    // Split mode: Q4 is the red mask and Q1/Q2/Q3 remain original.
    // Other modes: filter_sw selects original or binary red mask globally.
    wire [3:0] r_port_next, g_port_next, b_port_next;

    display_control U_DISPLAY_CONTROL (
        .split_mode_aligned(split_mode_aligned),
        .quadrant_4_aligned(quadrant_4_aligned),
        .red_filter_en     (red_filter_en),
        .out_valid         (out_valid),
        .clean_mask        (clean_mask),
        .original_r        (original_r),
        .original_g        (original_g),
        .original_b        (original_b),
        .red_r             (red_r),
        .red_g             (red_g),
        .red_b             (red_b),
        .r_port_next       (r_port_next),
        .g_port_next       (g_port_next),
        .b_port_next       (b_port_next)
    );


    rgb_out_reg U_RGB_OUT_REG (
        .clk        (clk),
        .rst        (rst),
        .r_port_next(r_port_next),
        .g_port_next(g_port_next),
        .b_port_next(b_port_next),
        .r_port     (r_port),
        .g_port     (g_port),
        .b_port     (b_port)
    );

endmodule

module display_control (
    input            split_mode_aligned,
    input            quadrant_4_aligned,
    input            red_filter_en,
    input            out_valid,
    input            clean_mask,
    input      [3:0] original_r,
    input      [3:0] original_g,
    input      [3:0] original_b,
    input      [3:0] red_r,
    input      [3:0] red_g,
    input      [3:0] red_b,
    output reg [3:0] r_port_next,
    output reg [3:0] g_port_next,
    output reg [3:0] b_port_next
);

    always_comb begin
        if (split_mode_aligned) begin
            if (quadrant_4_aligned) begin
                r_port_next = red_r & {4{clean_mask}} & {4{out_valid}};
                g_port_next = red_g & {4{clean_mask}} & {4{out_valid}};
                b_port_next = red_b & {4{clean_mask}} & {4{out_valid}};
            end else begin
                r_port_next = original_r;
                g_port_next = original_g;
                b_port_next = original_b;
            end
        end else begin
            if (red_filter_en) begin
                r_port_next = red_r;
                g_port_next = red_g;
                b_port_next = red_b;
            end else begin
                r_port_next = original_r;
                g_port_next = original_g;
                b_port_next = original_b;
            end
        end
    end

endmodule

module rgb_out_reg (
    input            clk,
    input            rst,
    input      [3:0] r_port_next,
    input      [3:0] g_port_next,
    input      [3:0] b_port_next,
    output reg [3:0] r_port,
    output reg [3:0] g_port,
    output reg [3:0] b_port
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r_port <= 0;
            g_port <= 0;
            b_port <= 0;
        end else begin
            r_port <= r_port_next;
            g_port <= g_port_next;
            b_port <= b_port_next;
        end
    end

endmodule
