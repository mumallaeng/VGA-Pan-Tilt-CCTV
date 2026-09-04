class green_color_filter_base_test extends uvm_test;

    `uvm_component_utils(green_color_filter_base_test)

    green_color_filter_env      env;
    green_color_filter_sequence seq;

    function new(string name = "green_color_filter_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = green_color_filter_env::type_id::create("ENV", this);
        seq = green_color_filter_sequence::type_id::create("SEQ");
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

endclass

class green_color_filter_test extends green_color_filter_base_test;

    `uvm_component_utils(green_color_filter_test)

    function new(string name = "green_color_filter_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        // TODO: Can change the number of transactions to generate in the sequence
        seq.count = 200;
        seq.start(env.agt.sqr);
        #10;

        phase.drop_objection(this);
    endtask

endclass
