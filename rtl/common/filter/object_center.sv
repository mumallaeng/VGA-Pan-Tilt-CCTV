module object_center (
    input  logic       target_valid_in,
    input  logic [8:0] min_x,
    input  logic [8:0] max_x,
    input  logic [7:0] min_y,
    input  logic [7:0] max_y,

    output logic       target_valid_out,
    output logic [8:0] target_x,
    output logic [7:0] target_y
);

    logic [9:0] sum_x;
    logic [8:0] sum_y;

    assign sum_x = {1'b0, min_x} + {1'b0, max_x};
    assign sum_y = {1'b0, min_y} + {1'b0, max_y};

    assign target_valid_out = target_valid_in;
    assign target_x = sum_x[9:1];
    assign target_y = sum_y[8:1];

endmodule
