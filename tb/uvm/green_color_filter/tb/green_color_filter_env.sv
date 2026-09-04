class green_color_filter_env extends uvm_env;

    `uvm_component_utils(green_color_filter_env)

    green_color_filter_agent      agt;
    green_color_filter_scoreboard scb;
    green_color_filter_coverage   cov;

    function new(string name = "green_color_filter_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = green_color_filter_agent::type_id::create("AGT", this);
        scb = green_color_filter_scoreboard::type_id::create("SCB", this);
        cov = green_color_filter_coverage::type_id::create("COV", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.send.connect(scb.recv);
        agt.mon.send.connect(cov.recv);
    endfunction

endclass
