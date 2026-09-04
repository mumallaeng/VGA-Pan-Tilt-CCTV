`timescale 1ns / 1ps

module button_debounce (
    input  logic clk,
    input  logic rst,
    input  logic i_btn,
    output logic o_btn
);

    // clock divider
    // 100MHz -> 1KHz
    parameter F_COUNT = 100_000_000 / 1_000;
    reg [$clog2(F_COUNT)-1:0] r_counter;
    reg clk_100khz;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            r_counter <= 0;
            clk_100khz <= 1'b0;
        end else begin
            if (r_counter == F_COUNT - 1) begin
                r_counter  <= 0;
                clk_100khz <= 1'b1;
            end else begin
                r_counter <= r_counter + 1;
                clk_100khz <= 1'b0;
            end
        end
    end

    // syncronizer
    reg [7:0] sync_reg, sync_next;
    reg  edge_reg;
    reg  debounce;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sync_reg <= 0;
        end else begin
            if (clk_100khz) begin
            sync_reg <= sync_next;
            end
        end
    end

    always_comb begin
        sync_next = {i_btn, sync_reg[7:1]};
        //sync_next = {sync_reg[6:0], i_btn};
    end

    // debounced level with hysteresis:
    // set when all 8 samples are 1, clear when all 8 are 0, hold otherwise.
    // prevents contact chatter during a hold from producing extra o_btn pulses.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            debounce <= 1'b0;
        end else if (clk_100khz) begin
            if (&sync_reg) debounce <= 1'b1;
            else if (~|sync_reg) debounce <= 1'b0;
        end
    end

    // rising edge detect
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            edge_reg <= 1'b0;
        end else begin
            edge_reg <= debounce;
        end
    end

    assign o_btn = debounce & (~edge_reg);

endmodule