`timescale 1ns / 1ps

module xadc_xy_reader (
    input  logic        clk,
    input  logic        rst,
    input  logic [ 4:0] channel_addr,
    input  logic [11:0] xadc_data,
    input  logic        xadc_drdy,
    input  logic        xadc_eoc,
    output logic [11:0] o_xadc_x,
    output logic [11:0] o_xadc_y,
    output logic        o_xadc_data_valid
);

    logic [ 4:0] xadc_read_channel;
    logic x_received;
    
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            xadc_read_channel <= 5'd0;
            o_xadc_x          <= 12'd0;
            o_xadc_y          <= 12'd0;
            o_xadc_data_valid <= 1'b0;
            x_received        <= 1'b0;
        end else begin
            o_xadc_data_valid <= 1'b0;
            if (xadc_eoc) begin
                xadc_read_channel <= channel_addr;
            end
            if (xadc_drdy) begin
                case (xadc_read_channel)
					5'h16: begin
                        o_xadc_x   <= xadc_data;
                        x_received <= 1'b1;
                    end
					5'h1E: begin
                        o_xadc_y <= xadc_data;
                        if (x_received == 1) begin
                            o_xadc_data_valid <= 1'b1;
                            x_received <= 1'b0;
                        end
                    end
				endcase
            end
        end 
    end

endmodule
