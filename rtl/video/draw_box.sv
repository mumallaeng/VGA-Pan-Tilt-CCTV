`timescale 1ns / 1ps

module draw_box #(
    parameter THICKNESS = 2
) (
    input        pclk,
    input        rst,
    input        target_valid_in,
    input        done,
    input  [9:0] x_pixel,
    input  [9:0] y_pixel,
    input  [8:0] max_x,
    input  [8:0] min_x,
    input  [7:0] max_y,
    input  [7:0] min_y,
    output       box_en
);
    // Register to latching max/min x/y data
    reg [8:0] draw_max_x, draw_max_x_next;
    reg [8:0] draw_min_x, draw_min_x_next;
    reg [7:0] draw_max_y, draw_max_y_next;
    reg [7:0] draw_min_y, draw_min_y_next;

    always @(posedge pclk or posedge rst) begin
        if (rst) begin
            draw_max_x <= 0;
            draw_min_x <= 0;
            draw_max_y <= 0;
            draw_min_y <= 0;
        end else begin
            draw_max_x <= draw_max_x_next;
            draw_min_x <= draw_min_x_next;
            draw_max_y <= draw_max_y_next;
            draw_min_y <= draw_min_y_next;
        end
    end
    // next max/min x/y value
    always @(*) begin
        draw_max_x_next = draw_max_x;
        draw_min_x_next = draw_min_x;
        draw_max_y_next = draw_max_y;
        draw_min_y_next = draw_min_y;
        if (done) begin
            draw_max_x_next = max_x;
            draw_min_x_next = min_x;
            draw_max_y_next = max_y;
            draw_min_y_next = min_y;
        end
    end

    // check camera image is in boundary
    wire x_in, y_in;
    wire inbound;
    assign x_in = (x_pixel[9:1] >= draw_min_x) & (x_pixel[9:1] < draw_max_x);
    assign y_in = (y_pixel[8:1] >= draw_min_y) & (y_pixel[8:1] < draw_max_y);
    assign inbound = x_in & y_in;

    // enable signal to select raw image or Red image
    wire x_edge, y_edge;
    wire border;

    assign x_edge = (x_pixel[9:1] < draw_min_x + THICKNESS) | (x_pixel[9:1] + THICKNESS >= draw_max_x);
    assign y_edge = (y_pixel[8:1] < draw_min_y + THICKNESS) | (y_pixel[8:1] + THICKNESS >= draw_max_y);
    assign border = inbound & (x_edge | y_edge);

    assign box_en = target_valid_in & border;

endmodule
