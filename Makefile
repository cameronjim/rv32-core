# Icarus Verilog simulation driver for the rv32-core testbenches.
# Recipes run under cmd.exe on Windows, so keep them to plain tool invocations.

IVERILOG ?= C:/iverilog/bin/iverilog.exe
VVP      ?= C:/iverilog/bin/vvp.exe

BUILD_DIR := sim/build
BUILD_WIN := $(subst /,\,$(BUILD_DIR))

# rv32_pkg must be compiled before the modules that import it
PKG      := rtl/rv32_pkg.sv
RTL_SRCS := $(PKG) $(filter-out $(PKG),$(wildcard rtl/*.sv))

# every tb/<name>_tb.sv becomes a <name>_tb target
TB_SRCS    := $(wildcard tb/*_tb.sv)
TB_TARGETS := $(basename $(notdir $(TB_SRCS)))

.DEFAULT_GOAL := test
.PHONY: test clean

ifeq ($(TB_TARGETS),)
test:
	@echo No testbenches found in tb.
else
test: $(TB_TARGETS)
	@echo All testbenches passed.
endif

# build and run one testbench, for example: make alu_tb
%_tb: tb/%_tb.sv $(RTL_SRCS)
	@if not exist "$(BUILD_WIN)" mkdir "$(BUILD_WIN)"
	$(IVERILOG) -g2012 -o $(BUILD_DIR)/$@.vvp $(RTL_SRCS) $<
	$(VVP) $(BUILD_DIR)/$@.vvp

clean:
	@if exist "$(BUILD_WIN)" rmdir /s /q "$(BUILD_WIN)"
	@echo Cleaned $(BUILD_DIR).
