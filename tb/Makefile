# Generic cocotb + Verilator Makefile.
#
# Usage from repo root (with the venv active):
#   source .venv/bin/activate
#   make -C tb MODULE=test_counter TOPLEVEL=counter
#
# MODULE   = the Python test file in this dir (without .py)
# TOPLEVEL = the top SystemVerilog module name to simulate
# SRCS     = SystemVerilog sources (defaults to all of ../rtl)

SIM ?= verilator
TOPLEVEL_LANG ?= verilog

TOPLEVEL ?= counter
MODULE   ?= test_counter

SRCS ?= $(wildcard $(PWD)/../rtl/*.sv)
VERILOG_SOURCES += $(SRCS)

# emit a VCD waveform into sim_build/dump.vcd for GTKWave
EXTRA_ARGS += --trace --trace-structs

include $(shell cocotb-config --makefiles)/Makefile.sim
