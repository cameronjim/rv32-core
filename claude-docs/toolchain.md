# Toolchain setup

Decisions and setup steps for the development environment, recorded 2026-08-04.
The machine is a Windows 10 Pro desktop (16 GB RAM). Everything below runs natively
on Windows. WSL2 is installed but currently fails to start (error 0x800705aa), so
nothing in this project depends on it.

## Strategy

Simulation-first. The design is written and verified entirely in Icarus Verilog
before Quartus enters the picture. Quartus is only needed for synthesis, pin
assignment, and programming the board, which starts in the hardware bring-up phase.
This keeps the edit-compile-test loop fast (seconds, not minutes) and means the
multi-gigabyte Quartus install does not block RTL development.

## Installed tools

| Tool | Version | Location | Purpose |
| ---- | ------- | -------- | ------- |
| Icarus Verilog | 14.0 (devel) | `C:\iverilog` | compile and simulate SystemVerilog |
| GTKWave | 3.4.0 (nightly standalone) | `C:\Users\CJ\opt\gtkwave` | view VCD waveforms |
| xPack RISC-V GCC | 15.2.0-1 (`riscv-none-elf-gcc`) | `C:\Users\CJ\opt\xpack-riscv-none-elf-gcc-15.2.0-1` | cross-compile programs to RV32I |
| xPack windows-build-tools | 4.4.1-3 (GNU Make 4.4.1) | `C:\Users\CJ\opt\xpack-windows-build-tools-4.4.1-3` | make |

All four `bin` directories are on the user PATH. New terminals pick them up;
terminals opened before the install will not.

## Standard invocations

Simulation, one testbench at a time:

```
iverilog -g2012 -o sim/build/alu_tb.vvp rtl/alu.sv tb/alu_tb.sv
vvp sim/build/alu_tb.vvp
```

`-g2012` enables the SystemVerilog subset Icarus supports. Testbenches dump
waveforms with `$dumpfile`/`$dumpvars` and get viewed with `gtkwave file.vcd`.

Cross-compilation for the CPU:

```
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0x0 -o prog.elf prog.s
riscv-none-elf-objcopy -O binary prog.elf prog.bin
```

The xPack toolchain names binaries `riscv-none-elf-*`, not `riscv32-unknown-elf-*`.
It is a multilib build, so `-march=rv32i -mabi=ilp32` selects a pure RV32I target.
Both invocations were smoke-tested on install day and work.

## Icarus SystemVerilog limits

Icarus 14 handles the subset this project uses: `logic`, `always_ff`, `always_comb`,
packages, enums, parameters, `$readmemh`. It does not support interfaces or other
advanced SV features. The code rules already keep the RTL inside the safe subset.
Everything gets re-verified by Quartus synthesis before touching hardware.

## Quartus (pending install)

Synthesis needs Quartus Prime Lite Edition 23.1std. That is the last release line
that supports the Cyclone V; the newer Pro editions dropped it. Download from the
Intel FPGA Software Download Center (requires a free Intel account):

1. Quartus Prime Lite Edition 23.1std for Windows
2. Cyclone V device support (part of the same download page, separate file)
3. Optional: Questa Intel Starter Edition, if ModelSim-style simulation is ever
   wanted. It needs a free node-locked license from the Intel licensing portal.
   Icarus covers simulation for now, and skipping Questa saves about 8 GB.

Disk note: about 50 GB free on C: at setup time. Quartus Lite plus Cyclone V
support installs to roughly 15 GB. Fine, but do not also install Questa without
checking free space first.
