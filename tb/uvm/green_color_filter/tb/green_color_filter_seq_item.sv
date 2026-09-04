class green_color_filter_seq_item extends uvm_sequence_item;

    // Define transaction fields
    rand logic [15:0] pixel_rgb565;
    rand logic        pixel_valid;
    rand logic [ 3:0] vga_r;
    rand logic [ 3:0] vga_g;
    rand logic [ 3:0] vga_b;
    logic             green_mask;
    logic             green_valid;
    logic      [ 3:0] original_r;
    logic      [ 3:0] original_g;
    logic      [ 3:0] original_b;
    logic      [ 3:0] green_r;
    logic      [ 3:0] green_g;
    logic      [ 3:0] green_b;

    // Bias the green channel (rgb565[10:5]) toward the G_MIN threshold so
    // the mask decision boundary actually gets exercised by random tests.
    constraint c_green_bias {
        pixel_rgb565[10:5] dist {
            [0  : 30] :/ 2,
            [31 : 40] :/ 3,
            [41 : 63] :/ 5
        };
    }

    function new(string name = "green_color_filter_seq_item");
        super.new(name);
    endfunction

    `uvm_object_utils_begin(green_color_filter_seq_item)
        `uvm_field_int(pixel_rgb565, UVM_ALL_ON)
        `uvm_field_int(pixel_valid, UVM_ALL_ON)
        `uvm_field_int(vga_r, UVM_ALL_ON)
        `uvm_field_int(vga_g, UVM_ALL_ON)
        `uvm_field_int(vga_b, UVM_ALL_ON)
        `uvm_field_int(green_mask, UVM_ALL_ON)
        `uvm_field_int(green_valid, UVM_ALL_ON)
        `uvm_field_int(original_r, UVM_ALL_ON)
        `uvm_field_int(original_g, UVM_ALL_ON)
        `uvm_field_int(original_b, UVM_ALL_ON)
        `uvm_field_int(green_r, UVM_ALL_ON)
        `uvm_field_int(green_g, UVM_ALL_ON)
        `uvm_field_int(green_b, UVM_ALL_ON)
    `uvm_object_utils_end

    function string convert2string();
        return $sformatf(
            "rgb565=%04h valid=%0d vga=(%0d,%0d,%0d) mask=%0d gvalid=%0d orig=(%0d,%0d,%0d) green=(%0d,%0d,%0d)",
            pixel_rgb565,
            pixel_valid,
            vga_r,
            vga_g,
            vga_b,
            green_mask,
            green_valid,
            original_r,
            original_g,
            original_b,
            green_r,
            green_g,
            green_b
        );
    endfunction

endclass
