`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: ov7670_xclk_gen
// Description: Generates the OV7670 25 MHz master clock from the Basys3 100 MHz
//              system clock.
//////////////////////////////////////////////////////////////////////////////////

module ov7670_xclk_gen (
    input  logic clk_100MHz,
    input  logic rst,
    output logic ov_xclk
);

    logic [1:0] clk_divider;

    always_ff @(posedge clk_100MHz or posedge rst) begin : xclk_divider
        if (rst) begin
            clk_divider <= 2'b00;
        end else begin
            clk_divider <= clk_divider + 1'b1;
        end
    end

    // A continuously toggling divide-by-four clock: 100 MHz / 4 = 25 MHz.
    assign ov_xclk = clk_divider[1];

endmodule
