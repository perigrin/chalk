# LLVM IR Target

> **Status:** Active. The LLVM target is the IR-stressing native backend, driven
> by the runtime-free-boundary corpus. It is implemented at
> `lib/Chalk/IR/Target/LLVM.pm` and validated by `t/bootstrap/corpus/*` (lli
> output compared to perl as the sole oracle).

## Rationale

Chalk targets a Sea-of-Nodes IR that is intended to be a complete representation
of the program — sufficient to drive not just source-to-source translation but
also native code generation. A native-code backend stresses the IR in ways that
source-level backends do not: it surfaces missing annotations, under-specified
control flow, and SSA-construction gaps that a Perl-to-Perl round-trip will never
reveal.

**Sequencing decision (2026-06-06): LLVM first, not C/XS first.** This is recorded
in [`plans/2026-06-06-three-axis-codegen-and-typed-ir-contract.md`](plans/2026-06-06-three-axis-codegen-and-typed-ir-contract.md)
(the THREE-AXIS model: IR→Perl = expressiveness, IR→LLVM = **self-sufficiency, the
forcing function**, IR→C/XS = practicality, deferred). An earlier draft of THIS doc
(preserved in History below) made C/XS the prerequisite "stepping stone" and
deferred LLVM until C/XS proved the IR; that sequencing was superseded by the
three-axis plan. Per that plan's "Why LLVM IR specifically (not C/XS, not native
asm)" section: **`lli` interprets the emitted IR directly — no compile, no link, no
XS — while C/XS "drags in Perl-embedding complexity (XS, SV marshalling) orthogonal
to 'is the IR correct / self-sufficient.'"** LLVM-first gets the IR-stressing native
backend (the doc's stated reason for wanting one) without the C/XS toolchain build
(no `Build.PL`, `.so` linking, CPAN/cc). The C/XS axis is kept as the practicality
artifact, rebuilt later on the types the LLVM axis forces into the IR — "we do not
invest in un-welding the existing C path." The LLVM target's only external
dependency is `lli` (`/usr/lib/llvm-15/bin/lli`).

This is the path the **runtime-free-boundary campaign** takes (see
[`architecture/runtime-free-boundary.md`](architecture/runtime-free-boundary.md)):
each in-subset value type / dispatch form is lowered to libperl-free LLVM IR and
validated `lli == perl` over a constructive corpus. That campaign is precisely the
"stress the IR with a native backend" exercise this doc always wanted — done
through LLVM directly instead of via C/XS.

## Validation model

- **perl is the sole oracle.** Emitted `.ll` is run through `lli`; its output is
  compared to perl's. Never self-comparison.
- **No libperl.** The emitted `.ll` links no Perl C-API: no `Perl_`, `SV`, `sv_`,
  `AV`, `HV` symbols. A value/operation that cannot be lowered without libperl is a
  GAP (work-list), not a fallback. This is the runtime-free boundary.
- **Constructive corpus.** The hand-authored IR blocks in `t/corpus/mdtest/*.md`
  are both the lowering spec and the contract the future parser must emit (the IR
  producer for some idioms — e.g. regex — does not exist yet, so the hand-authored
  graph stands in for it).

## Relationship to C / XS targets

The C and XS targets (`lib/Chalk/Bootstrap/Perl/Target/C.pm`, the `BNF/Target/*`
targets) still exist and are documented in
[`architecture/ir-lowering.md`](architecture/ir-lowering.md). They are no longer a
*prerequisite* for LLVM; LLVM and the source/native targets exercise the IR
through different lowering paths and can proceed independently. (If/when native
object-code emission beyond `lli` is wanted, `llc`/`clang` over the same emitted IR
is the path — no per-architecture backend needed.)

## History (superseded sequencing)

The original plan deferred LLVM behind C/XS with these gating criteria (kept for
the record; **no longer in force**):

> LLVM IR target work may begin when all of the following hold:
> - The C target produces correct output for the full self-hosting corpus.
> - The XS target produces correct output for the full self-hosting corpus.
> - `Chalk::IR::Graph` construction is complete (full SSA with Phi insertion,
>   dominator analysis, data-flow rewriting).
> - The optimization layer is producing measurable wins through the existing
>   targets.

The LLVM-first decision replaced this: LLVM achieves the IR-completeness proof
those criteria were meant to gate, without requiring the C/XS toolchain build.
