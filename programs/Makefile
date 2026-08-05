# Build the demo programs for the rv32-core CPU.
# Recipes are plain tool invocations with no shell builtins, so they behave the
# same whether make picks cmd.exe or a POSIX sh.
#
#   make -C programs <name>   hardware flavor of one demo, into build/
#   make -C programs sim      simulation flavor of every demo, into hex/
#   make -C programs hw       hardware flavor of every demo, into build/
#
# hex/ is committed so the simulation testbenches never need the cross
# toolchain; build/ is gitignored and regenerated for the Quartus flow.

RISCV_PREFIX ?= C:/Users/CJ/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
PYTHON       ?= python

CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump

COMMON := common
BUILD  := build
HEX    := hex

HEXGEN := ../tools/hex_gen.py

# python does the directory work so the recipes parse the same under cmd.exe
# and under a POSIX sh, whichever one make happens to pick up
MKDIR = $(PYTHON) -c "import os,sys; os.makedirs(sys.argv[1], exist_ok=True)"
RMDIR = $(PYTHON) -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)"

# imem and dmem regions, matching the memory map in claude-docs/architecture.md
IMEM_BASE := 0x00000000
DMEM_BASE := 0x00001000
MEM_SIZE  := 4096

DEMOS := led_blink counter switch_mirror fibonacci memtest reaction

CFLAGS  := -march=rv32i -mabi=ilp32 -nostdlib -ffreestanding -O2 \
           -Wall -Wextra -I$(COMMON)
LDFLAGS := -Wl,--no-relax -T $(COMMON)/link.ld
LDLIBS  := -lgcc

CRT0 := $(COMMON)/crt0.s
DEPS := $(CRT0) $(COMMON)/link.ld $(COMMON)/mmio.h $(COMMON)/config.h $(HEXGEN)

SIM_HEX := $(addprefix $(HEX)/,$(addsuffix .hex,$(DEMOS)))
HW_HEX  := $(addprefix $(BUILD)/,$(addsuffix .hex,$(DEMOS)))

.DEFAULT_GOAL := all
.PHONY: all sim hw clean $(DEMOS)
.SECONDARY:

all: sim

sim: $(SIM_HEX)
	@echo Simulation hex files up to date in $(HEX).

hw: $(HW_HEX)
	@echo Hardware hex files up to date in $(BUILD).

# named target per demo builds the hardware flavor
$(DEMOS): %: $(BUILD)/%.hex

$(BUILD)/%_hw.elf: %.c $(DEPS)
	@$(MKDIR) $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(CRT0) $< $(LDLIBS)

$(BUILD)/%_sim.elf: %.c $(DEPS)
	@$(MKDIR) $(BUILD)
	$(CC) $(CFLAGS) -DSIMULATION $(LDFLAGS) -o $@ $(CRT0) $< $(LDLIBS)

# each build emits two images: <name>.hex for imem and <name>_data.hex for
# dmem, whose word index 0 is byte address 0x1000
$(BUILD)/%.hex: $(BUILD)/%_hw.elf
	$(PYTHON) $(HEXGEN) --base $(IMEM_BASE) --size $(MEM_SIZE) $< $@
	$(PYTHON) $(HEXGEN) --base $(DMEM_BASE) --size $(MEM_SIZE) $< $(BUILD)/$*_data.hex

$(HEX)/%.hex: $(BUILD)/%_sim.elf
	@$(MKDIR) $(HEX)
	$(PYTHON) $(HEXGEN) --base $(IMEM_BASE) --size $(MEM_SIZE) $< $@
	$(PYTHON) $(HEXGEN) --base $(DMEM_BASE) --size $(MEM_SIZE) $< $(HEX)/$*_data.hex

# disassembly and section table for a built elf, for example: make dump-counter
dump-%: $(BUILD)/%_sim.elf
	$(OBJDUMP) -d -h -t $<

clean:
	@$(RMDIR) $(BUILD)
	@echo Cleaned $(BUILD).
