VCS_OPTS = -full64 -sverilog
VCS_OPTS += -ntb_opts uvm-1.2 -kdb -lca
VCS_OPTS += -timescale=1ns/1ps
VCS_OPTS += -debug_access+all
VCS_OUTPUTS = -o simv
VCS_INCDIR = +incdir+tb +incdir+../../../rtl/common/filter
VCS_SRC_FILES = ../../../rtl/common/filter/green_color_filter.sv ./tb/green_color_filter_interface.sv ./tb/green_color_filter_pkg.sv ./tb/tb_top.sv

TEST ?= green_color_filter_test
SEED ?= 1
INFO_LEVEL ?= UVM_MEDIUM

LOG_FILE = sim.log

SIMV_OPTS = +UVM_TESTNAME=$(TEST)
SIMV_OPTS += +UVM_VERBOSITY=$(INFO_LEVEL)
SIMV_OPTS += +ntb_random_seed=$(SEED)
SIMV_OPTS += -cm line+cond+fsm+tgl+branch+assert
SIMV_OPTS += -cm_dir coverage.vdb
SIMV_OPTS += -cm_name sim1
SIMV_OPTS += -l $(LOG_FILE)

WAVE_SRC = green_color_filter_wave.fsdb


.PHONY: comp simv clean waveform cover

comp:
	@vcs $(VCS_OPTS) $(VCS_INCDIR) $(VCS_OUTPUTS) $(VCS_SRC_FILES)
	@echo ""
	@echo "===================== Compile Complete ====================="
	@echo ""

simv: comp
	@./simv $(SIMV_OPTS)
	@echo "Dependency Target: [$<]"
	@echo "Target: [$@]"
	@echo ""
	@echo "===================== Simulation Complete ====================="
	@echo ""

clean:
	@rm -rf simv* csrc *.log *.key *.h *.fsdb
	@echo "Erasing Result Files ..."

waveform:
	@verdi -dbdir ./simv.daidir -ssf $(WAVE_SRC)

cover:
	@verdi -dbdir ./simv.daidir -ssf $(WAVE_SRC) -cov -covdir coverage.vdb/
