# Single-cycle datapath architecture

Design decisions for the single-cycle RV32I core. This is the contract the RTL
implements. Updated as the design evolves; last touched 2026-08-04 (phase 1,
leaf modules).

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

## Deferred to later phases

- Instruction and data memory, byte/halfword load-store logic (phase 2)
- cpu_top wiring, PC register, next-pc mux, top-level testbench (phase 2)
- Memory-mapped I/O decode (phase 4)
- Pipeline registers, hazards, forwarding (phase 5)

## Testing strategy (phase 1)

Every module has a self-checking testbench in tb/ that prints one final
"PASS: <module>" line or "FAIL: <detail>" lines and exits nonzero on failure
via $fatal. Testbenches dump VCD waveforms for GTKWave. `make test` builds and
runs every testbench in Icarus Verilog and fails loudly if any test fails.
Directed cases cover each instruction or operation the module handles, plus
edge cases: x0 behavior, sign extension boundaries, shift amounts of 0 and 31,
signed/unsigned comparison around 0x80000000, and negative immediates.
