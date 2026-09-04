class green_color_filter_base_sequence extends uvm_sequence #(green_color_filter_seq_item);

    `uvm_object_utils(green_color_filter_base_sequence)

    green_color_filter_seq_item seq_item;

    function new(string name = "green_color_filter_base_sequence");
        super.new(name);
    endfunction

    task valid_random(int count);
        repeat (count) begin
            // Create a new sequence item
            seq_item = green_color_filter_seq_item::type_id::create("seq_item");

            start_item(seq_item);

            // Random pixel/vga values, forced valid
            assert (seq_item.randomize()) else `uvm_fatal("Randomization failed", "Failed to randomize sequence item");
            seq_item.pixel_valid = 1;

            finish_item(seq_item);
        end
    endtask

    task invalid_pixel_test(int count);
        repeat (count) begin
            // Create a new sequence item
            seq_item = green_color_filter_seq_item::type_id::create("seq_item");

            start_item(seq_item);

            // Random values, forced invalid -> mask/green outputs must clear
            assert (seq_item.randomize()) else `uvm_fatal("Randomization failed", "Failed to randomize sequence item");
            seq_item.pixel_valid = 0;

            finish_item(seq_item);
        end
    endtask

    task boundary_region_test(int count);
        repeat (count) begin
            // Create a new sequence item
            seq_item = green_color_filter_seq_item::type_id::create("seq_item");

            start_item(seq_item);

            // Push g6 to the extremes so both sides of the G_MIN / GR_DIFF /
            // GB_DIFF decision get hit, not just the biased middle.
            assert (seq_item.randomize() with {
                pixel_valid == 1;
                pixel_rgb565[10:5] inside {[0 : 2], [61 : 63]};
            }) else `uvm_fatal("Randomization failed", "Failed to randomize sequence item");

            finish_item(seq_item);
        end
    endtask

endclass

class green_color_filter_sequence extends green_color_filter_base_sequence;

    `uvm_object_utils(green_color_filter_sequence)

    int count;

    function new(string name = "green_color_filter_sequence");
        super.new(name);
    endfunction

    task body();
        `uvm_info(get_type_name(), $sformatf("Start (repeat %0d times)", count), UVM_LOW)

        // Invalid-pixel and boundary-region checks first
        invalid_pixel_test(10);
        boundary_region_test(20);

        repeat (count) begin
            valid_random(1);
        end

        `uvm_info(get_type_name(), $sformatf("Done (%0d times)", count), UVM_LOW)
    endtask

endclass
