import uvm_pkg::*;
import green_color_filter_pkg::*;

module tb_top;
    // Clock & Reset
    logic clk;
    logic rst;

    parameter CLK_PERIOD = 10;  // ns

    // Interface
    green_color_filter_interface green_color_filter_if (
        .clk(clk),
        .rst(rst)
    );

    // Instantiate the DUT
    green_color_filter DUT (
        .pixel_rgb565(green_color_filter_if.pixel_rgb565),
        .pixel_valid (green_color_filter_if.pixel_valid),
        .vga_r       (green_color_filter_if.vga_r),
        .vga_g       (green_color_filter_if.vga_g),
        .vga_b       (green_color_filter_if.vga_b),
        .green_mask  (green_color_filter_if.green_mask),
        .green_valid (green_color_filter_if.green_valid),
        .original_r  (green_color_filter_if.original_r),
        .original_g  (green_color_filter_if.original_g),
        .original_b  (green_color_filter_if.original_b),
        .green_r     (green_color_filter_if.green_r),
        .green_g     (green_color_filter_if.green_g),
        .green_b     (green_color_filter_if.green_b)
    );

    // Make VERDI dump file
    initial begin
        $fsdbDumpfile("green_color_filter_wave.fsdb");
        $fsdbDumpvars(0);
        $fsdbDumpMDA();
    end

    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    initial begin
        rst = 1;
        #(CLK_PERIOD * 5);
        rst = 0;
    end

    // Set UVM configuration and run the test
    initial begin
        uvm_config_db#(virtual green_color_filter_interface)::set(null, "*", "green_color_filter_if",
                                                    green_color_filter_if);
        run_test("green_color_filter_test");
    end
endmodule
