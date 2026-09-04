class green_color_filter_driver extends uvm_driver #(green_color_filter_seq_item);

    `uvm_component_utils(green_color_filter_driver)

    virtual green_color_filter_interface green_color_filter_if;

    green_color_filter_seq_item seq_item;

    function new(string name = "green_color_filter_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual green_color_filter_interface)::get(
                this, "", "green_color_filter_if", green_color_filter_if
            )) begin
            `uvm_fatal(get_type_name(),
                       "Virtual interface must be set for green_color_filter_if");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        // Wait for reset - Default is active low
        wait (green_color_filter_if.rst == 1);
        wait (green_color_filter_if.rst == 0);
        @(posedge green_color_filter_if.clk);

        forever begin
            seq_item_port.get_next_item(seq_item);

            green_color_filter_if.pixel_rgb565 <= seq_item.pixel_rgb565;
            green_color_filter_if.pixel_valid  <= seq_item.pixel_valid;
            green_color_filter_if.vga_r        <= seq_item.vga_r;
            green_color_filter_if.vga_g        <= seq_item.vga_g;
            green_color_filter_if.vga_b        <= seq_item.vga_b;

            // Wait for 1 CLK
            @(posedge green_color_filter_if.clk);

            // Send the sequence item back to the sequencer
            seq_item_port.item_done();
        end
    endtask

endclass
