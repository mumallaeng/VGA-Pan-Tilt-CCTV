class green_color_filter_agent extends uvm_agent;

    `uvm_component_utils(green_color_filter_agent)

    uvm_sequencer #(green_color_filter_seq_item) sqr;
    green_color_filter_driver                    drv;
    green_color_filter_monitor                   mon;

    function new(string name = "green_color_filter_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        sqr = uvm_sequencer #(green_color_filter_seq_item)::type_id::create("SQR", this);
        drv = green_color_filter_driver::type_id::create("DRV", this);
        mon = green_color_filter_monitor::type_id::create("MON", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass
