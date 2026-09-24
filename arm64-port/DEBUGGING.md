# DEBUGGING — ARM64 recompilers

Techniques and tools for debugging the ARM64 JIT. The examples run the core in
RetroArch; the environment variables are read by the core, so they go on the
frontend's command line.

---

## 1. microVU1 ⇆ interpreter shadow differential

The main tool for finding where the **microVU1 recompiler** produces wrong output.
Lives in `pcsx2/arm64/aVU.cpp`. Enabled entirely through environment variables,
no rebuild required. Output goes to a dedicated file as `MVUDIFF key=value` records
so you can grep, diff, or feed them to a script without scraping the emulator log.

### How it works

microVU1 runs as the real, committed VU1 — the game is completely unperturbed.
After each VU1 program finishes, the harness:

1. Snapshots microVU's output state (VF/VI/ACC/Q/Mem).
2. Rewinds VU1 to the program's input.
3. Re-runs the **interpreter** over that same input as a side-effect-suppressed
   shadow (ground truth).
4. Compares the two and logs any divergences.

VU1 state and the non-VU1 globals the shadow can disturb (`VPU_STAT`, VIF's `VEW`,
`cpuRegs.cycle`) are restored to microVU's committed values afterwards. XGKICK GS
transfers and D/T-bit `INTC` raises are suppressed during the shadow run via
`g_mvuShadowRun`, which gates paths in `VUops.cpp`, `aVU_Lower.inl`, and
`VU1microInterp.cpp`. The BIOS boots identically with and without the harness active.

### Environment variables

All parsed once at startup:

| Variable | Default | Meaning |
|---|---|---|
| `MVU_DIFF=1` | off | Enable the harness. |
| `MVU_DIFF_OUT=<path>` | `mvudiff.log` | Output file path. |
| `MVU_DIFF_PC=<hex>` | all | Only diff programs whose entry byte-PC equals this. |
| `MVU_DIFF_REG=<list>` | everything | Comma-separated watch-list: `vfNN`, `viNN`, `acc`, `q`, `mac`, `status`, `clip`. Naming a reg also shows its benign diffs. |
| `MVU_DIFF_SKIP=<n>` | 0 | Skip the first `n` diverging programs before the localizer fires. |
| `MVU_DIFF_MAX=<n>` | 200 | Total report line cap (`0` = unlimited). |
| `MVU_DIFF_ULP=<n>` | 4 | FP gap in ULPs treated as benign rounding (`0` = require bit-exact). |
| `MVU_LOC=1` | off | On first real divergence, run the per-instruction localizer. Must be set at startup — it gates the trace injection hooks. |
| `MVU_VF=1` | off | Include VF regs in the per-step localizer compare (noisy near DIV/WAITQ). |
| `MVU_DIFF_QRAW=1` | off | Report the DIV-latency `Q` artifact as a real divergence instead of suppressing it. |

### What counts as a real divergence

Sets `result=DIVERGE` and fires the localizer:
- A computed integer register `VI01–15` (these drive branches and addressing).
- VF / ACC / memory differing by more than `MVU_DIFF_ULP` ULPs, a sign flip, or a NaN.
- A control-flow (next-PC) mismatch.

Suppressed under a watch-all run (benign by design):
- Lazily materialized flag regs `VI16–18` — microVU only writes these when a program
  reads them, so they legitimately differ mid-program from the interpreter. The real
  signal is a downstream computed register that a wrong flag feeds into.
- FP rounding within the ULP tolerance — microVU's `fmul`+`fadd` vs the interpreter's
  FMAC accumulate a consistent 1-LSB difference, same as x86 microVU.
- The DIV-latency `Q` artifact.

Explicitly naming a register in `MVU_DIFF_REG` shows and counts all of its diffs
including benign ones, e.g. `MVU_DIFF_REG=mac,status` to chase flag bugs.

### Recipes

```bash
# Find the first diverging program and localize it to the instruction:
MVU_DIFF=1 MVU_LOC=1 MVU_DIFF_OUT=/tmp/gow2.log \
  retroarch -L build/pcee2_libretro.so path/to/game.iso

# Focus on one program (its entry byte-PC from the log) and watch flags + accumulator:
MVU_DIFF=1 MVU_DIFF_PC=0x00d8 MVU_DIFF_REG=mac,status,clip,acc MVU_LOC=1 \
  MVU_DIFF_OUT=/tmp/narrow.log \
  retroarch -L build/pcee2_libretro.so path/to/game.iso

# Require bit-exact FP (removes the ULP benign classification):
MVU_DIFF=1 MVU_DIFF_ULP=0 MVU_DIFF_OUT=/tmp/exact.log \
  retroarch -L build/pcee2_libretro.so path/to/game.iso

# Skip the first 5 divergences before the localizer fires (useful when the first
# few are known-harmless BIOS programs that aren't the bug you care about):
MVU_DIFF=1 MVU_LOC=1 MVU_DIFF_SKIP=5 MVU_DIFF_OUT=/tmp/skip.log \
  retroarch -L build/pcee2_libretro.so path/to/game.iso
```

### Reading the output

Each record is one line of `key=value` pairs. Key fields:

- `prog_pc=XXXX` — program entry byte-PC (matches `MVU_DIFF_PC`).
- `reg=VF01` / `reg=VI03` / `reg=ACC` / `reg=MEM[0040]` — which register or memory
  quadword diverged.
- `int=...` / `mvu=...` — interpreter value vs microVU value.
- `BENIGN=fp-ulp` — the diff is within the ULP tolerance (only logged when the reg is
  explicitly watched).
- `result=DIVERGE` — at least one real (non-benign) divergence was found in this program.

The per-instruction localizer (MVU_LOC) emits a `==== FIRST DIVERGENCE ====` block with
the diverging op disassembled, the exact register mismatch, an 8-op context window, and
the full program disasm with the diverging instruction marked `->`.

---

## 2. Inspecting emitted JIT code

`armDisassembleAndDumpCode(ptr, size)` (declared in `pcsx2/arm64/AsmHelpers.h`)
disassembles and prints a range of emitted ARM64 instructions to the console. Use it
when a JIT block crashes or produces wrong output and you need to see what was actually
emitted.

```cpp
// After compiling a block, dump it:
armDisassembleAndDumpCode(block->codeStart, block->codeSize);
```

For the VU recompiler you can also read the per-program code range out of the
`microBlock` struct and dump it the same way.

---

## 3. gdb / lldb

### Basic launch

```bash
# gdb (Linux, Android):
MVU_DIFF=1 MVU_LOC=1 gdb --args retroarch -L build/pcee2_libretro.so path/to/game.iso

# lldb (macOS):
lldb -- retroarch -L build/pcee2_libretro.so path/to/game.iso
(lldb) env MVU_DIFF=1 MVU_LOC=1
(lldb) run
```

### Handling JIT-generated signals

The JIT uses SIGSEGV for vtlb fastmem fault handling. By default the debugger stops
on every signal, which makes running games impossible. Pass them through:

```
(gdb) handle SIGSEGV nostop noprint pass
(gdb) handle SIGBUS nostop noprint pass

(lldb) process handle SIGSEGV --stop false --notify false --pass true
(lldb) process handle SIGBUS  --stop false --notify false --pass true
```

If you need to stop on a *specific* crash (not vtlb), set a conditional breakpoint or
re-enable the signal just before the suspect code runs.

### Breakpoints in JIT-emitted code

JIT code lives at dynamic addresses. The easiest way to break into it is to set a
breakpoint on the C++ function that hands off to the block, then step into the emitted
code:

```
# Break when a specific VU1 program is about to execute:
(lldb) b recMicroVU1::Execute
(lldb) condition 1 (VU1.VI[REG_TPC].UL == 0xd8)   # byte-PC >> 3 for word-PC

# Or break on the shadow harness entry:
(lldb) b mvuDiffReport
```

To break at an arbitrary emitted address (once you know it from a log or dump):

```
(lldb) br set -a 0x<address>
```

The commands below are lldb's; gdb has the same operations (`break`,
`info registers`, `x/20i $pc`, `watch`, `bt`).

### Inspecting ARM64 registers

```
(lldb) register read          # all general-purpose registers
(lldb) register read x0 x1 x2
(lldb) register read --format hex v0  # NEON / VF register

# After a crash in JIT code, the PC tells you where it died:
(lldb) register read pc
(lldb) disassemble --start-address <pc-value> --count 20
```

### Inspecting VU state from C++ context

```
# Print VF registers (128-bit each, stored as VECTOR in VURegs):
(lldb) p VU1.VF[1]
(lldb) p/x VU1.VI[REG_TPC].UL
(lldb) p/x VU1.ACC

# Check the shadow-run flag:
(lldb) p g_mvuShadowRun

# Dump 16 bytes of VU1 data memory at offset 0x40:
(lldb) memory read --size 4 --format x VU1.Mem+0x40
```

### Watchpoints

Useful for catching when a specific VU memory location or register gets a wrong value:

```
# Break when VU1.VF[24] is written:
(lldb) watchpoint set expression -w write -- &VU1.VF[24]

# Break when the shadow flag is set:
(lldb) watchpoint set variable g_mvuShadowRun
```

### Backtrace and frames

```
(lldb) bt           # full backtrace
(lldb) frame select 3
(lldb) p someLocalVar
```

### Scripted conditional stop (useful for JIT loops)

```
# Stop only on the Nth call to a function (e.g. the 50th Execute):
(lldb) b recMicroVU1::Execute
(lldb) breakpoint command add 1
  > if ($__bp_id == 50): stop
  > DONE
```

---
