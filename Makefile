VCS       ?= vcs
SIMV      ?= simv
TEST      ?= test
SEED      ?= 1
VCS_FLAGS ?= -full64 -sverilog -ntb_opts uvm-1.2 -debug_access+all
CM_FLAGS  ?= -cm line+cond+tgl+fsm+branch

.PHONY: all compile run clean

all: compile run

compile:
	$(VCS) $(VCS_FLAGS) $(CM_FLAGS) -f filelist.f -o $(SIMV) -l compile.log

run:
	./$(SIMV) +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) \
		$(CM_FLAGS) -cm_name $(TEST)_$(SEED) -l sim.log

clean:
	rm -rf csrc simv simv.daidir simv.vdb ucli.key vc_hdrs.h \
		compile.log sim.log waveform.fsdb dma_read.txt dma_write.txt
