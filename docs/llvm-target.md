# LLVM IR Target (Planned)

> **Status:** Deferred. Waiting on the C/XS backend to prove the Sea-of-Nodes
> IR is complete enough to drive a full compiler backend.

## Rationale

Chalk targets a Sea-of-Nodes IR that is intended to be a complete representation
of the program — sufficient to drive not just source-to-source translation but
also native code generation. An LLVM IR target is the natural endgame: it would
let Chalk emit native machine code for any LLVM-supported architecture without
writing per-target backends.

The LLVM target is deferred intentionally. A full native-code backend stresses
the IR in ways that source-level backends do not: it surfaces missing
annotations, under-specified control flow, and SSA-construction gaps that a
Perl-to-Perl round-trip will never reveal. The C and XS targets are the
stepping stone. They are close enough to native code that the IR has to carry
the right information (explicit control flow, type annotations sufficient for
struct layout, deterministic scheduling) but far enough from LLVM that they
exercise the IR through a different lowering path.

Once the C and XS targets are both producing correct, performant output across
the full Chalk corpus, the IR is proven complete, and LLVM IR lowering becomes
a straightforward engineering task rather than a design exploration.

## Gating Criteria

LLVM IR target work may begin when all of the following hold:

- The C target produces correct, behavioral-equivalent output for the full
  self-hosting corpus.
- The XS target produces correct, behavioral-equivalent output for the full
  self-hosting corpus.
- `Chalk::IR::Graph` construction is complete (full SSA with Phi insertion,
  dominator analysis, data-flow rewriting) — see
  [`plans/2026-04-04-son-ir-polymorphic-migration.md`](plans/2026-04-04-son-ir-polymorphic-migration.md).
- The optimization layer described in [`architecture/ir-lowering.md`](architecture/ir-lowering.md)
  is producing measurable wins through the existing targets.

## Scope (Provisional)

The LLVM target will emit LLVM IR text or bitcode consumable by `llc` or `clang`.
Detailed design is out of scope until the gating criteria are met; premature
design would hard-code assumptions about the IR that the C/XS work may still
invalidate.
