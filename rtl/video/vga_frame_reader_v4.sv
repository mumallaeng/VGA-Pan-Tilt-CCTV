`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////

// Engineer: Jong.W.Park
// Create Date: 2026/09/01 07:41:40
// Module Name: vga_frame_reader_v3
//
//   Reads a 320x240 RGB565 frame buffer and displays it on VGA.
//   Also provides the exact RGB565 pixel stream used for VGA display
//   so that image-processing modules can use the same pixel timing.
//////////////////////////////////////////////////////////////////////////////////

module vga_frame_reader_v4 #(
    parameter IMG_WIDTH  = 320,
    parameter IMG_HEIGHT = 240,
    parameter ADDR_WIDTH = 17
) (
    // Global signals
    input  wire                   clk,
    input  wire                   rst,
    input  wire  [           1:0] vga_sw,
    // Output from vga_core
    input  wire  [           9:0] vga_x,
    input  wire  [           9:0] vga_y,
    input  wire                   video_on,
    // Output from draw_box
    input                         box_en,
    // Frame-buffer read side
    output logic [ADDR_WIDTH-1:0] fb_raddr,
    input  wire  [          15:0] fb_rdata,
    // VGA RGB444 output
    output logic [           3:0] vga_r,
    output logic [           3:0] vga_g,
    output logic [           3:0] vga_b,
    // RGB565 pixel stream for image processing
    output logic [          15:0] pixel_rgb565,
    output logic                  pixel_valid,
    // Display-region controls aligned with pixel_rgb565/pixel_valid
    output logic                  split_mode_aligned,
    output logic                  quadrant_4_aligned
);

    localparam FRAME_SIZE = IMG_HEIGHT * IMG_WIDTH;

    logic [           8:0] img_x;  // 0-319
    logic [           7:0] img_y;  // 0-239
    // Valid for requesting a pixel from the frame buffer.
    logic                  pixel_req_valid;
    // Delayed valid aligned with fb_rdata.
    logic                  pixel_valid_d;
    logic                  split_mode_req;
    logic                  quadrant_4_req;
    logic                  mode_active;
    logic [ADDR_WIDTH-1:0] addr_calc;
    logic [           1:0] vga_sw_meta;
    logic [           1:0] vga_sw_sync;


    typedef enum logic [1:0] {
        MODE_ORIGINAL   = 2'b00,  // 320x240, top-left
        MODE_FULLSCREEN = 2'b01,  // 640x480, 2x enlargement
        MODE_SPLIT      = 2'b10,  // Four 320x240 copies
        MODE_BLACK      = 2'b11   // Black screen
    } vga_mode_e;

    vga_mode_e vga_mode;


    // ============================================================
    // Synchronize asynchronous board switches to VGA pixel clock
    // ============================================================

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vga_sw_meta <= 2'b00;
            vga_sw_sync <= 2'b00;
        end else begin
            vga_sw_meta <= vga_sw;
            vga_sw_sync <= vga_sw_meta;
        end
    end

    assign vga_mode = vga_mode_e'(vga_sw_sync);


    // ============================================================
    // VGA mode / source-image coordinate selection
    // ============================================================

    always_comb begin : vga_sw_mode_sel

        img_x       = 9'd0;
        img_y       = 8'd0;
        mode_active = 1'b0;

        case (vga_mode)

            // ----------------------------------------------------
            // 320x240 image at the top-left corner
            // ----------------------------------------------------
            MODE_ORIGINAL: begin
                if ((vga_x < 320) && (vga_y < 240)) begin
                    img_x       = vga_x[8:0];
                    img_y       = vga_y[7:0];
                    mode_active = 1'b1;
                end
            end


            // ----------------------------------------------------
            // 320x240 -> 640x480
            // Each source pixel is displayed as a 2x2 block.
            // ----------------------------------------------------
            MODE_FULLSCREEN: begin
                if ((vga_x < 640) && (vga_y < 480)) begin
                    img_x       = vga_x[9:1];
                    img_y       = vga_y[8:1];
                    mode_active = 1'b1;
                end
            end


            // ----------------------------------------------------
            // Four copies of the 320x240 image
            // ----------------------------------------------------
            MODE_SPLIT: begin
                if ((vga_x < 640) && (vga_y < 480)) begin

                    if (vga_x < 320) img_x = vga_x[8:0];
                    else img_x = vga_x - 10'd320;

                    if (vga_y < 240) img_y = vga_y[7:0];
                    else img_y = vga_y - 10'd240;

                    mode_active = 1'b1;
                end
            end


            // ----------------------------------------------------
            // Black screen
            // ----------------------------------------------------
            MODE_BLACK: begin
                img_x       = 9'd0;
                img_y       = 8'd0;
                mode_active = 1'b0;
            end


            default: begin
                img_x       = 9'd0;
                img_y       = 8'd0;
                mode_active = 1'b0;
            end

        endcase

    end


    // ============================================================
    // Frame-buffer address calculation
    //
    // addr = img_y * IMG_WIDTH + img_x
    //
    // IMG_WIDTH is constant, so synthesis can optimize this
    // constant multiplication.
    // ============================================================

    assign addr_calc = (img_y * IMG_WIDTH) + img_x;


    // Valid request for the current VGA coordinate.
    assign pixel_req_valid = video_on && mode_active;

    // Mathematical screen quadrants: Q2=upper-left, Q4=lower-right.
    // Only Q4 selects the red mask in split mode; all other quadrants remain
    // original video. These request-side flags are delayed with BRAM data.
    assign split_mode_req = pixel_req_valid && (vga_mode == MODE_SPLIT);
    assign quadrant_4_req = split_mode_req &&
                            (vga_x >= 10'd320) && (vga_y >= 10'd240);


    // ============================================================
    // Frame-buffer read address
    //
    // frame_buffer registers rd_data once. Keep fb_raddr combinational so
    // the request-to-data path is exactly one clock, matching valid below.
    // ============================================================

    always_comb begin
        fb_raddr = '0;
        if (pixel_req_valid && (addr_calc < FRAME_SIZE)) begin
            fb_raddr = addr_calc;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pixel_valid_d      <= 1'b0;
            split_mode_aligned <= 1'b0;
            quadrant_4_aligned <= 1'b0;
        end else begin
            pixel_valid_d      <= pixel_req_valid;
            split_mode_aligned <= split_mode_req;
            quadrant_4_aligned <= quadrant_4_req;
        end
    end


    // ============================================================
    // RGB565 pixel stream + RGB444 VGA conversion
    //
    // pixel_rgb565 and VGA RGB outputs use the SAME fb_rdata.
    //
    // Therefore:
    //
    //   pixel_rgb565[15:11] = Red
    //   pixel_rgb565[10:5]  = Green
    //   pixel_rgb565[4:0]   = Blue
    //
    // The image-processing stream is aligned to the same valid
    // timing used by the displayed VGA pixel.
    // ============================================================

    always_comb begin

        // Default outputs
        vga_r = 4'd0;
        vga_g = 4'd0;
        vga_b = 4'd0;

        pixel_rgb565 = 16'h0000;
        pixel_valid = 1'b0;


        if (pixel_valid_d) begin

            // ----------------------------------------------------
            // Exact RGB565 pixel used for image processing
            // ----------------------------------------------------
            pixel_rgb565 = fb_rdata;
            pixel_valid = 1'b1;


            // ----------------------------------------------------
            // RGB565 -> RGB444
            //
            // RGB565:
            //   RRRRR GGGGGG BBBBB
            //
            // RGB444:
            //   RRRR GGGG BBBB
            //
            // Use the upper bits of each channel.
            // ----------------------------------------------------
            // <Edited by Donghyun Kim>
            vga_r = box_en ? 4'hf : fb_rdata[15:12];
            vga_g = box_en ? 4'h0 : fb_rdata[10:7];
            vga_b = box_en ? 4'h0 : fb_rdata[4:1];
            // <Done edited by Donghyun Kim>
        end

    end

endmodule
