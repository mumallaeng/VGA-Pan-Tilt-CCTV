`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Jong.W.Park
// Create Date: 2026/07/03 08:20:52
// Design Name: VGA
// Module Name: pixel_clk_gen
// Target Devices: Basys3 
//////////////////////////////////////////////////////////////////////////////////

module pixel_clk_gen (
    input  logic clk,
    input  logic rst,
    output logic pclk
);

    logic [1:0] clk_div;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) clk_div <= 2'b00;
        else clk_div <= clk_div + 1'b1;
    end

    assign pclk = clk_div[1];

endmodule
