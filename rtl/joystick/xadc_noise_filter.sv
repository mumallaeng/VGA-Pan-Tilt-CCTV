`timescale 1ns / 1ps

module xadc_noise_filter (
    input  logic        clk,
    input  logic        rst,
    input  logic        i_xadc_data_valid,
    input  logic [11:0] i_xadc_x,
    input  logic [11:0] i_xadc_y,
    output logic [11:0] o_filtered_x,
    output logic [11:0] o_filtered_y,
    output logic        o_filtered_data_valid
);

    logic [11:0] x_sample[0:3];
    logic [11:0] y_sample[0:3];
    logic        initialized; // sample 저장소가 최초 입력값으로 초기화 됐는가

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            x_sample[0]           <= 12'd0;
            x_sample[1]           <= 12'd0;
            x_sample[2]           <= 12'd0;
            x_sample[3]           <= 12'd0;
            y_sample[0]           <= 12'd0;
            y_sample[1]           <= 12'd0;
            y_sample[2]           <= 12'd0;
            y_sample[3]           <= 12'd0;
            o_filtered_x          <= 12'd0;
            o_filtered_y          <= 12'd0;
            o_filtered_data_valid <= 1'b0;
            initialized           <= 1'b0;
        end else begin
            o_filtered_data_valid <= 1'b0;
            if (i_xadc_data_valid) begin
                if (!initialized) begin
                    x_sample[0]  <= i_xadc_x;
                    x_sample[1]  <= i_xadc_x;
                    x_sample[2]  <= i_xadc_x;
                    x_sample[3]  <= i_xadc_x;

                    y_sample[0]  <= i_xadc_y;
                    y_sample[1]  <= i_xadc_y;
                    y_sample[2]  <= i_xadc_y;
                    y_sample[3]  <= i_xadc_y;

                    o_filtered_x <= i_xadc_x;
                    o_filtered_y <= i_xadc_y;
                    initialized  <= 1'b1;
                end else begin
                    x_sample[3] <= x_sample[2];
                    x_sample[2] <= x_sample[1];
                    x_sample[1] <= x_sample[0];
                    x_sample[0] <= i_xadc_x;

                    y_sample[3] <= y_sample[2];
                    y_sample[2] <= y_sample[1];
                    y_sample[1] <= y_sample[0];
                    y_sample[0] <= i_xadc_y;
                    o_filtered_x <= ({2'b00, i_xadc_x} + {2'b00, x_sample[0]} +
                        {2'b00, x_sample[1]} + {2'b00, x_sample[2]}) >> 2;

                    o_filtered_y <= ({2'b00, i_xadc_y} + {2'b00, y_sample[0]} +
                        {2'b00, y_sample[1]} + {2'b00, y_sample[2]}) >> 2;
                end
                o_filtered_data_valid <= 1'b1;
            end
        end
    end

endmodule
