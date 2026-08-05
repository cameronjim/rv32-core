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

# Test program hex files. These are committed, so `make test` never needs the
# cross toolchain; run `make tb-programs` only after editing a .s source.
# Override RISCV_PREFIX if the xPack toolchain lives somewhere else.
RISCV_PREFIX ?= C:/Users/CJ/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
PYTHON       ?= python

PROG_DIR  := tb/programs
PROGRAMS  := arith mem branch
PROG_HEX  := $(addprefix $(PROG_DIR)/,$(addsuffix .hex,$(PROGRAMS)))

.PHONY: tb-programs
tb-programs: $(PROG_HEX)
	@echo Regenerated $(PROG_HEX).

# --no-relax keeps the linked instruction stream matching the .s source, so the
# expected values documented per line stay trustworthy
$(PROG_DIR)/%.hex: $(PROG_DIR)/%.s tools/hex_gen.py
	@if not exist "$(BUILD_WIN)" mkdir "$(BUILD_WIN)"
	$(RISCV_PREFIX)gcc -march=rv32i -mabi=ilp32 -nostdlib -Wl,--no-relax -Ttext=0x0 -o $(BUILD_DIR)/$*.elf $<
	$(RISCV_PREFIX)objcopy -O binary $(BUILD_DIR)/$*.elf $(BUILD_DIR)/$*.bin
	$(PYTHON) tools/hex_gen.py $(BUILD_DIR)/$*.bin $@
