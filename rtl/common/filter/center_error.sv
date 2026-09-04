`timescale 1ns / 1ps

module center_error (
    input  logic              pclk,
    input  logic              rst,
    input  logic              frame_done,
    input  logic              target_valid_out,
    input  logic        [8:0] target_x,
    input  logic        [7:0] target_y,
    output logic              valid,
    output logic signed [8:0] rect_x,
    output logic signed [7:0] rect_y
);
    logic signed [8:0] current_x;
    logic signed [7:0] current_y;

    // Four stored samples plus the current sample form a five-frame window.
    logic signed [8:0] x_d1, x_d2, x_d3, x_d4;
    logic signed [7:0] y_d1, y_d2, y_d3, y_d4;

    logic        [2:0] sample_count;
    logic signed [11:0] sum_x;
    logic signed [11:0] sum_y;
    logic signed [8:0] averaged_x;
    logic signed [7:0] averaged_y;
    logic signed [8:0] rect_x_hold;
    logic signed [7:0] rect_y_hold;

    // X: right is positive. Y: above the screen center is positive.
    assign current_x = $signed({1'b0, target_x}) - 10'sd160;
    assign current_y = 9'sd120 - $signed({1'b0, target_y});
    assign valid     = target_valid_out;

    // Use only the number of valid samples collected during filter warm-up.
    always_comb begin
        sum_x = 12'sd0;
        sum_y = 12'sd0;

        case (sample_count)
            3'd0: begin
                sum_x      = $signed({{3{current_x[8]}}, current_x});
                sum_y      = $signed({{4{current_y[7]}}, current_y});
                averaged_x = sum_x;
                averaged_y = sum_y;
            end
            3'd1: begin
                sum_x      = $signed({{3{x_d1[8]}}, x_d1}) +
                             $signed({{3{current_x[8]}}, current_x});
                sum_y      = $signed({{4{y_d1[7]}}, y_d1}) +
                             $signed({{4{current_y[7]}}, current_y});
                averaged_x = sum_x / 12'sd2;
                averaged_y = sum_y / 12'sd2;
            end
            3'd2: begin
                sum_x      = $signed({{3{x_d2[8]}}, x_d2}) +
                             $signed({{3{x_d1[8]}}, x_d1}) +
                             $signed({{3{current_x[8]}}, current_x});
                sum_y      = $signed({{4{y_d2[7]}}, y_d2}) +
                             $signed({{4{y_d1[7]}}, y_d1}) +
                             $signed({{4{current_y[7]}}, current_y});
                averaged_x = sum_x / 12'sd3;
                averaged_y = sum_y / 12'sd3;
            end
            3'd3: begin
                sum_x      = $signed({{3{x_d3[8]}}, x_d3}) +
                             $signed({{3{x_d2[8]}}, x_d2}) +
                             $signed({{3{x_d1[8]}}, x_d1}) +
                             $signed({{3{current_x[8]}}, current_x});
                sum_y      = $signed({{4{y_d3[7]}}, y_d3}) +
                             $signed({{4{y_d2[7]}}, y_d2}) +
                             $signed({{4{y_d1[7]}}, y_d1}) +
                             $signed({{4{current_y[7]}}, current_y});
                averaged_x = sum_x / 12'sd4;
                averaged_y = sum_y / 12'sd4;
            end
            default: begin
                sum_x      = $signed({{3{x_d4[8]}}, x_d4}) +
                             $signed({{3{x_d3[8]}}, x_d3}) +
                             $signed({{3{x_d2[8]}}, x_d2}) +
                             $signed({{3{x_d1[8]}}, x_d1}) +
                             $signed({{3{current_x[8]}}, current_x});
                sum_y      = $signed({{4{y_d4[7]}}, y_d4}) +
                             $signed({{4{y_d3[7]}}, y_d3}) +
                             $signed({{4{y_d2[7]}}, y_d2}) +
                             $signed({{4{y_d1[7]}}, y_d1}) +
                             $signed({{4{current_y[7]}}, current_y});
                averaged_x = sum_x / 12'sd5;
                averaged_y = sum_y / 12'sd5;
            end
        endcase
    end

    // Present the new average during the done cycle, then hold it until the
    // next valid frame result arrives.
    assign rect_x = (frame_done && target_valid_out) ? averaged_x : rect_x_hold;
    assign rect_y = (frame_done && target_valid_out) ? averaged_y : rect_y_hold;

    // Update once per completed frame. Invalid targets do not enter the window.
    always_ff @(posedge pclk or posedge rst) begin
        if (rst) begin
            x_d1         <= '0;
            x_d2         <= '0;
            x_d3         <= '0;
            x_d4         <= '0;
            y_d1         <= '0;
            y_d2         <= '0;
            y_d3         <= '0;
            y_d4         <= '0;
            rect_x_hold  <= '0;
            rect_y_hold  <= '0;
            sample_count <= 3'd0;
        end else if (frame_done && target_valid_out) begin
            x_d4 <= x_d3;
            x_d3 <= x_d2;
            x_d2 <= x_d1;
            x_d1 <= current_x;
            y_d4 <= y_d3;
            y_d3 <= y_d2;
            y_d2 <= y_d1;
            y_d1 <= current_y;

            rect_x_hold <= averaged_x;
            rect_y_hold <= averaged_y;

            if (sample_count < 3'd4)
                sample_count <= sample_count + 1'b1;
        end
    end

endmodule
