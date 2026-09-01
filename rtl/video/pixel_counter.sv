`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Jong.W.Park
// Create Date: 2026/07/03 08:25:47
// Design Name: VGA
// Module Name: pixel_counter
//////////////////////////////////////////////////////////////////////////////////

module pixel_counter (
    input  logic       pclk,
    input  logic       rst,
    output logic [9:0] h_cnt,  //horizontal counter
    output logic [9:0] v_cnt   //vertical counter
);
    //  |visible    |front porch    |sync pulse |back porch |
    //  |640        |16             |960        |48         |
    //  |-----------|---------------|-----------|-----------|
    //  |480        |10             |2          |33         |
    //  |-----------|---------------|-----------|-----------|
    localparam H_MAX = 800;
    localparam V_MAX = 525;

    always_ff @(posedge pclk or posedge rst) begin : horizontal_counter
        if (rst) begin
            h_cnt <= '0;
        end else begin
            if (h_cnt == H_MAX - 1) begin
                h_cnt <= '0;
            end else begin
                h_cnt <= h_cnt + 1'b1;
            end
        end
    end

    always_ff @(posedge pclk or posedge rst) begin : vertical_counter
        if (rst) begin
            v_cnt <= '0;
        end else begin
            if (h_cnt == H_MAX - 1) begin
                if (v_cnt == V_MAX - 1) begin
                    v_cnt <= '0;
                end else begin
                    v_cnt <= v_cnt + 1'b1;
                end
            end
        end
    end
endmodule
