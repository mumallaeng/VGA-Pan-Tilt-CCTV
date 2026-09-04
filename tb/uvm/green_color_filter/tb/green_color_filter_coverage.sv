class green_color_filter_coverage extends uvm_component;

    `uvm_component_utils(green_color_filter_coverage)

    uvm_analysis_imp #(green_color_filter_seq_item, green_color_filter_coverage) recv;

    green_color_filter_seq_item seq_item;

    covergroup green_color_filter_cvg with function sample(green_color_filter_seq_item tr);
        option.per_instance = 1;

        // Define Coverage point
        cp_valid : coverpoint tr.pixel_valid;
        cp_mask : coverpoint tr.green_mask {
            bins masked   = {1};
            bins unmasked = {0};
        }
        cp_g6 : coverpoint tr.pixel_rgb565[10:5] {
            bins low  = {[0 : 31]};
            bins mid  = {[32 : 47]};
            bins high = {[48 : 63]};
        }
        cross_valid_mask : cross cp_valid, cp_mask;
    endgroup

    function new(string name = "green_color_filter_coverage", uvm_component parent = null);
        super.new(name, parent);
        recv = new("recv", this);
        green_color_filter_cvg = new();
    endfunction

    function void write(green_color_filter_seq_item t);
        green_color_filter_cvg.sample(t);
        `uvm_info(get_type_name(), $sformatf("Coverage: %s", t.convert2string()), UVM_MEDIUM)
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("COV", "Functional coverage result", UVM_LOW)
        `uvm_info("COV", $sformatf("================================"), UVM_LOW)
        `uvm_info("COV", $sformatf("TOTAL                = %6.2f%%", green_color_filter_cvg.get_inst_coverage()), UVM_LOW)
        `uvm_info("COV", $sformatf("valid x mask         = %6.2f%%", green_color_filter_cvg.cross_valid_mask.get_inst_coverage()), UVM_LOW)
        `uvm_info("COV", $sformatf("green channel buckets= %6.2f%%", green_color_filter_cvg.cp_g6.get_inst_coverage()), UVM_LOW)
        `uvm_info("COV", $sformatf("================================"), UVM_LOW)
    endfunction
endclass
