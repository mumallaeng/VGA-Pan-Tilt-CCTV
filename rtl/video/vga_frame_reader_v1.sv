`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Jong.W.Park
// Create Date: 2026/07/12 22:19:07
// Module Name: vga_frame_reader
//////////////////////////////////////////////////////////////////////////////////

module vga_frame_reader #(
    parameter IMG_WIDTH  = 320,
    parameter IMG_HEIGHT = 240,
    parameter ADDR_WIDTH = 17
) (
    //global signals
    input  logic                     clk,
    input  logic                     rst,
    input  logic [              1:0] vga_sw,
    //output from vga_core
    input  logic [              9:0] vga_x,
    input  logic [              9:0] vga_y,
    input  logic                     video_on,
    //frame_buffer read side
    output logic [ADDR_WIDTH -1 : 0] fb_raddr,
    input  logic [             15:0] fb_rdata,
    //VGA RGB444 output
    output logic [              3:0] vga_r,
    output logic [              3:0] vga_g,
    output logic [              3:0] vga_b
);

    localparam FRAME_SIZE = IMG_HEIGHT * IMG_WIDTH;

    logic [           8:0] img_x;  // 0-319
    logic [           7:0] img_y;  // 0-239

    logic                  pixel_valid;
    logic                  pixel_valid_d;
    logic                  mode_active;
    logic [ADDR_WIDTH-1:0] addr_calc;
    logic [           1:0] vga_sw_meta;
    logic [           1:0] vga_sw_sync;

    typedef enum logic [1:0] {
        MODE_ORIGINAL   = 2'b00,  // 320x240, top-left
        MODE_FULLSCREEN = 2'b01,  // 640x480, 2x enlargement
        MODE_SPLIT      = 2'b10,  // four 320x240 copies
        MODE_BLACK      = 2'b11   // black
    } vga_mode_e;

    vga_mode_e vga_mode;

    // Synchronize the asynchronous board switches to the VGA pixel clock.
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

    always_comb begin : vga_sw_mode_sel
        img_x       = 9'd0;
        img_y       = 8'd0;
        mode_active = 1'b0;

        case (vga_mode)
            MODE_ORIGINAL: begin
                if ((vga_x < 320) && (vga_y < 240)) begin
                    img_x       = vga_x[8:0];
                    img_y       = vga_y[7:0];
                    mode_active = 1'b1;
                end
            end
            MODE_FULLSCREEN: begin
                if ((vga_x < 640) && (vga_y < 480)) begin
                    img_x       = vga_x[9:1];
                    img_y       = vga_y[8:1];
                    mode_active = 1'b1;
                end
            end
            MODE_SPLIT: begin
                if ((vga_x < 640) && (vga_y < 480)) begin
                    if (vga_x < 320) img_x = vga_x[8:0];
                    else img_x = vga_x - 10'd320;

                    if (vga_y < 240) img_y = vga_y[7:0];
                    else img_y = vga_y - 10'd240;

                    mode_active = 1'b1;
                end
            end
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

    // addr = img_y * 320 + img_x. IMG_WIDTH is constant, so synthesis
    // implements the multiplication as constant arithmetic.
    assign addr_calc   = (img_y * IMG_WIDTH) + img_x;
    assign pixel_valid = video_on && mode_active;
    // ------------------------------------------------------------
    //frame buffer read address
    // BRAM read latency => delay the selected-mode valid signal by one clock.
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fb_raddr      <= '0;
            pixel_valid_d <= 1'b0;
        end else begin
            pixel_valid_d <= pixel_valid;

            if (pixel_valid) begin
                if (addr_calc < FRAME_SIZE) fb_raddr <= addr_calc;
            end else begin
                fb_raddr <= '0;
            end
        end
    end
    // ------------------------------------------------------------
    //RGB565 -> RGB444
    // ------------------------------------------------------------
    always_comb begin
        if (pixel_valid_d) begin
            vga_r = fb_rdata[15:12];
            vga_g = fb_rdata[10:7];
            vga_b = fb_rdata[4:1];
        end else begin
            vga_r = 4'd0;
            vga_g = 4'd0;
            vga_b = 4'd0;
        end
    end
endmodule
