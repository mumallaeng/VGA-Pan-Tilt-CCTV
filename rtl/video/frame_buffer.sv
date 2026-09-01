`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Jong.W.Park 
// Create Date: 2026/07/10 20:04:25
// Module Name: frame_buffer
//////////////////////////////////////////////////////////////////////////////////


module frame_buffer #(
    parameter IMG_WIDTH  = 320,
    parameter IMG_HEIGHT = 240,
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 17
) (
    //write side : OV7670 CAM CLK Domain
    input logic                  wr_clk,
    input logic                  wr_en,
    input logic [ADDR_WIDTH-1:0] wr_addr,
    input logic [DATA_WIDTH-1:0] wr_data,

    //read side : VGA pixel CLK Domain
    input logic                    rd_clk,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data
);

    localparam FRAME_SIZE = IMG_WIDTH * IMG_HEIGHT;

    logic [DATA_WIDTH-1:0] mem[0:FRAME_SIZE-1];

    //write side : OV7670 CAM CLK Domain    
    always_ff @(posedge wr_clk) begin
        if (wr_en) begin
            if (wr_addr < FRAME_SIZE) begin
                mem[wr_addr] <= wr_data;
            end
        end
    end

    //read side : VGA pixel CLK Domain    
    always_ff @( posedge rd_clk ) begin
        if (rd_addr < FRAME_SIZE) begin
            rd_data <= mem[rd_addr];
        end else begin
            rd_data <= {DATA_WIDTH{1'b0}};
        end
    end


endmodule
