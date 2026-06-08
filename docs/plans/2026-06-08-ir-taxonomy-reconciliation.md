# Target-Layer Reconciliation: single IR vocabulary + a common `Chalk::Target` home

**Date:** 2026-06-08
**Status:** PLAN — awaiting perigrin's approval before execution
**Author:** drafted from two alignment audits (aggregate-nodes audit + MOP-nodes audit)
run against commits `3435b75a..5f6a9f63` (the G2–G5 runtime-free GAP-clearing campaign).

**Scope:** this plan covers two of the three target-layer architecture-review
findings:
- **Finding 1 (node taxonomy)** — converge the ~18 parallel G4/G5 nodes onto the
  single canonical IR (Parts below: Problem → Phases 0–6).
- **Finding 2 (target namespace)** — move the codegen targets into a common
  top-level `Chalk::Target::*` (see the "Target namespace consolidation" section at
  the end).
- Finding 3 (LLVM-first sequencing) is RESOLVED — it was a documented decision
  (`docs/plans/2026-06-06-three-axis-codegen-and-typed-ir-contract.md`), not drift;
  `docs/llvm-target.md` has been updated to cite it. Not covered here.
- Note: `Chalk::IR::Node::Coerce` is NOT drift — it resolves
  `typed-ir-representation.md`'s own open questions (a node, parameterized by
  from/to) exactly as that doc planned. Out of scope; it is the model done right.

## Problem

The G4 (Array/Hash) and G5 (feature-class MOP) campaign work introduced ~18 new IR
node types, each chosen locally by a per-issue subagent against its corpus cases
rather than against the documented node taxonomy
(`docs/architecture/sea-of-nodes-ir.md`, `mop.md`, `typed-ir-representation.md`).
The result is a **second, parallel IR vocabulary** that:

- is **parser-unreachable** (no `Actions.pm` code constructs these nodes; only the
  hand-authored corpus fixtures + `Target::LLVM` do),
- **duplicates or drifts from canonical nodes** the design already specifies, and
- has **no documented bridge** to the canonical surface nodes the parser emits.

Critically, `lib/Chalk/IR/Target/LLVM.pm` lowers ONLY the parallel nodes — it has
**zero dispatch arms** for the canonical `Subscript`, `PostfixDeref`, `ArrayRef`,
`HashRef`, `Call`, or `Length`. So today there are two disconnected tiers and the
backend only understands the wrong one.

**Decision (perigrin, 2026-06-08): fix all the drift; converge on a SINGLE IR.**
The canonical surface nodes (which the parser already emits) are THE IR; the LLVM
backend must lower THOSE; the parallel nodes are deleted, except for the genuinely
new ones, which are kept ONLY if added to the design docs.

## Audit verdicts (the work-list)

### Cluster A — Aggregate / deref (G4), all in `lib/Chalk/IR/Node/`

| Parallel node | Canonical target | Verdict | Action |
|---|---|---|---|
| `ScalarLen` | `Length` (UnaryOp) | DUPLICATE | delete; give `Length` a repr-aware LLVM arm (array-count vs str-length via repr/field) |
| `ArrayRead` | `Subscript` (container,index) | duplicate-by-layer | delete; LLVM lowers `Subscript` with array repr → bounds-checked slot load |
| `HashRead` | `Subscript` (container,key) | duplicate-by-layer | delete; LLVM lowers `Subscript` with hash repr → memcmp key scan |
| `ArrayWrite` | `Assign(Subscript-lvalue, val)` | GENUINELY-NEW behavior, undocumented | replace with `Assign` over a `Subscript` lvalue (element store); LLVM lowers that |
| `HashWrite` | `Assign(Subscript-lvalue, val)` | GENUINELY-NEW behavior, undocumented | same as ArrayWrite |
| `ArrayDeref` | `PostfixDeref` (sigil=`@`) | duplicate-by-layer | delete; LLVM lowers `PostfixDeref` by sigil |
| `HashDeref` | `PostfixDeref` (sigil=`%`) | duplicate-by-layer | delete; LLVM lowers `PostfixDeref` by sigil |
| `ArrayLiteral` | `ArrayRef` (constructs from elements) | overlaps constructor role | fold into `ArrayRef` (value-vs-ref split → a repr/flag on `ArrayRef`, NOT a 2nd node) |
| `HashLiteral` | `HashRef` (constructs from pairs) | overlaps constructor role | fold into `HashRef` |
| `MakeArrayRef` | `ArrayRef` | take-ref vs construct — DECIDE | either: `ArrayRef` already yields a ref (no separate take-ref), or document a distinct take-ref op. Likely fold: `ArrayRef` IS the ref-producing constructor. |
| `MakeHashRef` | `HashRef` | same | same |

Open sub-decision in Cluster A: the value-vs-ref split (`ArrayLiteral` = unboxed
`%Array` value; `MakeArrayRef` = boxed ref) the subagent introduced. Canonical
`ArrayRef` "constructs an array reference from elements" — it conflates construct +
ref. **Resolution to confirm during execution:** keep ONE canonical `ArrayRef` that
produces a ref; the unboxed-value tier becomes an LLVM-emitter implementation detail
(a temp `%Array` the emitter materializes then references), NOT a separate IR node.

### Cluster B — feature-class MOP (G5), all in `lib/Chalk/IR/Node/`

| Parallel node | Canonical target | Verdict | Action |
|---|---|---|---|
| `MethodCall` | `Call(dispatch_kind='method', name, target/set_target)` | DUPLICATE of the unified `Call` the deleted Shim was replaced BY | delete; emit `Call(dispatch_kind='method')`; teach LLVM to lower method-`Call` via the vtable slot (resolve from `target` MOP::Method or class registry) |
| `New` | `Call(dispatch_kind='method', name='new')` | DUPLICATE (construction is method dispatch) | delete; emit `Call(name='new')`; the malloc/vtable/:param/ADJUST behavior becomes the LLVM lowering of `new`-Call. (If a distinct `Construct` node is wanted, it MUST be documented first.) |
| `MethodDef` | `MethodInfo` / `MOP::Method` (+ its Graph) | DUPLICATE of the MOP/metadata layer | delete; method structure lives in `MOP::Method`/`MethodInfo`; LLVM consumes that |
| `FieldDef` | `MOP::Field` / `FieldInfo` | DUPLICATE | delete; field metadata (fieldix/is_param/has_reader/default) lives in `MOP::Field` |
| `ClassDecl` | `MOP::Class` / `ClassInfo` | DUPLICATE | delete; class structure lives in `MOP::Class`/`ClassInfo`; LLVM consumes the MOP, not a node subtree |
| `AdjustBlock` | `MOP::Phaser::Adjust` (+ its Graph) | DUPLICATE | delete; ADJUST lives in the MOP phaser layer |
| `FieldWrite` | `Assign(FieldAccess-lvalue, val)` | DRIFTS (drops `field_stash`; relies on ambient emitter state) | replace with `Assign` over a `FieldAccess` lvalue carrying field_index + field_stash |

The G5 direction must align with the documented **codegen-reads-MOP** migration
(`docs/plans/2026-04-21-chalk-mop-migration-plan.md`): the LLVM backend should read
`MOP::Class`/`ClassInfo` for class/method/field/ADJUST structure, NOT a parallel
in-graph node subtree.

### Conforms (no action) — already aligned with the taxonomy
`RegexMatch`/`RegexSubst` (registered, extend the documented `Regex` base — though
G6 is still only spiked, not built); `Coerce` (typed-rep model); the `Bool`/`Str`/
`Slot`/`Undef` **representations** (these are repr tags + LLVM types, NOT nodes —
correct per `typed-ir-representation.md`); `TypeTag.pm` (the compare oracle, test-side).

## The unified-IR target (what "single IR" means here)

ONE node vocabulary — the canonical surface nodes the parser emits:
- aggregates: `ArrayRef`, `HashRef` (construct), `Subscript` (read + lvalue-for-write),
  `PostfixDeref` (deref by sigil), `Slice`, `Length`.
- calls/objects: `Call` (dispatch_kind method/sub/builtin + `target`), `FieldAccess`
  (read; field_index+field_stash), `Assign` (writes, incl. element/field stores),
  `Ref`; class/method/field/ADJUST structure in the **MOP/`ClassInfo` layer**.
- value reps (Bool/Int/Num/Str/Undef/Array/Hash/Slot) stay as **representation tags +
  LLVM types**, not nodes. `Coerce` edges stay.

`Target::LLVM` is refactored to lower THESE. The ~16 duplicate/drift parallel nodes
are DELETED; element-store and field-store become `Assign`-over-lvalue; the genuinely
new behaviors (element store, the malloc/vtable construction lowering) live in the
**LLVM emitter**, driven by canonical nodes + repr + the MOP — not new node types.
Any node we choose to KEEP as genuinely-new MUST be added to
`docs/architecture/sea-of-nodes-ir.md` in the same change.

## Execution plan (TDD, bite-sized, dependency-ordered)

**Invariant for the whole refactor:** the G4/G5 corpus cases (references.md R1–R11,
classes.md 7 cases) MUST stay GREEN (lli==perl, libperl-free) at every step — they
are the behavioral contract. The refactor changes the IR the corpus ir-blocks
construct + how LLVM lowers them; the *observable* behavior must not change. Because
the corpus ir-blocks ARE the parser's spec, rewriting them onto canonical nodes is
part of the deliverable (it makes the spec honest).

Order (each phase: rewrite corpus ir-blocks → teach LLVM to lower the canonical node
→ delete the parallel node → full corpus+ir sweep GREEN → commit):

### Phase 0 — the trivial win (do first, de-risks the harness)
0.1 Fold `ScalarLen` → `Length`: rewrite R1's ir-block to use `Length` (repr Array);
add a repr-aware arm to LLVM for `Length`; delete `ScalarLen.pm` + its NodeFactory
entry + its LLVM arm. Sweep. Commit.

### Phase 1 — aggregate reads/derefs onto canonical nodes
1.1 `Subscript` lowering: teach LLVM to lower `Subscript` (inputs[0]=container,
inputs[1]=index/key), branching on the container's repr (Array → bounds-checked slot
load; Hash → memcmp key scan), reusing the existing `_lower_array_read`/
`_lower_hash_read` bodies. Rewrite R2/R3/R5 ir-blocks to `Subscript`. Delete
`ArrayRead`/`HashRead`. Sweep. Commit.
1.2 `PostfixDeref` lowering: teach LLVM to lower `PostfixDeref` by `sigil`
(`@`→array, `%`→hash) reusing the deref bitcast bodies. Rewrite R4/R5/R8. Delete
`ArrayDeref`/`HashDeref`. Sweep. Commit.

### Phase 2 — aggregate construction onto ArrayRef/HashRef
2.1 Fold `ArrayLiteral`/`MakeArrayRef` → `ArrayRef`; `HashLiteral`/`MakeHashRef` →
`HashRef`. Decide the value-vs-ref representation (recommend: `ArrayRef`/`HashRef`
produce the ref; the unboxed `%Array`/`%Hash` is an emitter temp). Teach LLVM to
lower `ArrayRef`/`HashRef`. Rewrite R1/R4/R5 ir-blocks. Delete the 4 parallel
construct nodes. Sweep. Commit.

### Phase 3 — element/field stores onto Assign-over-lvalue
3.1 Element store: rewrite R6/R7 ir-blocks to `Assign(Subscript-lvalue, value)`;
teach LLVM to lower an `Assign` whose lhs is a `Subscript` (element store). Delete
`ArrayWrite`/`HashWrite`. Sweep. Commit.
3.2 Field store: rewrite classes.md method-call/adjust ir-blocks to
`Assign(FieldAccess-lvalue, value)` (FieldAccess carries field_index + field_stash);
teach LLVM to lower it. Delete `FieldWrite`. Sweep. Commit.

### Phase 4 — method dispatch & construction onto Call
4.1 Method dispatch: teach LLVM to lower `Call(dispatch_kind='method')` via the
vtable slot, resolving the callee from `Call.target` (MOP::Method) or a class
registry. Rewrite classes.md method-simple/field-basic/field-attrs/class-isa
ir-blocks to use `Call(dispatch_kind='method')`. Delete `MethodCall`. Sweep. Commit.
4.2 Construction: rewrite `Empty->new` etc. to `Call(dispatch_kind='method',
name='new')`; move the malloc/vtable/:param/ADJUST lowering under the new-Call arm.
Delete `New`. Sweep. Commit.

### Phase 5 — class structure onto the MOP/ClassInfo layer
5.1 Replace the `ClassDecl`/`MethodDef`/`FieldDef`/`AdjustBlock` node subtree with
`MOP::Class`/`ClassInfo` (+ `MethodInfo`, `MOP::Field`, `MOP::Phaser::Adjust`) that
the LLVM backend consumes to build the per-class vtable + object struct + ADJUST
order. Rewrite all 7 classes.md ir-blocks to carry the class via the MOP/ClassInfo
metadata (the `%ref`-input mechanism), not the node subtree. Delete the 4 structural
nodes. Sweep. Commit. (Largest phase; aligns with the codegen-reads-MOP migration.)

### Phase 6 — documentation (mandatory, same change-set)
6.1 Update `docs/architecture/sea-of-nodes-ir.md`: confirm the canonical aggregate/
call/field nodes are the single vocabulary; document the element-store and
field-store = `Assign`-over-lvalue model; document the repr tags
(Bool/Str/Slot/Array/Hash) and that they are NOT nodes; record any genuinely-new
node KEPT (with rationale).
6.2 Update `docs/architecture/mop.md` + the codegen-reads-MOP plan to reflect that
the LLVM backend consumes the MOP for class structure.
6.3 Add a short "LLVM lowering: how canonical nodes map to LLVM" section so the
parser↔backend contract is explicit.

## Risks & mitigations
- **Risk:** rewriting corpus ir-blocks could mask a real behavior change.
  **Mitigation:** the perl oracle is unchanged; lli==perl must hold at every phase;
  the `behavior` blocks (perl results) are NOT edited — only the `ir` blocks.
- **Risk:** `Subscript`/`PostfixDeref` are parser-level polymorphic; the repr needed
  to pick array-vs-hash lowering must be present on the node. **Mitigation:** verify
  the repr/type is set on the container input; if the parser doesn't yet set it,
  that's a TypeInference gap to note (the corpus ir-blocks set it explicitly).
- **Risk:** Phase 5 (MOP consumption) is large and touches the stalled MOP-migration
  surface. **Mitigation:** consume `ClassInfo` (immutable, has id()) as a node input
  WITHOUT wiring the stalled migration internals; keep self-contained against the
  corpus.
- **Risk:** large refactor of gate-verified work. **Mitigation:** phase-by-phase,
  full sweep + lli==perl gate after each phase; each phase independently revertible.

## Acceptance criteria
- `lib/Chalk/IR/NodeFactory.pm` no longer registers the deleted parallel nodes; the
  deleted `.pm` files are gone.
- `Target::LLVM` lowers the canonical nodes (`Subscript`, `PostfixDeref`, `ArrayRef`,
  `HashRef`, `Length`, `Call`-method, `Assign`-over-lvalue, `FieldAccess`) and the
  MOP layer; it no longer dispatches the deleted ops.
- references.md R1–R11 + classes.md 7 cases stay GREEN (lli==perl, libperl-free);
  full corpus+ir+codegen-harness sweep exit=0, no non-TODO failures.
- The corpus ir-blocks (the parser's spec) use ONLY canonical nodes.
- The design docs (sea-of-nodes-ir.md, mop.md) match the implemented single IR; any
  genuinely-new node KEPT is documented with rationale.
- No regression to G2/G3/L3 cases.

## Target namespace consolidation (Finding 2)

**Decision (perigrin, 2026-06-08): codegen targets belong in a common top-level
`Chalk::Target::*`** — NOT under `Chalk::IR::` (targets are *consumers* of the IR,
not part of it) and NOT under the legacy `Chalk::Bootstrap::*::Target` (the
`Bootstrap` prefix is being retired). Target home = `Chalk::Target::{LLVM,Perl,C,XS}`,
with the existing abstract base `Chalk::Bootstrap::Target` ("Base class for code
generation targets") becoming `Chalk::Target` (the base interface that subclasses'
`generate()`/`lower()` implement).

Current surface (the move):

| Module | Current namespace | Consumers | Target namespace |
|---|---|---|---|
| `lib/Chalk/IR/Target/LLVM.pm` | `Chalk::IR::Target::LLVM` | **14** (all test-side, this session) | `Chalk::Target::LLVM` |
| `lib/Chalk/Bootstrap/Target.pm` | `Chalk::Bootstrap::Target` (base) | — | `Chalk::Target` (base) |
| `lib/Chalk/Bootstrap/Perl/Target/{Perl,C,EmitHelpers,ClassRegistry}.pm` | `Chalk::Bootstrap::Perl::Target::*` | part of ~153 | `Chalk::Target::{Perl,C,...}` |
| `lib/Chalk/Bootstrap/BNF/Target/{Perl,C,XS,XS/AST/*}.pm` | `Chalk::Bootstrap::BNF::Target::*` | part of ~153 | `Chalk::Target::BNF::*` (or fold) |

`Chalk::Target` does not exist yet (0 refs today).

### Two scopes (decide narrow-vs-full at execution time)
- **Narrow (cheap, do alongside Phase 0):** move ONLY `Chalk::IR::Target::LLVM` →
  `Chalk::Target::LLVM` (git mv + package rename + update the 14 `use` lines, all in
  t/), and create `Chalk::Target` as the base (promote `Bootstrap::Target`, leaving a
  compat alias if the 153 Bootstrap consumers still reference the old base). Fixes the
  immediate "LLVM shouldn't live under IR" problem; the Perl/C/XS family stays put for
  now under a tracked follow-up.
- **Full (large, tied to the Bootstrap rename):** also migrate the ~153-file
  `Chalk::Bootstrap::{Perl,BNF}::Target::*` family (Perl/C/XS + the BNF/XS AST tree +
  EmitHelpers/ClassRegistry) into `Chalk::Target::*`. ~167 files touched; entangled
  with the broader `Bootstrap`→`Chalk` rename, so it should be sequenced WITH that
  rename, not ahead of it.

### Recommendation
Do the **narrow** move (LLVM → `Chalk::Target::LLVM` + create `Chalk::Target` base)
as part of this reconciliation — it is cheap (14 test-side refs), removes the
"target under IR" wart immediately, and establishes `Chalk::Target` as the canonical
home so future targets land there. File the **full** Bootstrap-target migration as a
separate issue tied to the Bootstrap→Chalk rename (it is mechanical but large and
should not be smuggled into this node-reconciliation work). Update
`docs/architecture/ir-lowering.md` (which still describes the Bootstrap-namespaced
targets and never mentions the LLVM target) to reflect `Chalk::Target::*` as the
target layer.

## Execution disposition (to decide with perigrin after approval)
- A single tracked git-zhi issue ("target-layer reconciliation") with the node phases
  0–6 + the narrow `Chalk::Target` move as its task list, OR one issue per phase in a
  small chain; the full Bootstrap-target migration is its OWN issue (rename-tied).
- Sequence relative to G6/G7: STRONGLY prefer doing this reconciliation BEFORE G6/G7
  build more LLVM lowering on top of the parallel vocabulary (G6's RegexMatch is
  already taxonomy-conformant; G7's $1 consumes G6's capture struct — neither should
  accrete more drift). The narrow `Chalk::Target::LLVM` move should land FIRST (or
  alongside Phase 0) so G6/G7's new lowering code is written at the correct namespace.
