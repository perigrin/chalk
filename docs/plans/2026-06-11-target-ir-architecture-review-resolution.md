# Target/IR Architecture Review — Resolution

**Date:** 2026-06-11
**Status:** DECIDED (perigrin). This closes the review opened 2026-06-08
(memory: architecture_review_needed_target_layer; findings doc:
`paad/architecture-reviews/2026-06-08-target-ir-layer-review.md`).

## Finding dispositions

1. **Node taxonomy (Finding 1)** — RESOLVED BY EXECUTION. The R1–R3
   reconciliation (`docs/plans/2026-06-08-ir-taxonomy-reconciliation.md`,
   COMPLETE 2026-06-10) deleted the 18 parallel G4/G5 nodes and converged
   the LLVM backend onto the canonical vocabulary. Verified by the
   whole-branch review
   (`paad/code-reviews/phase1-lateral-bindings-2026-06-10-17-37-49-256a9b37-branch-agentic.md`).

2. **Target namespace (Finding 2)** — DECIDED 2026-06-08, NARROW MOVE
   EXECUTED (R1): `Chalk::Target` is the base, `Chalk::Target::LLVM` lives
   there; `Chalk::Bootstrap::Target` is a compat alias. The full
   ~153-consumer Bootstrap-target migration is filed (zhi `019eb316`,
   rename-tied).

3. **LLVM deferral (Finding 3)** — WAS NEVER DRIFT. LLVM-first was decided
   and documented 2026-06-06
   (`docs/plans/2026-06-06-three-axis-codegen-and-typed-ir-contract.md`):
   IR→LLVM is the self-sufficiency forcing function NOW; IR→C/XS is the
   practicality axis, deferred near-capstone. Stale doc text corrected
   2026-06-10 (ir-lowering.md, runtime-free-boundary.md).

## Application to the MOP-migration chain gate (re-audit §5 caveat)

**LLVM-first HOLDS.** Consequence for the punch-list chain
(zhi `019eb420`/`019eb421-*`):

- **1/4 (Target::C entry-point migration) parks near-capstone** with the
  rest of the C/XS axis. It remains the structural head of the 2→3→4 chain
  (cfg_state/legacy-path/body-dual-write deletions all require Target::C
  off the backchannel first), so the chain's *deletion* items inherit the
  near-capstone timing. No re-sequencing of 2/4–3/4 around LLVM is
  possible: their blockers are Target::C consumers, not LLVM ones.

## The structs decision (Phase 6 vs R3 tension) — DECIDED 2026-06-11

**Decision (perigrin): the metadata structs still delete eventually; the
LLVM backend should read the MOP directly.** R3's ClassInfo consumption
(`_populate_registry_from_classinfo`; `MethodInfo.body_node`/`return_repr`)
is formally **TRANSITIONAL** — a bridge, not the end-state read surface.
Rationale: ONE post-parse representation (the MOP). Retaining the Info
structs as a permanent parallel read surface would recreate, at the
class-structure layer, the two-vocabularies failure mode the R1–R3
reconciliation just eliminated at the node layer.

The review's counter-option (keep the structs as a formally-retained
immutable read surface) was considered and declined.

### Consequences (named now, designed in the new issue)

1. **A new migration phase exists**: teach `Chalk::Target::LLVM` to build
   its class registry from `MOP::Class`/`MOP::Method`/`MOP::Field`/
   `MOP::Phaser::Adjust` directly (the Perl target already proves
   MOP-driven emission). Filed as its own issue; **4/4 (struct deletion)
   is blocked by it** in addition to 3/4.
2. **The node-input protocol question must be solved in that design.** R3
   chose `ClassInfo` partly because the immutable structs carry the
   node-input protocol (`id()` for hash-cons keys, no-op `add_consumer`)
   that lets class structure ride as a `Call(new)` input. `MOP::Class` has
   neither. The MOP-direct design must either (a) give the MOP
   metaobjects the protocol (content-based `id()`, no-op `add_consumer`),
   or (b) move class structure off the node-input channel entirely (e.g.,
   a registry handed to the backend alongside the graph, as
   `lower_with_elaboration` already does for `class_registry`).
3. **The corpus contract shape is transitional too**: `classes.md`/
   `host.md` ir-blocks build `ClassInfo(...)`/`MethodInfo(...)` as the
   parser-spec shape. When the LLVM backend goes MOP-direct, the corpus
   builder and the ir-block vocabulary follow (likely constructing
   `MOP::Class` via `declare_*` in the harness), and the corpus
   dual-contract docs amend with it.
4. **Doc annotations**: mop.md's "LLVM consumes ClassInfo" section and
   sea-of-nodes-ir.md's MOP-lowering section gain TRANSITIONAL notes
   (applied with this resolution). CLAUDE.md's Phase-6 caution updates
   from "reconcile before deleting" to the decided sequencing.

## Net state after this resolution

The 2026-06-08 architecture-review pause is fully discharged. Open work is
all issue-tracked: the Bootstrap-target migration (`019eb316`), the
MOP-migration chain (`019eb420`/`019eb421-*`, head parked near-capstone),
the new LLVM-reads-MOP-directly issue (blocking 4/4), the pre-B::SoN
cache/identity family (`019eb316`), and the G6/G7 feature tails
(`019eb073`/`019eb0d7`).
