class green_color_filter_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(green_color_filter_scoreboard)

    uvm_analysis_imp #(green_color_filter_seq_item, green_color_filter_scoreboard) recv;

    // Pass Fail count
    int pass_count = 0;
    int fail_count = 0;

    // Must track rtl/common/filter/green_color_filter.sv parameters
    localparam logic [7:0] G_MIN = 8'b1000_0000;
    localparam logic [7:0] GR_DIFF = 8'd40;
    localparam logic [7:0] GB_DIFF = 8'd40;

    function new(string name = "green_color_filter_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        recv = new("recv", this);
    endfunction

    function void write(green_color_filter_seq_item item);
        bit ok = 1;
        logic [4:0] r5, b5;
        logic [5:0] g6;
        logic [7:0] r8, g8, b8;
        logic [8:0] g_ext, r_thresh, b_thresh;
        logic exp_mask, exp_valid, exp_mask_en;
        logic [3:0] exp_green;

        // Reference model - mirrors green_color_filter.sv bit-for-bit
        r5 = item.pixel_rgb565[15:11];
        g6 = item.pixel_rgb565[10:5];
        b5 = item.pixel_rgb565[4:0];
        r8 = {r5, r5[4:2]};
        g8 = {g6, g6[5:4]};
        b8 = {b5, b5[4:2]};

        g_ext    = {1'b0, g8};
        r_thresh = {1'b0, r8} + {1'b0, GR_DIFF};
        b_thresh = {1'b0, b8} + {1'b0, GB_DIFF};

        exp_mask = item.pixel_valid &&
            (g8 >= G_MIN) &&
            (g_ext >= r_thresh) &&
            (g_ext >= b_thresh);
        exp_valid   = item.pixel_valid;
        exp_mask_en = exp_valid && exp_mask;
        exp_green   = {4{exp_mask_en}};

        ok &= (item.green_mask === exp_mask);
        ok &= (item.green_valid === exp_valid);
        ok &= (item.original_r === item.vga_r);
        ok &= (item.original_g === item.vga_g);
        ok &= (item.original_b === item.vga_b);
        ok &= (item.green_r === exp_green);
        ok &= (item.green_g === exp_green);
        ok &= (item.green_b === exp_green);

        if (ok) pass_count++;
        else begin
            fail_count++;
            `uvm_error("SCB", $sformatf(
                       "MISMATCH exp(mask=%0d valid=%0d green=%0d) act(%s)",
                       exp_mask,
                       exp_valid,
                       exp_green,
                       item.convert2string()
                       ))
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("SCB", "==============================================",
                  UVM_LOW)
        `uvm_info("SCB", "============== Scoreboard Report =============",
                  UVM_LOW)
        `uvm_info("SCB", $sformatf(
                  "\tTotal     count : %0d", pass_count + fail_count), UVM_LOW)
        `uvm_info("SCB", $sformatf("\tPass      count : %0d", pass_count),
                  UVM_LOW)
        `uvm_info("SCB", $sformatf("\tFail      count : %0d", fail_count),
                  UVM_LOW)
        `uvm_info("SCB", "==============================================",
                  UVM_LOW)
    endfunction

endclass
