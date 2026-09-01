`timescale 1ns / 1ps

module box_coordinate (
    input        pclk,
    input        rst,
    input        target_valid,
    input  [9:0] x_pixel,
    input  [9:0] y_pixel,
    input  [8:0] max_x,
    input  [8:0] min_x,
    input  [7:0] max_y,
    input  [7:0] min_y,
    output [8:0] draw_x,
    output [7:0] draw_y
);
    reg [8:0] x_cnt, x_next;
    reg [7:0] y_cnt, y_next;
    // latching max/min x/y value
    reg [8:0] max_x_reg, max_x_next;
    reg [8:0] min_x_reg, min_x_next;
    reg [7:0] max_y_reg, max_y_next;
    reg [7:0] min_y_reg, min_y_next;

    // count x & y coordinate
    always @(posedge pclk or posedge rst) begin
        if (rst) begin
            x_cnt     <= 0;
            y_cnt     <= 0;
            max_x_reg <= 0;
            min_x_reg <= 0;
            max_y_reg <= 0;
            min_y_reg <= 0;
        end else begin
            x_cnt     <= x_next;
            y_cnt     <= y_next;
            max_x_reg <= max_x_next;
            min_x_reg <= min_x_next;
            max_y_reg <= max_y_next;
            min_y_reg <= min_y_next;
        end
    end

    // Calculate current coordinate is in bounding box range
    wire x_en, y_en;
    assign x_en = (x_pixel[9:1] < max_x) & (x_pixel[9:1] >= min_x);
    assign y_en = (y_pixel[9:1] < max_y) & (y_pixel[9:1] >= min_y);

    // next coordinate logic
    always @(*) begin
        x_next     = min_x;
        y_next     = min_y;
        max_x_next = max_x_reg;
        min_x_next = min_x_reg;
        max_y_next = max_y_reg;
        min_y_next = min_y_reg;

        if (target_valid) begin
            if (x_en & y_en) begin
                x_next = x_cnt + 1;
                y_next = y_cnt;
                if (x_cnt == max_x_reg - 1) begin
                    x_next = min_x_reg;
                    y_next = y_cnt + 1;
                    if (y_cnt == max_y_reg - 1) begin
                        y_next     = min_y_reg;
                        max_x_next = max_x;
                        min_x_next = min_x;
                        max_y_next = max_y;
                        min_y_next = min_y;
                    end
                end
            end
        end
    end

    // Output logic
    assign draw_x = x_cnt;
    assign draw_y = y_cnt;

endmodule
