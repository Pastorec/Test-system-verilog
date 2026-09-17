# Convenience wrapper around run_iverilog.sh
.PHONY: all fixed orig orig-core dump clean

all: fixed

fixed:
	@./run_iverilog.sh

orig:
	@./run_iverilog.sh --orig

orig-core:
	@./run_iverilog.sh --orig-core

dump:
	@./run_iverilog.sh --dump

clean:
	@rm -rf build
