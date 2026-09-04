class green_color_filter_monitor extends uvm_monitor;

    `uvm_component_utils(green_color_filter_monitor)

    virtual green_color_filter_interface green_color_filter_if;

    green_color_filter_seq_item seq_item;

    uvm_analysis_port #(green_color_filter_seq_item) send;

    function new(string name = "green_color_filter_monitor", uvm_component parent = null);
        super.new(name, parent);
        send = new("send", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
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
        @(posedge green_color_filter_if.clk);
        forever begin
            seq_item = green_color_filter_seq_item::type_id::create("seq_item");

            // DUT is purely combinational, so inputs and outputs are
            // captured together as one consistent snapshot.
            seq_item.pixel_rgb565 <= green_color_filter_if.pixel_rgb565;
            seq_item.pixel_valid  <= green_color_filter_if.pixel_valid;
            seq_item.vga_r        <= green_color_filter_if.vga_r;
            seq_item.vga_g        <= green_color_filter_if.vga_g;
            seq_item.vga_b        <= green_color_filter_if.vga_b;
            seq_item.green_mask   <= green_color_filter_if.green_mask;
            seq_item.green_valid  <= green_color_filter_if.green_valid;
            seq_item.original_r   <= green_color_filter_if.original_r;
            seq_item.original_g   <= green_color_filter_if.original_g;
            seq_item.original_b   <= green_color_filter_if.original_b;
            seq_item.green_r      <= green_color_filter_if.green_r;
            seq_item.green_g      <= green_color_filter_if.green_g;
            seq_item.green_b      <= green_color_filter_if.green_b;
            @(posedge green_color_filter_if.clk);

            // send the sequence item through the analysis port
            send.write(seq_item);
        end
    endtask

endclass
