`timescale 1ns / 1ps

module min_max_find #(
    parameter int IMG_WIDTH     = 320,
    parameter int IMG_HEIGHT    = 240,
    parameter int MIN_RED_COUNT = 10,
    parameter int COUNT_WIDTH   = $clog2(MIN_RED_COUNT + 1)
) (
    input logic pclk,
    input logic rst,

    input logic       clean_mask,
    input logic       out_valid,
    input logic [8:0] clean_x,
    input logic [7:0] clean_y,

    output logic       target_valid_in,
    output logic [8:0] min_x,
    output logic [8:0] max_x,
    output logic [7:0] min_y,
    output logic [7:0] max_y,
    output logic       done
);

    logic frame_start;
    logic frame_end;
    logic frame_end_d;
    logic frame_synced;
    logic pixel_hit;

    logic found_pixel;
    logic [COUNT_WIDTH-1:0] mask_count;

    logic [8:0] min_x_reg;
    logic [8:0] max_x_reg;
    logic [7:0] min_y_reg;
    logic [7:0] max_y_reg;

    assign frame_start = out_valid &&
                         (clean_x == 9'd0) &&
                         (clean_y == 8'd0);

    assign frame_end = frame_synced && out_valid &&
                       (clean_x == IMG_WIDTH - 1) &&
                       (clean_y == IMG_HEIGHT - 1);

    // Ignore pixels until a coordinate (0,0) frame boundary has been seen.
    assign pixel_hit = out_valid && clean_mask &&
                       (frame_synced || frame_start);

    always_ff @(posedge pclk or posedge rst) begin
        if (rst) begin
            frame_synced <= 1'b0;
            frame_end_d  <= 1'b0;
            found_pixel <= 1'b0;
            mask_count  <= '0;

            min_x_reg <= 9'd0;
            max_x_reg <= 9'd0;
            min_y_reg <= 8'd0;
            max_y_reg <= 8'd0;

            target_valid_in <= 1'b0;
            min_x <= 9'd0;
            max_x <= 9'd0;
            min_y <= 8'd0;
            max_y <= 8'd0;
            done  <= 1'b0;
        end else begin
            // Delay EOF so the last pixel first passes through the normal
            // accumulator path. Results are committed one pclk later.
            frame_end_d <= frame_end;
            done        <= 1'b0;

            if (frame_start) begin
                frame_synced <= 1'b1;
                found_pixel <= 1'b0;
                mask_count  <= '0;
            end

            if (pixel_hit) begin
                // The first detected pixel initializes all four bounds.
                if (frame_start || !found_pixel) begin
                    min_x_reg <= clean_x;
                    max_x_reg <= clean_x;
                    min_y_reg <= clean_y;
                    max_y_reg <= clean_y;
                    found_pixel <= 1'b1;
                end else begin
                    if (clean_x < min_x_reg) min_x_reg <= clean_x;
                    if (clean_x > max_x_reg) max_x_reg <= clean_x;
                    if (clean_y < min_y_reg) min_y_reg <= clean_y;
                    if (clean_y > max_y_reg) max_y_reg <= clean_y;
                end

                // Only the threshold result is required, so saturate here.
                if (frame_start) begin
                    mask_count <= {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
                end else if (mask_count < MIN_RED_COUNT) begin
                    mask_count <= mask_count + 1'b1;
                end
            end

            if (frame_end_d) begin
                done <= 1'b1;

                if (found_pixel && (mask_count >= MIN_RED_COUNT)) begin
                    target_valid_in <= 1'b1;
                    min_x <= min_x_reg;
                    max_x <= max_x_reg;
                    min_y <= min_y_reg;
                    max_y <= max_y_reg;
                end else begin
                    target_valid_in <= 1'b0;
                    min_x <= 9'd0;
                    max_x <= 9'd0;
                    min_y <= 8'd0;
                    max_y <= 8'd0;
                end
            end
        end
    end

endmodule
