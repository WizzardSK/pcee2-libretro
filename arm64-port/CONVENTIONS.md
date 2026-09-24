# CONVENTIONS — ARM64 recompilers

> How the ARM64 recompilers in `pcsx2/arm64/` are written. Grounded in what
> already exists in `pcsx2/arm64/AsmHelpers.h`, `aR5900.h` and `Vif_Dynarec.cpp`
> — when in doubt, copy the patterns already in those files.

---

## 1. The emitter: VIXL MacroAssembler

All ARM64 codegen goes through VIXL's `MacroAssembler`, accessed via the
thread-local `armAsm` pointer (`AsmHelpers.h`). The VIF dynarec
(`Vif_Dynarec.cpp`) is the smallest complete worked example — read it before
writing new emission code.

Block lifecycle (see `AsmHelpers.cpp`):
- `armSetAsmPtr(ptr, capacity, pool)` — point the assembler at a code buffer.
- `armStartBlock()` / `armEndBlock()` — begin/finalize a block; returns code ptr.
- `armGetCurrentCodePointer()` — current emit position.
- `armAlignAsmPtr()` — alignment between blocks.

Helpers to reuse instead of re-rolling:
- `armEmitJmp(ptr)` / `armEmitCall(ptr)` — far jump/call (handles range via trampolines).
- `armEmitCbnz(reg, ptr)` / `armEmitCondBranch(cond, ptr)` — conditional far branches.
- `armMoveAddressToReg(reg, addr)` — materialize a 64-bit address.
- `armLoadPtr` / `armStorePtr` — load/store a pointer-sized value at an absolute addr.
- `armBeginStackFrame(save_fpr)` / `armEndStackFrame(save_fpr)` — prologue/epilogue.
- `armOffsetMemOperand`, `armGetMemOperandInRegister` — address/offset helpers.
- `armLoadConstant128`, `armEmitVTBL` — 128-bit literal load, NEON table lookup.
- `GetPCDisplacement(cur, tgt)` — PC-relative branch displacement (>>2).

Constant pool: `ArmConstantPool` (`AsmHelpers.h`) provides `GetJumpTrampoline`,
`GetLiteral` (u64 / u128 / bytes), and `EmitLoadLiteral`. Use it for far targets
and 128-bit constants rather than inlining.

`armDisassembleAndDumpCode(ptr, size)` dumps emitted ARM64 — see `DEBUGGING.md`.

---

## 2. Register allocation map

Shared scratch and ABI registers, defined in `AsmHelpers.h`. Do not reassign them.

| Macro | Reg | Role |
|---|---|---|
| `RXRET` / `RWRET` / `RQRET` | x0 / w0 / q0 | Return value |
| `RXARG1..4` / `RWARG1..4` | x0–x3 / w0–w3 | Call arguments (AAPCS64) |
| `RXVIXLSCRATCH` / `RWVIXLSCRATCH` | x16 / w16 | VIXL internal scratch — **do not hold state here** |
| `RSCRATCHADDR` | x17 | Address-calculation scratch |
| `RQSCRATCH*` | q30 / d30 / s30 | Vector scratch #1 (also `RQSCRATCHI/F/D` views) |
| `RQSCRATCH2*` | q31 / d31 / s31 | Vector scratch #2 |
| `RQSCRATCH3*` | q29 / d29 / s29 | Vector scratch #3 |

Persistent EE state, defined in `aR5900.h` — callee-saved so it survives calls
into the interpreter and C++ helpers. Never use these as scratch in a generator:

| Macro | Reg | Role |
|---|---|---|
| `RESTATEPTR` | x19 | `&cpuRegs` — base for guest GPR / PC / HI/LO accesses |
| — | x20 | EE guest-GPR cache register (`REC_GPR_CACHE_REGS` in `aR5900.cpp`) |
| `REVTLBPTR` | x21 | vtlb table base (the non-fastmem fallback path) |
| `RFASTMEMBASE` | x28 | host-MMU fastmem base (`vtlbdata.fastmem_base`), pinned in `recGenDispatchers` when fastmem is on |

ABI reminders (AAPCS64):
- **x18 is the platform register** (reserved on macOS and Windows) — never use it.
- x29 = FP, x30 = LR, sp / xzr special. In an immediate-operand position the
  register number 31 means **sp**, not xzr — check what VIXL emits.
- Callee-saved GPRs: **x19–x28** (+ x29/x30). Callee-saved SIMD: **v8–v15** (low 64 bits only).
- `armIsCalleeSavedRegister(reg)` tells you if a reg must be preserved.

Guest → host mapping:
- EE/VU 128-bit registers → NEON `v0–v31` (q regs). 64-bit GPR halves via `ldp/stp`.
- 32-bit MIPS GPRs (IOP) → ARM64 w-registers.
- MIPS FPU (COP1) → `s0–s31` (single) / `d0–d31` (double).

---

## 3. Build / test loop

Change one or two functions, rebuild, test, commit — do not write hundreds of
lines before compiling. The core builds as in `CLAUDE.md`:

```sh
cmake --build build --target pcee2_libretro
retroarch -L build/pcee2_libretro.so path/to/game.iso
```

Test a change on a BIOS boot, a 2D game, an IOP-heavy game and a 3D game before
calling it done. The *CPU Recompiler (JIT)* core options turn off the EE, IOP,
VU0 and VU1 recompilers one at a time, which is the quickest way to tell which
one a crash belongs to.

---

## 4. Correctness discipline

- **The interpreter is the ground truth.** When JIT output diverges, diff against
  the C++ semantics in `Interpreter.cpp` (EE), `R3000AInterpreter.cpp` (IOP),
  `VU0microInterp.cpp` / `VU1microInterp.cpp` (VU). Opcode dispatch:
  `R5900OpcodeTables.cpp`.
- **Interpreter fallback is allowed.** Rare or complex ops may call back via
  `recCall(Interp::...)`; mark such places clearly.
- **x86 is the reference implementation, never the thing to break.** Mirror the
  structure of `pcsx2/x86/` (`iR5900*.cpp`, `recVTLB.cpp`, `iR3000A.cpp`,
  `microVU*`), translating x86emitter calls to VIXL.

---

## 5. Code placement & guards

- ARM64 rec files live in `pcsx2/arm64/` and are registered in
  `pcsx2/CMakeLists.txt` (`pcsx2arm64Sources` / `pcsx2arm64Headers`).
- Gate ARM64 code in shared files with `#ifdef ARCH_ARM64` / `#ifdef ARCH_X86`
  (from `common/Pcsx2Defs.h`). **Not** `_M_ARM64` / `_M_X86`: those are
  MSVC-only, so under clang or GCC `#ifdef _M_ARM64` is dead code and
  `#ifndef _M_X86` is true on x86 too. Upstream's own `#ifdef _M_X86` blocks in
  `VMManager.cpp` (`InitializeCPUProviders` and friends) are where the ARM64
  recs are hooked in, in their `#else` branches.
- **Never** remove or weaken the x86 path.

---

## 6. Commits

- On `libretro`, or a `libretro-arm64-*` branch to run the CI matrix first.
- One opcode family or subtask per commit, message `ARM64: <what>` — e.g.
  `ARM64: microVU — fix FTOI NaN-pattern inputs`.
