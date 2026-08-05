# Single-cycle datapath architecture

Design decisions for the single-cycle RV32I core. This is the contract the RTL
implements. Updated as the design evolves; last touched 2026-08-04 (phase 2,
memory system and core integration).

## Datapath overview

One instruction per clock. The PC feeds instruction memory, the instruction is
decoded combinationally, the register file is read, the ALU computes, data
memory is accessed, and the result is written back to the register file on the
next rising edge. No pipeline registers.

```
        +-----+   +------+   +----------+   +-----+   +------+   +--------+
 pc --> |imem | ->|decode| ->| reg_file | ->| alu | ->| dmem | ->|writeback|--+
        +-----+   +------+   +----------+   +-----+   +------+   +--------+  |
   ^                                            |                            |
   +--- next-pc logic (branch_cmp, adders) <----+                            |
                              reg_file write port <--------------------------+
```

Next-PC selection:

- default: pc + 4
- branch taken or jal: pc + imm (dedicated adder in cpu_top, not the ALU)
- jalr: (rs1 + imm) & ~1, taken from the ALU result with bit 0 cleared

The ALU computes the jalr target (rs1 + imm) so no third adder is needed.
Branches are resolved by a dedicated comparator (branch_cmp), not the ALU, so
the ALU stays free of condition-flag logic.

## Modules (phase 1)

All synthesizable modules import `rv32_pkg`. Widths are parameterized with
`DATA_WIDTH` (32) where it aids readability.

### rv32_pkg (package, rtl/rv32_pkg.sv)

Shared types and constants:

- `alu_op_e`: enum `logic [3:0]` with ALU_ADD, ALU_SUB, ALU_AND, ALU_OR,
  ALU_XOR, ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU, ALU_PASS_B
- opcodes (7 bit): OP_LUI, OP_AUIPC, OP_JAL, OP_JALR, OP_BRANCH, OP_LOAD,
  OP_STORE, OP_IMM, OP_REG
- funct3 constants for branches (F3_BEQ, F3_BNE, F3_BLT, F3_BGE, F3_BLTU,
  F3_BGEU), loads/stores (F3_LB, F3_LH, F3_LW, F3_LBU, F3_LHU), and ALU
  selection (F3_ADD_SUB, F3_SLL, F3_SLT, F3_SLTU, F3_XOR, F3_SRL_SRA, F3_OR,
  F3_AND)
- `wb_sel_e`: enum `logic [1:0]` with WB_ALU, WB_MEM, WB_PC4

### alu (rtl/alu.sv)

Pure combinational. Inputs `a`, `b` (32 bit), `op` (alu_op_e). Output `result`.
Shifts use `b[4:0]` as the amount. ALU_SLT and ALU_SLTU produce 32'd0 or 32'd1.
ALU_PASS_B outputs `b` unchanged (used by lui). No flags, no zero output.

### reg_file (rtl/reg_file.sv)

32 registers of 32 bits. Two combinational read ports (`rs1_addr` ->
`rs1_data`, `rs2_addr` -> `rs2_data`), one synchronous write port (`rd_addr`,
`rd_data`, `rd_we`) on posedge clk. x0 is hardwired: reads of address 0 return
0, writes to address 0 are ignored. Synchronous active-low reset clears all
registers to zero.

### imm_gen (rtl/imm_gen.sv)

Pure combinational. Input `instr` (32 bit), output `imm` (32 bit, sign
extended). Format selected by opcode:

- I: OP_LOAD, OP_IMM, OP_JALR
- S: OP_STORE
- B: OP_BRANCH
- U: OP_LUI, OP_AUIPC (imm = upper 20 bits, low 12 zero)
- J: OP_JAL

Unknown opcode produces 0.

### branch_cmp (rtl/branch_cmp.sv)

Pure combinational. Inputs `rs1_data`, `rs2_data`, `funct3`. Output `taken`.
Implements beq, bne, blt (signed), bge (signed), bltu, bgeu. Undefined funct3
values produce taken = 0.

### control (rtl/control.sv)

Pure combinational decoder. Inputs `opcode` (instr[6:0]), `funct3`
(instr[14:12]), `funct7_b5` (instr[30]). Outputs and their meaning:

| signal      | width    | meaning                                    |
| ----------- | -------- | ------------------------------------------ |
| reg_write   | 1        | write rd this cycle                        |
| alu_a_src   | 1        | 0 = rs1_data, 1 = pc                       |
| alu_b_src   | 1        | 0 = rs2_data, 1 = imm                      |
| alu_op      | alu_op_e | ALU operation                              |
| wb_sel      | wb_sel_e | writeback source: ALU, MEM, or PC+4        |
| mem_read    | 1        | data memory read (loads)                   |
| mem_write   | 1        | data memory write (stores)                 |
| branch      | 1        | conditional branch, next pc uses branch_cmp|
| jump        | 1        | jal, next pc = pc + imm                    |
| jalr        | 1        | jalr, next pc = alu result with bit 0 clear|

Decode table:

| instr class | alu_a | alu_b | alu_op         | reg_write | wb_sel | mem_read | mem_write | branch | jump | jalr |
| ----------- | ----- | ----- | -------------- | --------- | ------ | -------- | --------- | ------ | ---- | ---- |
| R-type      | rs1   | rs2   | funct3/funct7  | 1         | ALU    | 0        | 0         | 0      | 0    | 0    |
| I-arith     | rs1   | imm   | funct3 (+b30 for srai) | 1 | ALU    | 0        | 0         | 0      | 0    | 0    |
| load        | rs1   | imm   | ADD            | 1         | MEM    | 1        | 0         | 0      | 0    | 0    |
| store       | rs1   | imm   | ADD            | 0         | x      | 0        | 1         | 0      | 0    | 0    |
| branch      | x     | x     | x              | 0         | x      | 0        | 0         | 1      | 0    | 0    |
| jal         | x     | x     | x              | 1         | PC4    | 0        | 0         | 0      | 1    | 0    |
| jalr        | rs1   | imm   | ADD            | 1         | PC4    | 0        | 0         | 0      | 0    | 1    |
| lui         | x     | imm   | PASS_B         | 1         | ALU    | 0        | 0         | 0      | 0    | 0    |
| auipc       | pc    | imm   | ADD            | 1         | ALU    | 0        | 0         | 0      | 0    | 0    |

ALU op from funct3 for R-type and I-arith: 000 ADD (SUB when R-type and
instr[30]), 001 SLL, 010 SLT, 011 SLTU, 100 XOR, 101 SRL (SRA when instr[30]),
110 OR, 111 AND. For I-arith, instr[30] only matters for shifts (srai); addi
ignores it because it is part of the immediate.

Unknown opcodes decode to all zeros (a nop that writes nothing).

## Memory map

| region | base        | size            | notes                          |
| ------ | ----------- | --------------- | ------------------------------ |
| imem   | 0x0000_0000 | 4 KB, 1024 words| reset vector is 0x0000_0000    |
| dmem   | 0x0000_1000 | 4 KB, 1024 words| read/write data                |
| mmio   | 0xFFFF_0000 | 64 KB window    | peripheral registers, map below|

Address decode lives outside cpu_top: the core emits full 32-bit byte
addresses, and the instantiating level (testbench now, board top later) maps
them onto memories and peripherals. The dmem word index is addr[11:2] within
its region. Misaligned accesses are not supported and have undefined behavior;
there is no trap machinery.

## Modules (phase 2)

### imem (rtl/imem.sv)

Instruction memory, word addressed, asynchronous read. Parameters ADDR_WIDTH
(word index width, default 10) and INIT_FILE (hex file loaded with $readmemh
when nonempty). Ports: `addr` (word index), `rdata` (32 bit). Read only.

Initialization uses an `initial $readmemh` block. This is the one sanctioned
use of `initial` in synthesizable code: Quartus honors it as block RAM initial
content, which is exactly how programs get preloaded at synthesis time.

Note on synthesis: asynchronous read keeps the core single cycle but means
Quartus will not infer M10K block RAM (M10K needs a registered read address).
Small memories land in MLABs or logic instead. Acceptable at this size;
revisit at hardware bring-up if resource usage hurts.

### dmem (rtl/dmem.sv)

Data memory, word addressed with per-byte write lanes, asynchronous read.
Parameters ADDR_WIDTH (default 10), DATA_WIDTH (32), INIT_FILE (optional
$readmemh preload, later useful for .data sections). Ports: `clk`, `addr`
(word index), `wdata`, `byte_en` (4 bit), `we`, `rdata`. Writes happen on
posedge clk for each lane where `we && byte_en[i]`. Reads return the full
word; lane extraction is the lsu's job.

The memory array has no reset. Block RAM contents cannot be cleared by a reset
signal, so this sequential block is exempt from the rst_n rule. Contents are
undefined at power-up unless INIT_FILE is given.

### lsu (rtl/lsu.sv)

Load-store unit, pure combinational, sits between the core datapath and raw
word memory. Handles lane steering and extension for byte and halfword access.

Store path: inputs `funct3`, `addr_lo` (addr[1:0]), `store_data` (rs2 value).
Outputs `mem_wdata` (store data shifted into the correct lanes) and `mem_be`
(4-bit byte enable). sb enables one lane, sh enables two (addr_lo[1] picks the
half), sw enables all four. Undefined funct3 produces mem_be = 0 so nothing is
written.

Load path: inputs `funct3`, `addr_lo`, `mem_rdata` (raw word). Output
`load_data`: lb/lbu select the addressed byte and sign/zero extend, lh/lhu the
addressed halfword, lw passes through. Undefined funct3 produces 0.

### cpu_top (rtl/cpu_top.sv)

The single-cycle core: all phase 1 modules plus the lsu, PC register, and
muxes. Memories stay outside so the same core drops into the testbench now and
the board top with MMIO decode later. Parameter RESET_VECTOR (default
32'h0000_0000).

Ports: `clk`, `rst_n`; instruction bus `imem_addr` (byte address, the PC) and
`imem_rdata`; data bus `dmem_addr` (byte address), `dmem_wdata`, `dmem_be`,
`dmem_we`, `dmem_re`, `dmem_rdata`.

Internals:

- PC register, synchronous active-low reset to RESET_VECTOR
- pc_plus4 adder and a branch-target adder (pc + imm) shared by branches and jal
- instruction field slicing: rs1 = instr[19:15], rs2 = instr[24:20],
  rd = instr[11:7], funct3 = instr[14:12], funct7_b5 = instr[30]
- ALU input muxes per control: a = rs1_data or pc, b = rs2_data or imm
- next-pc priority mux: jalr takes alu_result with bit 0 cleared, else jump or
  taken branch takes pc + imm, else pc_plus4
- writeback mux per wb_sel: alu_result, lsu load_data, or pc_plus4
- dmem_addr = alu_result, dmem_we = mem_write, dmem_re = mem_read, byte
  enables and wdata from the lsu store path

### cpu_top_tb (tb/cpu_top_tb.sv)

Instantiates cpu_top, imem, and dmem, decoding dmem at 0x1000 (addr[31:12] ==
20'h00001). Runs a list of assembled test programs. Per test: load the hex
into imem with $readmemh, pulse reset, run until the program signals done or a
cycle budget expires, then check architectural state through hierarchical
references into the register file and dmem array.

Done convention: a finished test program stores the magic word 32'h0000600D to
the last dmem word (byte address 0x1FFC). Timeout is a test failure.

Test programs live in tb/programs/ as assembly source plus committed .hex
files (regenerated with the cross toolchain via a make target, committed so
`make test` does not require the toolchain):

- arith: R-type and I-type results landing in known registers
- mem: sw/lw, sb/lb/lbu, sh/lh/lhu across byte lanes, sign extension cases
- branch: each branch taken and not taken, jal/jalr call and return, lui/auipc

## MMIO register map

The mmio region is selected when addr[31:16] == 16'hFFFF. Word access only.
Loads from unmapped mmio addresses return 0; stores to them are ignored. The
map is fixed here in phase 3 so programs and the simulation model agree; the
synthesizable mmio block in phase 4 implements the same map.

| address     | name  | access | meaning                                        |
| ----------- | ----- | ------ | ---------------------------------------------- |
| 0xFFFF_0000 | LEDR  | R/W    | bits 9:0 drive the red LEDs, readable for RMW  |
| 0xFFFF_0004 | SW    | R      | bits 9:0, current slide switch positions       |
| 0xFFFF_0008 | KEY   | R      | bits 3:0, pushbuttons, 1 means pressed (the hardware normalizes the board's active-low pins) |
| 0xFFFF_0010 | HEX0  | R/W    | bits 6:0, segments a..g active high (hardware inverts for the board's active-low displays) |
| 0xFFFF_0014 | HEX1  | R/W    | same layout                                    |
| 0xFFFF_0018 | HEX2  | R/W    | same layout                                    |
| 0xFFFF_001C | HEX3  | R/W    | same layout                                    |
| 0xFFFF_0020 | HEX4  | R/W    | same layout                                    |
| 0xFFFF_0024 | HEX5  | R/W    | same layout                                    |
| 0xFFFF_0030 | CYCLE | R      | free-running 32 bit cycle counter, 0 at reset  |

Software conventions (linker layout, crt0, build flow, sim vs hardware
builds) live in claude-docs/software.md.

## Deferred to later phases

- Synthesizable mmio block, board top, pin assignments, Quartus project (phase 4)
- Reaction timer demo needs buttons on real hardware to be interesting; a
  simulation-only version ships in phase 3 (phase 4 wires it to the board)
- Pipeline registers, hazards, forwarding (phase 5)

## Testing strategy

Every module has a self-checking testbench in tb/ that prints one final
"PASS: <module>" line or "FAIL: <detail>" lines and exits nonzero on failure
via $fatal. Testbenches dump VCD waveforms for GTKWave. `make test` builds and
runs every testbench in Icarus Verilog and fails loudly if any test fails.
Directed cases cover each instruction or operation the module handles, plus
edge cases: x0 behavior, sign extension boundaries, shift amounts of 0 and 31,
signed/unsigned comparison around 0x80000000, and negative immediates.
