# PROGRESS — ARM64 Recompiler Port

> Living roadmap. **This is the source of truth for "what's done" and "what's next."**
> Update it at the end of every session. Status legend:
> `[ ]` not started · `[~]` in progress · `[x]` done · `[!]` blocked (see JOURNAL).

---

## ▶ CURRENT FOCUS

**Host-MMU fastmem for EE load/store** — replace the per-access `vtlb_memRead/Write`
C-call (`aR5900LoadStore.cpp`, the current path for *every* memory op) with base-relative
(`x28`) fastmem + SIGSEGV backpatch. Full phased plan in **`arm64-port/FASTMEM_PLAN.md`**
(ports the memory half of ARMSX2 `ee33d237`). All the shared infra — region reservation,
RAM mapping, `vtlb_AddLoadStoreInfo`/`vtlb_BackpatchLoadStore`, mach-exception fault
delivery — already exists and is live on ARM64/macOS; only the emit + `vtlb_DynBackpatchLoadStore`
thunk are ours to write. **Start at F0** (confirm x28 free + fastmem base allocates).

Just-ported (ARMSX2 `673135b0`, pending build verify): MMI integer MADD/MADDU/MADD1/MADDU1,
MFHI1/MTHI1/MFLO1/MTLO1, native BC0F/BC0T (+likely) with CPCOND0 DMA-wait idle-skip, and
the Count/PERF MFC0/MTC0 commit-then-inline (`recCop0NeedsLiveCycle`) replacing their
single-step. Skipped that commit's EI/ERET rework — we already have `recIsForcedEventTestOp`.

---

## Phase 0 — Prerequisites & Tooling

- [x] 0.1 Build native ARM64 binary; verify it launches (`build/pcsx2-qt/PCSX2.app`, confirmed `arm64`).
- [x] 0.2 Confirm CPU-provider fallbacks on ARM64 (`VMManager.cpp:2727-2731` force interpreters).
- [x] 0.3 Gap audit: verified NO dormant EE/IOP/VU rec code exists in repo history — full port required. (See JOURNAL #0.)
- [x] 0.4 Read existing `pcsx2/arm64/` infra (`AsmHelpers`, `Vif_Dynarec`, `Vif_UnpackNEON`).
- [x] 0.5 Study VIXL MacroAssembler API + existing `arm64/AsmHelpers.{h,cpp}` block lifecycle (`armSetAsmPtr`/`armStartBlock`/`armEndBlock`, reg-alloc macros, constant pool).
- [x] 0.6 VIXL scratch harness: `tests/ctest/core/arm64_emit_test.cpp` (gtest `Arm64Emit.*`) mmaps a `MAP_JIT` buffer, emits add/const/load-store via `armAsm`, executes it, asserts results. **All 3 pass.** Proves emit+execute end-to-end.

**Done when:** we can JIT-emit and execute arbitrary ARM64 from a test, and we
understand the existing `pcsx2/arm64/` patterns well enough to copy them.

---

## Phase 1 — EE Recompiler Skeleton

- [x] 1.1 Created `pcsx2/arm64/aR5900.h` — pins persistent host regs: `RESTATEPTR`=x19 (`&cpuRegs`), `REFASTMEMBASE`=x20 (fastmem base), `REVTLBPTR`=x21 (vtlb base, Phase 2).
- [x] 1.2 Created `pcsx2/arm64/aR5900.cpp` — defines `recCpu` with stub provider fns (recExecute = `pxFailRel`, rest no-op); added both files to `pcsx2arm64Sources`/`Headers`. Builds + links; binary still arm64; unittests green.
- [x] 1.3 `recReserve()`/`recShutdown()`/`recResetEE()`: carve the SysMemory-reserved EE rec region (`GetEERec()`..`GetEERecEnd()`) into a code area + a 1 MB tail `ArmConstantPool`; `recPtr`/`recPtrEnd` cursor. Builds, links, arm64, unittests green.
- [x] 1.4 Minimal block compile loop: `recCompileBlock()` emits NOP/NOP/RET via VIXL through the real `armSetAsmPtr`/`armStartBlock`/`armEndBlock` lifecycle on the EE code cache, advances `recPtr` (resets cache past `recPtrEnd`); `recExecute()` enters the block and returns. Builds, links, arm64, unittests green.
- [x] 1.5 Wired `recCpu` into `VMManager.cpp`: added `#else` (ARM64) branches to the `_M_X86` guards in `InitializeCPUProviders` (`recCpu.Reserve()`), `ShutdownCPUProviders` (`recCpu.Shutdown()`), and `ClearCPUExecutionCaches` (`recCpu.Reset()`). `UpdateCPUImplementations` left untouched — `Cpu = &intCpu;` (rec reserved, not selected). Builds, links, arm64, unittests green; **verified on real BIOS boot** (no crash).

**Done when:** ARM64 build compiles + runs with the rec reserved/active, even if it
still defers all real work to the interpreter. ✅ **DONE** (BIOS boot verified).

---

## Phase 2 — vtlb Fast Memory & Load/Store  *(highest priority after skeleton)*

- [x] 2.1 Slow-path vtlb load/store codegen in `pcsx2/arm64/aR5900LoadStore.cpp`: `armEmitVtlbRead/Write` + `...Quad`, emitting calls to the C++ `vtlb_memRead/Write` helpers (interpreter-equivalent path). Builds, links, arm64, unittests green. *(Re-scoped from "implement `vtlb_DynBackpatchLoadStore`" — that is fastmem-only and is now Phase 2.2; see JOURNAL.)*
- [x] 2.2 **Fastmem fast path:** DONE & user-build-verified (all green), commit `2ff13e033d`. Host-MMU
  fastmem: a single `RFASTMEMBASE`(x28)-relative `Ldr`/`Str` on the hot path + SIGSEGV backpatch to the
  slow vtlb helper for MMIO/handler pages. Ported the memory half of ARMSX2 `ee33d237` (jpolo1224) onto our
  EE rec — plan in `arm64-port/FASTMEM_PLAN.md` (F0–F5). All behind `CHECK_FASTMEM` + an `s_eeFastmemBackpatch`
  toggle; the inline vmap path (`REVTLBPTR`=x21) is retained as the fallback for faulting PCs / fastmem-off.
  - **F1** `armEmitJmpPtr` (`AsmHelpers.{cpp,h}`) — W^X-safe in-place overwrite of one instruction with a
    `B imm26` (`BeginCodeWrite`/memcpy/`EndCodeWrite`/`FlushInstructionCache`). gtest `Arm64Emit.JmpPtrInPlacePatch`.
  - **F2** `vtlb_DynBackpatchLoadStore` in `RecStubs.cpp` (was `pxFailRel`) — thunk redoes the access via
    `vtlb_memRead/Write<T>` (+ `…128` quads) using the recorded addr/data reg codes, resolves addr/data
    aliasing, sign/zero-extends loads, resumes after the fault; **no cycle reload** (memory-based cycle model).
    `recBeginThunk`/`recEndThunk` carve a no-const-pool scratch region from the EE code buffer.
  - **F3** emit-side fastmem in all four `recTryTranslateCached{Load,Store}{,Quad}` + `armTryEmitFastmemScalar32`;
    threaded guest `pc` through `recTranslateOp`/`recTranslateOpOptimized`/`recEmitOp`/`recTryTranslateCachedOp`;
    x28 pinned at both dispatcher funnels under `CHECK_FASTMEM`; `vtlb_ClearLoadStoreInfo()` in `recResetRaw`;
    one-shot `[FASTMEM F0]` boot log. GPR cache **8→7** (dropped x28 = `RFASTMEMBASE`; x21 kept for the vmap fallback).
  - **F5** LWC1/SWC1 (`aR5900FPU.cpp`) take `pc` + route through `armTryEmitFastmemScalar32`.
  - Deliberately **NOT** ported from `ee33d237`: direct block chaining (we have recLUT 4.4) and the fast-tier
    register cache (we use x20). Remaining: **F6** SMC/invalidation interaction verify + **F7** perf gate
    (EE-fallback% and fps, fastmem on vs off) — see FASTMEM_PLAN.md.
- [x] 2.3 EE load/store opcode generators: decode + guest-GPR access wired onto `armEmitVtlbRead/Write[Quad]`. `armEmitEffectiveAddr`/`armEmitLoadGpr`/`armEmitStoreGpr` + the 128-bit `armEmitLoadQuad`/`armEmitStoreQuad` (`~0xF` align + NEON q access). `recTranslateOp` dispatches the full aligned family: `LB/LBU/LH/LHU/LW/LWU/LD`, `SB/SH/SW/SD`, `LQ/SQ`. Unaligned `LWL/LWR/LDL/LDR`/`SWL/SWR/SDL/SDR` deferred (byte-merge codegen). Runtime-proven addr+align via 7 `Arm64EmitEE.*` gtests.
- [x] 2.4 Test: full guest-memory round-trip through the scalar + quad generators. 6 new `Arm64EmitEE.*` gtests map a host buffer into the vtlb `vmap` (hand-built direct-pointer entry — no SysMemory/fastmem/page-fault-handler needed since default `EmuConfig` makes `vtlb_memRead/Write` a plain `*vmap[addr>>12].assumePtr(addr)`) and assert store→load, byte sign/zero-extend, doubleword, `$zero`-discard, and quad store/load + align-down all read/write the right bytes. Validates address calc + AAPCS64 marshalling + extension end-to-end.

**Done when:** EE memory ops go through the JIT fastmem path and read/write correctly.

---

## Phase 3 — EE Integer Arithmetic

- [x] 3.1 Immediate ops: `ADDI/ADDIU/SLTI/SLTIU/ANDI/ORI/XORI/LUI/DADDI/DADDIU`.
- [x] 3.2 Reg-reg ops: `ADD/ADDU/SUB/SUBU/SLT/SLTU/AND/OR/XOR/NOR/DADD/DADDU/DSUB/DSUBU`.
- [x] 3.3 Shifts: `SLL/SRL/SRA/SLLV/SRLV/SRAV/DSLLV/DSRLV/DSRAV/DSLL/DSRL/DSRA/DSLL32/DSRL32/DSRA32`.
- [x] 3.4 Moves: `MOVZ/MOVN` (→ `CSEL`), `MFHI/MTHI/MFLO/MTLO`.
- [x] 3.5 Mul/Div: `MULT/MULTU/DIV/DIVU` (+ MMI `MULT1/MULTU1/DIV1/DIVU1` → HI1/LO1). Uses `SMULL/UMULL` (32×32→64) and `SDIV/UDIV` + reload-based remainder. ARM `SDIV` reproduces the EE overflow quirk natively; only ÷0 needs a fixup. MULT/MULTU honour the R5900 3-operand `Rd=LO` write. **MMI multiply-accumulate `MADD/MADDU/MADD1/MADDU1` + pipeline-1 moves `MFHI1/MTHI1/MFLO1/MTLO1`** added (`aR5900MultDiv.cpp`, ARMSX2 `673135b0`); accumulator held in x17 across the widening multiply.
- [ ] 3.6 Constant propagation (`EE_CONST_PROP`): track known-constant GPRs, emit immediate forms.

---

## Phase 4 — EE Branches & Jumps

- [x] 4.1 Jumps: `J/JAL/JR/JALR` — codegen + wired into the block compiler (decoded
  by `recEmitBranch`, delay slot compiled after, block exits to dispatcher).
- [~] 4.2 Conditional branches: `BEQ/BNE/BLEZ/BGTZ/BLTZ/BGEZ/BLTZAL/BGEZAL` —
  codegen + wired (`recEmitBranch`). "Likely" variants (BEQL/BNEL/BLEZL/BGTZL/
  BLTZL/BGEZL/BLTZALL/BGEZALL — delay-slot nullification) run via interpreter
  fallback for now; native codegen still TODO. **COP0 `BC0F/BC0T` (+ likely
  `BC0FL/BC0TL`) native** via CPCOND0 (DMAC STAT/PCR) test — `armEmitBC0F/T`,
  `emitCpcond0Test` in `aR5900Branch.cpp`; wired into `recEmitBranch`/
  `recIsHandledBranch`/`recIsLikelyBranch`; `recBranchConditionReads`→0 so the
  DMA-wait spin idle-skips via the wait-loop fast-forward (ARMSX2 `673135b0`).
- [x] 4.3 **Dispatcher + delay-slot block compiler** — DONE & BIOS-boot verified.
  Multi-instruction `recCompileBlock`; branch generator + delay slot + exit; C++
  dispatcher loop in `recExecute` (pc→block→`_cpuEventTest_Shared`); per-opcode
  interpreter fallback via `intExecuteOneInst`; `Cpu = &recCpu` on ARM64.
- [x] 4.4 Block linking + recLUT (replaces the bring-up `s_blocks` unordered_map +
  recompile-on-miss). **DONE & MERGED to `armjit` (commit `37787a50b`).** recLUT page
  table + emitted DispatcherReg/Event/JITCompile/Enter/Unmapped stubs + inline
  cycle/event tail; blocks chain in host code. The parked `armjit-reclut-wip` stall was
  the 4.5-invalidation × recLUT interaction: fixed with targeted `recClear` (per-range
  slot reset, not whole-cache `recResetRaw`) + a 1 MB cache-emit headroom (VIXL was
  realloc'ing the MAP_JIT buffer). See CURRENT FOCUS.
- [~] 4.5 Block invalidation on TLB-mapping change. RAM-code page marking landed
  earlier (`recProtectCompiledRange` → `mmap_MarkCountedRamPage`). On `armjit-reclut-v2`
  the coarse whole-cache reset is replaced by **recLUT-backed targeted invalidation**:
  `recClear(addr,size)` resets only the slots in range to `JITCompile`. Still TODO:
  overlap-aware invalidation (a block straddling into the cleared range from an earlier
  start slot is currently missed) and TLB-aware page identity.

---

## Phase 5 — EE Coprocessors

- [x] 5.1 COP0: **inline interpreter fallback** (commit `ffe4f18d1`). Straight-line COP0
  ops (`MFC0`/`MTC0` for Rd∉{9,25}, `TLBR/TLBWI/TLBWR/TLBP`) emit inline `recEmitInterpInline`
  instead of breaking the block. PC-writing (`BC0*`,`ERET`), cycle-sensitive (Count/PERF),
  and interrupt-gating (`EI/DI/WAIT`) ops stay single-stepped. Native COP0 codegen not
  needed (COP0 isn't a per-op perf item).
- [x] 5.2 COP1 (FPU) — single-precision suite compiled natively:
  - [x] 5.2a Bit-exact transfer/move/load-store: `MFC1/MTC1/CFC1/CTC1`,
    `MOV_S/ABS_S/NEG_S`, `LWC1/SWC1` (`aR5900FPU.cpp`). No EE float quirks → exact.
  - [x] 5.2b Float arithmetic — EE non-IEEE rounding (`fpuDouble` input clamp +
    checkOverflow/checkUnderflow result clamp + FCR31 flags). Mirrors the **interpreter**
    (single precision, FPU.cpp), not iFPUd. Shared helpers `emitLoadFpuDouble` /
    `emitClampFpuDoubleBits` / `emitStoreClampedResult` in `aR5900FPU.cpp`.
    - [x] `ADD_S/SUB_S/MUL_S` + ACC `ADDA_S/SUBA_S/MULA_S`.
    - [x] `DIV_S/SQRT_S/RSQRT_S` (+ `checkDivideByZero`; over/underflow with no flags).
    - [x] `MADD/MSUB(/A)_S`, `MAX_S/MIN_S`.
    - [x] `C.F/C.EQ/C.LT/C.LE` compares, `BC1T/BC1F` branches, `CVT.S/CVT.W`.
    - [ ] Remaining on interpreter fallback: double W/L-format, likely `BC1FL/BC1TL`.
- [x] 5.3 COP2 (VU0 macro): **inline interpreter fallback** (commit `0108025c9`). COP2
  ops (`0x12`) + `LQC2`/`SQC2` emit an inline `recEmitInterpInline` call instead of
  breaking the block; safe because ARM64 `CpuVU0` is the synchronous VU0 interpreter (no
  microVU sync needed). `BC2*` branches stay single-stepped. Native microVU emission =
  Phase 7.
- [x] 5.4 MMI (128-bit int SIMD): map to NEON where possible (ref `x86/iMMI.cpp`).
  **COMPLETE** — every MMI op compiles natively except QFSRV (runtime SA register →
  interpreter). All decode indices match `tbl_MMI*`; full gtest coverage (269 Arm64EmitEE).
  - [x] First batch (`aR5900MMI.cpp`, commit `6b2ceb311`): NEON-mapped ops —
    `PADD*/PSUB*` (+ signed/unsigned saturating), `PCGT*/PCEQ*`, `PMAX*/PMIN*`,
    `PABSW/PABSH`, `PAND/POR/PXOR/PNOR`, `PEXTL*/PEXTU*`, `PPAC*`,
    `PCPYLD/PCPYUD/PCPYH`. 47 byte-exact gtests vs MMI.cpp.
  - [x] Parallel immediate shifts (`PSLLH/W`, `PSRLH/W`, `PSRAH/W`) — NEON
    `Shl/Ushr/Sshr` with sa=0 fast-path (`Mov`). 18 gtests, all pass.
  - [x] Lane permutes (`PINTH/PINTEH/PEXEH/PEXEW/PREVH/PROT3W/PEXCH/PEXCW`) — NEON
    `Ins` (lane insert), `Rev64` (PREVH). 8 gtests, all pass.
  - [x] Variable shifts (`PSLLVW/PSRLVW/PSRAVW` — amount from GPR[rs], 5-bit masked
    per lane). Scalar GPR shifts (`Lsl`/`Lsr`/`Asr`), 2 lanes per 64-bit store.
    3 gtests, all pass.
  - [x] Multiply-accumulate to HI/LO (`PMADD*/PMSUB*/PMULT*/PHMADH/PHMSBH` + the
    `PMFHI/PMFLO/PMTHI/PMTLO` moves). Word ops use scalar `Smull/Umull` + the EE
    division voodoo (positive 0xFFFFFFFF divisor); halfword ops do 8 lanes to
    LO/HI.UL[0..3]. gtests seed nonzero HI/LO to exercise the accumulate path.
  - [x] Misc (`PADSBH`, `PEXT5/PPAC5`, `PLZCW` [ARM64 `Cls`], `PMFHL` [LW/UW/SLW/LH/SH],
    `PMTHL`). `QFSRV` stays on the interpreter (shift amount = runtime SA register).

---

## Phase 6 — IOP Recompiler (R3000A)

- [x] 6.1 Create `pcsx2/arm64/aR3000A.{h,cpp}`.
- [x] 6.2 Implement `psxRec` interface (Reserve/Reset/ExecuteBlock/Clear/Shutdown) —
  C++ dispatcher loop + recLUT + per-block prologue/epilogue; all ops interpreter
  single-stepped (`iopExecuteOneInst`) for now. Correct, not yet fast.
- [x] 6.3 Port integer / load-store / branch / coprocessor generators (simpler than EE).
  - [x] Integer: ADDI/ADDIU/SLTI/SLTIU/ANDI/ORI/XORI/LUI, ADD/ADDU/SUB/SUBU/AND/OR/
    XOR/NOR/SLT/SLTU, SLL/SRL/SRA/SLLV/SRLV/SRAV, MFHI/MTHI/MFLO/MTLO,
    MULT/MULTU/DIV/DIVU (commit `86448e99c`). 32-bit; mirrors the gtested EE generators.
  - [x] Load/store (via iopMemRead/Write8/16/32 slow path — no vtlb fastmem on IOP).
    Aligned LB/LBU/LH/LHU/LW + SB/SH/SW (`f104adb25`); unaligned LWL/LWR/SWL/SWR
    (`3efc4c40c`, runtime shift+mask, recompute-after-call, no spill).
  - [x] Branches/jumps (J/JAL/JR/JALR, BEQ/BNE/BLEZ/BGTZ + REGIMM) — `13daf73d0`.
    Native generators + delay-slot compile in the block compiler; J-with-IRX-magic and
    branch-in-delay-slot bail to the interpreter. No likely branches on MIPS-I.
  - [x] Coprocessor (COP0 MFC0/CFC0/MTC0/CTC0/RFE; COP2/GTE + LWC2/SWC2) — `9095d983b`,
    inline-interp (EE-style, keeps block intact). RFE also emits iopTestIntc. No COP0/COP2
    branches on the IOP. **Phase 6.3 complete** (only SYSCALL/BREAK single-step).
- [x] 6.4 Wire into `VMManager.cpp` (reserve/shutdown/reset + `psxCpu` selection on ARM64).

**Milestone after Phase 6:** playable 2D games expected.

---

## Phase 7 — VU Recompilers (microVU)

> Strategy: **parallel clone** in `pcsx2/arm64/` — never touch `pcsx2/x86/microVU*` (hard rule #1).
> Copy the arch-neutral structs + analysis pass; rewrite all emission in VIXL. microVU stays
> *unselected* (interpreter live) until 7.6 — it's a program-level rec, so it can't single-step
> like the IOP skeleton could. VF→NEON `v0-v31`, VI→ARM `w`-regs, Q/P latency in one NEON reg.
> The full buildable sub-task order:

- [x] 7.1 Study `x86/microVU*.cpp/h` + `microVU_*.inl` — done (see CURRENT FOCUS +
  [[arm64-microvu-architecture]]). Mapped arch-neutral vs arch-specific; understood program/block
  model, the 96-byte `microRegInfo` state key, dispatcher entry contract, flag-instance pipeline.
- [~] 7.2 **Skeleton & infrastructure** (builds + links; NOT yet selected in VMManager):
  - [x] 7.2a `pcsx2/arm64/aVU.h` — ported the arch-neutral structs (`microRegInfo`, `microBlock`,
    `microJumpCache`, `microTempRegInfo`, `microVFreg/microVIreg`, `microConstInfo`,
    `microUpperOp/microLowerOp`, `microFlagInst/Cycles`, `microOp`, `microIR`,
    `microProgram(Manager/Quick/List)`, `microBlockManager`, `microVU`). Renamed
    `x86ptr/x86start/x86end` → `codePtr/codeStart/codeEnd`; dropped `x86emitter.h`.
    `microRegAlloc` forward-declared (7.2b). Verified via a minimal `aVU.cpp` TU: builds arm64,
    `sizeof(microRegInfo)==96` static_assert passes, unittests 2/2.
  - [x] 7.2b Port `microRegAlloc` (`microVU_IR.h` 226–1139) to ARM64 in `pcsx2/arm64/aVU_IR.h`
    — NEON `v0`–`v23` for VF, ARM `w`-regs for VI, base+offset addressing vs `RVUSTATE=x19`.
    Mirrors `allocReg`/`allocGPR`/`writeBackReg`/`clearNeeded`/`flushAll`/`clearReg`/`clearGPR`
    + the NEON emit helpers (`mVUloadReg`/`mVUsaveReg`/`mVUmergeRegs`/`loadIreg`). COP2/macro path
    dropped (Phase 7.9). All VF pool regs treated caller-saved (AAPCS64 only keeps v8–v15 low 64).
    Compile-exercised via `mVUallocCompileCheck` in aVU.cpp. Builds arm64; unittests 2/2.
  - [x] 7.2c `pcsx2/arm64/aVU.cpp` — mirror `microVU.cpp` (mVUinit/reset/close/clear, program
    cache mgmt, `mVUsearchProg`, `recMicroVU0/1::*` methods) + define the `microVU0/1` /
    `CpuMicroVU0/1` globals + real `vuJITFreeze`. Codegen/compile layer (dispatcher,
    block-fetch) `pxFailRel`-stubbed for 7.2d/later. Builds arm64; unittests 2/2. (`532adca92`)
  - [x] 7.2d Dispatcher — ported `mVUdispatcherAB/CD` + `mVUGenerateWaitMTVU/CopyPipelineState/
    CompareState` + `mVUexecute`/`mVUcleanUp` to VIXL (`microVU_Execute.inl` 23–315). AAPCS64
    frame via `armBeginStackFrame(true)`; loads VU FPCR (`msr FPCR`), builds the PQ NEON reg
    (v24) with the x86 lane layout, copies mac/clip flags, loads status GPRs (gprF0-3=w23-w26),
    `br x0` into the block; exit restores EE FPCR + `mVUcleanUp` cycle accounting. `mVUreset`
    now does the real emitter setup (`armSetAsmPtr(mVU.cache)` + one start/end block) and sets
    `codeStart`/`codePtr` past the dispatchers. Unselected ⇒ compiled but not executed yet.
    Builds arm64; unittests 2/2. (`a0d93ed5c`)
- [x] 7.3 **Analysis pass** (arch-neutral, near-verbatim copy) — `microVU_Analyze.inl` +
  the pipeline/flag analysis helpers in `microVU_Compile.inl`. Operates on `microOp`/`microIR`;
  no emitter calls, so it ported almost unchanged. (`microVU_Tables.inl` moved to 7.5.)
  - [x] `microVU_Analyze.inl` → `pcsx2/arm64/aVU_Analyze.inl` (pass-1 analysis) + the arch-neutral
    macro layer `pcsx2/arm64/aVU_Misc.h`. Compile-exercised via `mVUanalyzeCompileCheck`. Builds
    arm64; unittests 2/2. (`863de3e77`)
  - [x] Pipeline/cycle/flag-analysis helpers from `microVU_Compile.inl` (`mVUsetupRange`/
    `mVUincCycles`/`mVUsetCycles`/`mVUoptimizePipeState`/`eBitPass1`/`branchWarning`/`eBitWarning`/
    `mVUcheckBadOp` + `optimizeReg`/`calcCycles`/`tCycles`/`incP`/`incQ`/`cmpVFregs`/`mVUcheckIsSame`)
    → `pcsx2/arm64/aVU.cpp`. Arch-neutral; compile-exercised via `mVUcompileHelpersCheck`. Builds
    arm64; unittests 2/2. (`30ee0b64b`)
  - [ ] `microVU_Tables.inl` — MOVED to 7.5 (the dispatch tables reference the per-op emit
    handlers, which don't exist until the VIXL emission task).
- [~] 7.4 **Compile driver** — port `microVU_Compile.inl` (`mVUcompile`/`mVUblockFetch`/block
  search+link/`mVUsetupRange`). Interleaves 7.3 analysis with emit; ends blocks on E-bit/branch.
  - [x] First-pass init helpers (emitter-free): `startLoop`/`mVUinitConstValues`/`mVUinitFirstPass`
    → `pcsx2/arm64/aVU.cpp`. memset/memcpy + block-manager `add` only (no VIXL); `x86ptrStart`→
    `codeStart`. Compile-exercised via `mVUcompileHelpersCheck`. Builds arm64; unittests 2/2. (`9b01b4ca2`)
  - [x] Pass-2 flag allocators (first emit-backend slice) — flag-allocator half of `microVU_Alloc.inl`
    → `pcsx2/arm64/aVU_Alloc.inl`: `getFlagReg` + Status/Mac/Clip normalize/denormalize
    (`setBitSFLAG`/`setBitFSEQ`/`mVUallocSFLAGa`–`d`/`mVUallocMFLAGa`–`b`/`mVUallocCFLAGa`–`b`).
    Established the emit-layer reg-name macros (`gprT1`/`gprT2`/`gprF0`–`gprF3`) in `aVU_IR.h`.
    x86 GPRs→w-regs; `xTEST+JZ+xOR`→`Tst+B(eq)+Orr`; absolute `ptr16/ptr32`→`armMoveAddressToReg`+
    `Ldrh/Ldr/Str`. Compile-exercised via `mVUallocFlagCheck`. Builds arm64; unittests 2/2.
    (`8d312b4ce`)
  - [x] Pass-2 P/Q allocators (part 1b) — `getPreg`/`getQreg`/`writeQreg` → `aVU_Alloc.inl` + the
    NEON lane-broadcast `mVUunpack_xyzw` → `aVU_IR.h`. x86 `xPSHUF.D` splat → VIXL `Dup` (index ==
    case); `xINSERTPS`/`xMOVSS` into Q → `Ins` lane0. PQ pair in `mVU_xmmPQ` (v24), x86 layout.
    Compile-exercised via `mVUallocFlagCheck`. Builds arm64; unittests 2/2. (`f47f00c3e`)
  - [x] Clamp helpers (`microVU_Clamp.inl` → `aVU_Clamp.inl`): `mVUclamp1`–`4` + the `mVU_Globals`/
    `mVUglob` emit-constant table back into `aVU_Misc.h`. Range clamp → `Fminnm`/`Fmaxnm`; sign clamp
    → `Smin`/`Umin`. Compile-exercised via `mVUclampCheck`. arm64; unittests 2/2. (`95e3011ca`)
  - [x] Misc emit helper (`microVU_Misc.inl` → `aVU_Misc.inl`): `mVUaddrFix` VU address transform
    (VU0/VU1 wrap + VU0→VU1 window remap + waitMTVU). Compile-exercised via `mVUmiscCheck`. arm64;
    unittests 2/2. (`c8c6f31ea`) Deferred: `mVUoptimizeConstantAddr` (→ 7.5b), SSE arith (→ 7.5a).
  - [x] Emit-coupled driver `mVUcompile` + `mVUexecuteInstruction`/`doUpperOp`/`doLowerOp`/`doSwapOp`/
    `doIbit`, `mVUtestCycles`, `mVUDoDBit`/`mVUDoTBit`, `mvuPreloadRegisters`, and the real
    `mVUentryGet`/`mVUblockFetch`/`mVUcompileJIT` entry points (replaced the `pxFailRel` stubs).
    `aVU_Compile.inl` + `aVU_Tables.inl` + flag read-scan + branch drivers — the Tables/Compile
    big-bang (`37b43dae6`/`360eea8d6`/`c0135eab3`/`04be7bfc0`). Per-block session owned by the outer
    entries (`mVUexecute`/`mVUcompileJIT`); icache flushed via `armEndBlock`. Builds; unittests 2/2.
- [x] 7.5 **VIXL emission for the VU ISA:** (both halves done — Upper 7.5a, Lower 7.5b)
  - [x] 7.5a Upper (FMAC float vector → NEON): DONE (`aVU_Upper.inl`, commits `4875c456f`
    SSE helpers / `1b6544305` handlers). Full Upper ISA — ADD/SUB/MUL/MADD/MSUB (+ACC, +i/q/
    x/y/z/w), MAX/MINI, FTOI/ITOF, ABS, OPMULA/OPMSUB, CLIP, NOP + `mVUupdateFlags`. The custom
    SSE arith primitives (MIN_MAX_PS/SS, ADD_SS_TriAceHack, SSE_ADD/SUB/MUL/DIV/MAX/MIN(PS|SS),
    ADD2) landed in `aVU_Misc.inl`. Tables wired (`mVU_UPPER_OPCODE` + FD_00/01/10/11).
  - [x] 7.5b Lower (`aVU_Lower.inl`, `ddd15c67a`) — VI ALU (IADD/ISUB/IADDI/IADDIU/IAND/IOR/ISUBIU),
    load/store (LQ/SQ/ILW/ISW/LQI/SQI/LQD/SQD/ILWR/ISWR), EFU (DIV/SQRT/RSQRT + EATAN*/EEXP/ELENG/
    ERCPR/ERLENG/ERSADD/ERSQRT/ESADD/ESIN/ESQRT/ESUM + WAITQ/WAITP), MOVE/MFIR/MTIR/MR32/MFP, RANDOM
    (RINIT/RGET/RNEXT/RXOR), FSAND/FSEQ/FSOR/FSSET/FMAND/FMEQ/FMOR/FCxxx, XTOP/XITOP, real XGKICK,
    B/BAL/IBxx/JR/JALR (+ setBranchA/condEvilBranch/normJumpPass2). `mVUoptimizeConstantAddr`→
    `aVU_Misc.inl`. Full LOWER/LowerOP/T3_xx tables wired. arm64; unittests 2/2. Stays unselected.
- [x] 7.6 **Flags** — `microVU_Flags.inl` fully ported (`aVU_Flags.inl`). Analysis + emit
  (`ce947bbc0`): `findFlagInst`/`sortFlag`/`sortFullFlag`/`mVUstatusFlagOp`/`mVUsetFlags` +
  `mVUdivSet`/`mVUsetupFlags`. Read-scan (`360eea8d6`): `_mVUflagPass`/`mVUflagPass`/`mVUsetFlagInfo`
  + `shortBranch` (drive `mVUopU`/`mVUopL` pass4).
- [x] 7.7 **Branches** — `microVU_Branch.inl` fully ported. **Program-exit emitters**
  (`dabfe47e5`+`73616dccf`): `getLastFlagInst`/`mVUendProgram`/`mVUDTendProgram`/`mVUsetupBranch`
  + E/T-bit & lpState C thunks. **Branch drivers** (`04be7bfc0`): `normBranchCompile`/
  `normJumpCompile`/`normBranch`/`normJump`/`condBranch`. **Op handlers** (`ddd15c67a`, in
  `aVU_Lower.inl`): B/BAL + the conditional IBEQ/IBGEZ/IBGTZ/IBLEZ/IBLTZ/IBNE + JR/JALR +
  badBranch/evilBranch (`condEvilBranch`/`normJumpPass2`). The no-op XGKICK stubs were replaced by
  the real GIF-transfer path (now in Lower). condBranch's branch-value compare sign-extends
  (`mvuLdrsh16`) to match x86's 16-bit signed `xCMP(ptr16…)` for the IBLTZ-family conditions.
- [x] 7.8 **Wire selection + validate** — microVU0/1 selected on ARM64; two real-execution bugs
  found and fixed; BIOS + 2D + VU1-heavy 3D all boot & run.
  - [x] Selection wired (`dcbdec813`): all four ARM64 `#else` branches mirror x86; MTVU thread
    managed via recMicroVU1::Reserve/Shutdown (no manual vu1Thread.Open workaround).
  - [x] Bug #1 fixed (`7fb86fcfa`): `REC_VU1`/`THREAD_VU1` track `EmuConfig` (was hardcoded false) —
    XGKICK packet-size bit31/EOP misread → ~2 GB memcpy crash on first kick.
  - [x] Bug #2 fixed (`b7ae2fa7b`): `compareState` is C++ `memcmp`, not executed JIT — fixes the
    W^X SIGBUS (executing non-executable MAP_JIT mid-compile) on both the CPU and MTVU threads.
  - [x] **No crashes** — BIOS, Odin Sphere (2D), Rayman 3 (2D), FFX (3D) all boot without crashing.
  - [x] Built `MVU_DIFF` shadow differential + per-instruction localizer + DIV/FMAC/writeback dumps
    (`fb00e747b` + this session's debug tooling, all env-gated).
  - [x] **ROOT CAUSE ISOLATED: wrong MAC flag.** `FMAND` (pc=0240) reads a wrong MACflag → wrong VI →
    wrong branch → wrong vertex-loop count → reads garbage vertices → FMAC overflow to -FLT_MAX →
    malformed GIF packet → black screen + 17,509× "GS packet size exceeded" warnings. The FMAC math is
    correct given inputs; `mVUupdateFlags` is faithful to x86. See CURRENT FOCUS for the evidence.
  - [x] **FIXED (2026-06-07): not the MAC flag.** `mVUclamp1`/`mVUclamp2` used `xEmptyReg` as the
    constant-load scratch → aliased the value reg → operands collapsed to -FLT_MAX → poisoned MULq →
    wrong FMAC sign → wrong MAC flag (the visible symptom) → wrong branch → black screen. Fix: clamp
    helpers fall back to `RQSCRATCH` when `regT1.IsNone()`. BIOS verified (warnings 13903→1).
- [~] 7.9 **Macro mode** — port `microVU_Macro.inl` + the two COP2 analysis passes
  (`iR5900Analysis.cpp`) so the EE rec drives precise, analysis-driven EE↔VU0 sync
  (and eventually native COP2 emission) instead of the Phase 5.3 inline-interp blanket
  sync. Now a **correctness/timing** item (strict-timing games), not just perf polish.
  **Full plan: `arm64-port/MACRO_MODE_PLAN.md`** (phases M0–M6). Started 2026-06-18.
  - [x] **M0 scaffolding** (2026-06-18): M0.1 `cop2flags()` + `EEINST`/`g_pCurInstInfo` →
    new `pcsx2/arm64/aR5900Analysis.{h,cpp}`; M0.2 per-block `EEINST` inst-cache in
    `recRecompile` (`recScanBlockEnd` pre-scan, `s_instCache`, per-op `g_pCurInstInfo`,
    `s_eeEndBlock`); M0.3 non-syncing COP2 ALU entry identified
    (`Int_COP2SPECIAL1PrintTable[code&0x3f]`). No behavior change.
  - [x] **M1 COP2 analysis passes** (2026-06-18): faithful 1:1 port of both passes from
    `iR5900Analysis.cpp` into `aR5900Analysis.{h,cpp}` (`AnalysisPass`/`COP2FlagHackPass`/
    `COP2MicroFinishPass`), run in `recRecompile` after the M0.2 inst-cache build over
    `[startpc, s_eeEndBlock)` behind a `has_cop2` gate (COP2/LQC2/SQC2 present). Call order
    mirrors x86 (MicroFinish, then FlagHack under `vuFlagHack`). M1.1 FlagHack sets
    `EEINST_COP2_{DENORMALIZE,NORMALIZE}_STATUS_FLAG`/`STATUS`/`MAC`/`CLIP`; M1.2 MicroFinish
    sets `SYNC`/`FINISH`/`FLUSH_VU0_REGISTERS` (interlock pre-scan + LQC2/SQC2 finish-hoist +
    `block_interlocked`/`CHECK_FULLVU0SYNCHACK`); M1.3 env-gated dump `eeDumpCOP2AnnotatedBlock`
    (`EE_COP2_DUMP=1`). ⚠ no-offset inst-cache convention (vs x86's `+1`): passes called with
    base `s_instCache`; the SPECIAL2 look-ahead re-bases to `&inst_cache[(apc+4-start)>>2]`.
    Flags computed, **not consumed** (consumption starts M3) — no behavior change.
  - [x] **M2 sync/interlock emit helpers** (2026-06-18): faithful VIXL ports of
    `microVU_Macro.inl`'s `mVUFinishVU0`/`mVUSyncVU0(raw)`/`COP2_Interlock(mBitSync, raw)`
    in `aR5900.cpp` (after `recEmitFlushCycles`) + a per-block `static bool
    s_nBlockInterlocked` (reset in `recRecompile`). Memory-backed (no EE reg-alloc → no
    `iFlushCall`/`_freeX86reg`); x86 `rax`→`RXVIXLSCRATCH` (x16, dead before the
    `ExecuteBlockJIT(CpuVU0, interlocked)` args); cycle flush reuses `recScaleBlockCycles`;
    `Tbz(VPU_STAT,0,skip)` for the idle-tests; `xLoadFarAddr(arg1,CpuVU0)`→
    `armMoveAddressToReg(RXARG1, CpuVU0)` bakes the stable object pointer. Helpers are
    `[[maybe_unused]]` (M3 is the first caller) — present, **not consumed**, no behavior
    change. M3 prerequisite: set host-side `cpuRegs.code = op` at emit time (the x86
    `_Rt_`/`_Rd_` macros + `COP2_Interlock`'s `cpuRegs.code & 1` read it).
  - [~] **M3.1 recCFC2** (2026-06-18, code done — build pending user verify): first native
    COP2 transfer op + first consumer of the M2 helpers (`[[maybe_unused]]` dropped). Native,
    memory-backed in `aR5900.cpp`: `COP2_Interlock(false,0)` then the non-interlocked
    `SYNC_VU0→mVUSyncVU0(0)` / `FINISH_VU0→mVUFinishVU0` dispatch off the M1 flags, then
    per-`_Rd_` extend (`vi00→0`; `REG_I`/`REG_R`/`≥REG_STATUS_FLAG` → `Sxtw`, `REG_R` also
    `& 0x7FFFFF`; else `Ldrh` zero-extend) into `cpuRegs.GPR[rt].UD[0]`. Sync helpers get
    `raw=0` (the emit loop's `recOpNeedsCycleFlush`/`recEmitFlushCycles` already committed
    `cpuRegs.cycle`; their `if (raw!=0)` guard then skips the redundant commit but reads the
    current cycle). `recTranslateOp` `case 0x12` now switches on `rs` (0x02→`cpuRegs.code=op;
    recCFC2()`; 0x08→single-step; else inline-interp). Removed CFC2 from the inline-interp
    path; rewrote the stale "CpuVU0 is the synchronous VU0 interpreter" comment.
  - [~] **M3.2 recCTC2 + M3.3 recQMFC2/recQMTC2** (2026-06-18, code done — build pending):
    the rest of the COP2 transfer-register ops, native + memory-backed. **CTC2**: read-only/
    `REG_R`/`REG_STATUS_FLAG`/`REG_CMSAR1`/`REG_FBRST`/vi00/default switch; REG_STATUS inlines
    `mVUallocSFLAGd`'s denormalize bit-math (copied from `aVU_Alloc.inl`, microVU TU) + `Dup`
    broadcast into `VU0.micro_statusflags`; REG_CMSAR1 → `vu1Finish`/`vu1ExecMicro`; REG_FBRST
    reloads GPR[rt] from memory per `TEST_FBRST_RESET` → `vu0/1ResetRegs` (no callee-saved pin);
    default VI 1-15 → 16-bit `Strh`, VI≥16 (incl. REG_I) → 32-bit `Str`. **QMFC2/QMTC2**:
    128-bit `Ldr`/`Str RQSCRATCH` between `VU0.VF[rd]` ↔ `cpuRegs.GPR[rt]` (QMFC2 rt==0 / QMTC2
    vf00 early-outs; QMTC2 rt==0 → `Movi` zero). `recTranslateOp` `case 0x12` now switches rs
    (0x01 QMFC2 / 0x02 CFC2 / 0x05 QMTC2 / 0x06 CTC2 / 0x08 single-step / default inline-interp);
    **only the SPECIAL ALU macro ops remain on inline-interp** (until M5). Faithful to
    microVU_Macro.inl (not the interpreter).
  - [~] **M3.4 recLQC2/recSQC2** (2026-06-19, code done — build pending user verify): the last COP2
    transfer pair (quad load/store). Flag-driven `mVUSyncVU0(0)`/`mVUFinishVU0` off
    `g_pCurInstInfo->info`, **no `COP2_Interlock`** (faithful to microVU_Macro.inl recLQC2/recSQC2),
    `armEmitEffectiveAddr` + `& ~0xF` then the non-cached vtlb quad path
    (`armEmitVtlbReadQuad`/`WriteQuad`) targeting `&VU0.VF[_Rt_]`. `OP_LQC2`/`OP_SQC2` added to
    `recOpNeedsCycleFlush`; removed from inline-interp. **Phase M3 complete.** (Plus the 2026-06-19
    cycle-accounting fix: dropped the unconditional pre-flush; cycles now commit inside the M2 sync
    helpers on a real SYNC via `s_cop2RawCycles`, faithful to x86 — see JOURNAL.)
  - [~] **M4 recBC2F/T/FL/TL** (2026-06-19, code done — build pending user verify): the COP2 branches,
    emitted natively through the existing EE branch machinery (no longer single-stepped). `armEmitBC2F`/
    `armEmitBC2T` in `aR5900Branch.cpp` (mirror `armEmitBC1F/T`: test `VU0.VI[REG_VPU_STAT].UL & 0x100`,
    `eq`=branch-when-clear for F, `ne`=branch-when-set for T) + the likely forms BC2FL/BC2TL added to
    `armEmitBranchLikelyTest` (rt 0x02/0x03 → eq/ne, native delay-slot nullification — mirrors BC1FL/
    BC1TL; the PROGRESS-4.2 "likely branches fall back to interp" note is stale, they're native now).
    Wired into `recEmitBranch` / `recIsHandledBranch` / `recIsLikelyBranch` (`case 0x12`, rs==0x08).
    **Faithful to x86 `_setupBranchTest`: NO VU sync / interlock / cycle commit** (a plain bit-test
    branch — unlike the M3 transfer ops); TrySwapDelaySlot not ported (the EE rec has no delay-slot
    swap; a straight branch+delay-slot compile is faithful enough). `recTranslateOp` `case 0x12`
    rs==0x08 is now an unreachable defensive fallback (recRecompile ends the block at the branch).

---

## Phase 8 — Integration, Testing & Polish

- [ ] 8.1 Remove the ARM64 "UNSUPPORTED CONFIGURATION" warning (`CMakeLists.txt:84-93`).
- [ ] 8.2 Real `SaveStateBase::vuJITFreeze()` (replace the empty-byte hack in `RecStubs.cpp`).
- [ ] 8.3 Full unit-test suite green on ARM64.
- [ ] 8.4 Game-compat matrix: 2D first, then 3D.
- [~] 8.5 Profile + optimize hot paths.
  - [x] **FMV lag fixed** (`dev/fmv`). Profiled Rayman 3's FMV: not MPEG math (IPU/IDCT/yuv2rgb
    negligible) but an EE **recompile storm** — `recRecompile` was 22% of the EE thread. The ARM64 EE
    rec only had x86's tier-1 SMC protection (write-protect → fault → clear → recompile → reprotect,
    ping-ponging forever), amplified 4× by Apple Silicon's 16 KB host pages where IPU/EE-streamed video
    frames share pages with code. Ported x86's full Write/**Manual-checksum**/counted-give-up scheme to
    `aR5900.cpp` (`recEmitManualProtection` + `DispatchBlockDiscard`/`DispatchPageReset` stubs +
    `manual_page`/`manual_counter`) and a single-host-page block invariant. User-confirmed fixed.
    See JOURNAL + [[arm64-fmv-smc-recompile-storm]].
- [ ] 8.6 Re-enable LTO for ARM64 if stable.
- [ ] 8.7 macOS specifics (entitlements, Metal shader compile, MoltenVK).

---

## Test ladder (use to validate each milestone)

1. `unittests` target stays green.
2. PS2 BIOS boots (no disc) — fewer complex ops than games.
3. Simple 2D game (e.g. Gradius III/IV).
4. IOP-heavy title (e.g. a PS1-mode game) — exercises IOP rec.
5. 3D game (e.g. Final Fantasy X) — heavy EE + VU.
