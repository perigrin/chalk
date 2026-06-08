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

**Sequencing decision (perigrin, 2026-06): LLVM first, not C/XS first.** An
earlier draft of this doc (preserved in the History section below) made the C and
XS targets the prerequisite "stepping stone" and deferred LLVM until C/XS proved
the IR across the full corpus. That sequencing was superseded. **LLVM-first solves
everything the C/XS stepping-stone solved *for this problem* — exercising the IR
through a real native lowering path, proving runtime-free lowerability without
libperl — without bringing the entire C/XS toolchain build into scope** (no XS
compilation, no `Build.PL`, no `.so` linking, no CPAN/cc toolchain). The LLVM
target emits `.ll` text and runs it through `lli`; the only external dependency is
the LLVM interpreter. This makes the native-backend IR-stressing available now, at
a fraction of the build-infrastructure cost.

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
