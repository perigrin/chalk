# Target-Layer Reconciliation: single IR vocabulary + a common `Chalk::Target` home

**Date:** 2026-06-08 (revised 2026-06-09 to fold in the full architecture review)
**Status:** PLAN — NEEDS REVISION before execution (plan-review 2026-06-09 found 5 Critical + 8 Important holes; see paad/architecture-reviews/2026-06-09-reconciliation-plan-review.md). Direction sound; sequencing/decomposition/specs need fixing.
**Author:** drafted from two alignment audits (aggregate-nodes + MOP-nodes), then
revised against the 5-specialist + verifier architecture review
(`paad/architecture-reviews/2026-06-08-target-ir-layer-review.md`), run against
commits `3435b75a..5f6a9f63` (the G2–G5 runtime-free GAP-clearing campaign).

**Scope:** this plan now covers the full target-layer architecture review:
- **Finding 1 (node taxonomy)** — converge the ~18 parallel G4/G5 nodes onto the
  single canonical IR (Problem → Node phases 1–6).
- **Finding 2 (target namespace)** — move the codegen targets into a common
  top-level `Chalk::Target::*` (the "Target namespace consolidation" section).
- **Gate-integrity + latent-hazard findings (F3–F8, F11 from the review)** — the
  review found the gate-driven campaign's HARNESS and emitter carry 6 verified
  latent hazards a pure node-convergence would NOT fix (and some it would mask).
  These are addressed in **Phase G (Gate Hardening)**, sequenced FIRST, plus notes
  on which dissolve under the convergence (Phases 3–5). See the "Architecture-review
  findings folded in" section.
- Finding 3 (LLVM-first sequencing) is RESOLVED — documented decision
  (`docs/plans/2026-06-06-three-axis-codegen-and-typed-ir-contract.md`), not drift;
  `docs/llvm-target.md` updated to cite it.
- `Chalk::IR::Node::Coerce` is NOT drift — it resolves
  `typed-ir-representation.md`'s own open questions (a node, parameterized by
  from/to) exactly as that doc planned. The model done right; protect it.

## Architecture-review findings folded in (F3–F11)

The review (`paad/architecture-reviews/2026-06-08-target-ir-layer-review.md`)
confirmed Findings 1+2 and surfaced 6 NEW verified latent hazards (all latent —
no current corpus case is actively miscompiled, but all real). They split into
**gate-integrity** (must fix BEFORE the convergence relies on the gate) and
**latent-codegen** (several dissolve when lowering routes through canonical nodes):

| ID | Finding | Severity | Where addressed |
|---|---|---|---|
| **F3** | The corpus harness launders a lowered-but-malformed `.ll` (lli-rejected) as a passing GAP; `LLVMDriver` and `LLVMGapMap` give OPPOSITE verdicts on the same situation; the corpus gate never emits the MISCOMPILE label. | High (gate) | **Phase G** |
| **F4** | No mechanical libperl-free guard on corpus GREENs — 5/12 corpus `.t` files (incl. classes.t) have NO assertion; the rest use inconsistent regexes (some miss `sv_`/`AV`/`HV`). | High (gate) | **Phase G** |
| **F5** | `TypedInvariant` `%OP_REQUIRED_REPR` covers 6 ops; ALL G3–G5 ops (array/hash/method/field/compare/logical) are unchecked, and it is the ONLY operand-rep guard. | High (gate) | **Phase G** |
| **F11** | No parser→graph→LLVM equivalence test; the corpus is the SOLE producer of the parallel tier — convergence finally wires canonical nodes to LLVM, the moment the divergence could ship silently. | Med (gate) | **Phase G** (acceptance gate) |
| **F6** | Method-body `_need_*` flags (`_need_bool_str_globals`/`_need_str_to_num_helper`/`_need_memcmp`) set on the distinct `$body_ctx` are not propagated → undeclared-global IR. Same silent-stub class as the already-fixed Coerce(Bool→Str), one scope deeper. | High (codegen) | **Phase G** (fix now; it is a live emitter bug regardless of convergence) |
| **F7** | `representation // 'Int'` (~19 sites) silently lowers an undef-repr node as i64 before the Scalar-GAP `die` runs; `_lower_constant` emits `add i64 0,$val`. Defense-in-depth weakness. | Med (codegen) | **Phase G** (replace `// 'Int'` with an explicit "missing-repr → loud GAP") |
| **F8** | `_lower_and`/`_lower_or` hardcode `icmp ne i64`; `_lower_not`/`_ensure_i1` do `*→Bool` truthiness INLINE — a §2 "coercion is a visible node" violation AND a latent miscompile for a Bool/Num operand. Two impls of `*→Bool` (inline vs the `_lower_coerce` node). | Med (codegen) | **Dissolves in Phase 1+** if truthiness routes through an explicit `Coerce(*→Bool)` node; otherwise fix in Phase G. Decide during execution. |
| **F9** | `FieldWrite`/`FieldAccess` meaning depends on ambient `_in_method_body` state; FieldWrite dropped `field_stash`; 3 `_lower_field_write*` variants. | Med (codegen) | **Dissolves in Phase 3.2** (field store → `Assign(FieldAccess-lvalue)` carrying field_stash; ambient mode-flags removed). |
| **F2-iface** | The two target families have DIVERGENT interfaces — `Bootstrap::Target` defines `generate($ir)`; `IR::Target::LLVM` exposes `lower($return_node)` and does NOT inherit the base. | Med (namespace) | **Namespace section** — reconcile when `Chalk::Target` becomes the base. |
| **F10** | `LLVM.pm`'s 2831-line `Context` package bundles 4 separable responsibilities; `_process_if_node`/`_wire_region_phis` are duplicated (copy-paste-with-divergence) between `Context` and `ElaboratedContext`. | Med (cohesion) | **Tracked SEPARATELY** — pre-existing control-processor duplication, orthogonal to G4/G5; a follow-up cleanup, not part of this convergence. |

**Strengths to protect (do not regress):** repr-out-of-content_hash discipline;
Coerce as a hash-distinct explicit-on-edge node; acyclic Target→IR→MOP with no
`lib/`→`t/lib/` dependency; the GAP/MISCOMPILE+type-tag *model* (Phase G fixes its
*enforcement*, not the model); the adversarial loud-failures (MethodCall-on-absent,
OOB→undef).

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

Order: **Phase G (gate hardening) FIRST** — the gate must be trustworthy before
the node-convergence relies on it (the convergence is precisely what wires the
canonical tier to LLVM, the moment F11's divergence and F3's laundering could ship
silently). Then the node phases (each: rewrite corpus ir-blocks → teach LLVM to
lower the canonical node → delete the parallel node → full corpus+ir sweep GREEN →
commit).

### Phase G — Gate hardening (do FIRST; the review's strongest recommendation)
The campaign's gate is the thing that certifies "lli==perl, libperl-free, GAP-not-
MISCOMPILE." The review found it has silent-escape hatches. Harden it BEFORE the
convergence depends on it. Each sub-step is TDD (write a test that the CURRENT gate
wrongly passes / fails to catch, then fix the gate so it catches it).

G.1 (F3) Unify the GAP-vs-MISCOMPILE classification across harnesses. `LLVMDriver`
+ `MdtestCorpus` must distinguish lower-error (legitimate GAP) from lli-rejected-IR
(MISCOMPILE) from output-mismatch (MISCOMPILE) — a successfully-lowered `.ll` that
lli rejects is a MISCOMPILE, NEVER a GAP. Align `MdtestCorpus`'s classification with
`LLVMGapMap`'s (`lli_exit!=0 → MISCOMPILE`), and make the corpus gate EMIT the
MISCOMPILE label. RED: a fixture that lowers but emits malformed IR must be
classified MISCOMPILE (today the corpus gate would call it GAP/PASS). Commit.

G.2 (F4) Central mechanical libperl-free guard. Add ONE guard in the harness
(LLVMDriver/MdtestCorpus) that greps every GREEN `.ll` for `Perl_|\bSV\b|sv_|\bAV\b|
\bHV\b|\bPL_|newSV|libperl` and FAILS the GREEN on any hit — replacing the absent /
inconsistent per-`.t` `unlike()` calls. RED: a fixture whose `.ll` contains a libperl
symbol must FAIL its GREEN verdict (today increment/regex/variables/classes/subs
GREENs would pass it uncaught). Commit.

G.3 (F5) Extend `TypedInvariant` `%OP_REQUIRED_REPR` to the G3–G5 ops: Concat→Str (has
it), the array/hash ops (container operand must be Array/Hash repr; index Int; key
Str), method dispatch (invocant must be Object repr), comparisons/logical (operand
reps), so a mistyped operand is caught at the typed-graph layer, not at a backend
bitcast. Add bilateral `well-typed-graph.t` cases per the bilateral-coverage rule.
RED: a hand-authored graph passing an Int where %Array is required must FAIL
TypedInvariant (today it passes). Commit.

G.4 (F11) Parser→graph→LLVM equivalence GATE. This is the ACCEPTANCE CRITERION for
the whole convergence, not a one-off: once LLVM lowers the canonical nodes, add a
test that a graph in canonical-node shape (as the parser would emit) lowers and
matches perl — so the corpus spec and a future parser cannot diverge silently. (If
the parser can't yet emit a given idiom, the canonical-shape hand-authored graph is
the stand-in, but it MUST be canonical-node-shaped, not parallel-tier.) This gate is
satisfied incrementally as each node phase converts its corpus to canonical nodes.

G.5 (F6) Fix the method-body `_need_*` flag propagation NOW (a live emitter bug): the
prologue must see the flags set during method-body lowering (propagate ALL `_need_*`
from `$body_ctx` to `$ctx`, or lower bodies before assembling the prologue). RED: a
method body doing `Coerce(Bool->Str)` or a hash-key compare must NOT emit
undeclared-global IR (today it does → lli rejects → F3 would mis-file it as GAP).
Commit. (This is independent of the convergence; it is wrong today.)

G.6 (F7) Replace `representation // 'Int'` defaulting with an explicit missing-repr
policy: an undef-repr node reaching lowering is a loud GAP/die ("node X has no
representation"), NOT a silent i64. RED: an undef-repr Constant must GAP, not emit
`add i64 0,$val`. (Coordinate with `_ensure_i1`'s existing undef-repr die, which is
already correct — make the rest consistent.) Commit.

G.7 (F8) Decide the `*→Bool` truthiness duplication: route `_lower_and`/`_lower_or`/
`_lower_not` through the explicit `Coerce(*→Bool)` node path (the on-graph impl in
`_lower_coerce`) instead of the inline hardcoded `icmp ne i64`. This removes the §2
violation AND the latent Bool/Num-operand miscompile. (May naturally fold into Phase
1 if logical ops get repr-dispatched lowering then; decide during execution. If
deferred, leave the inline path with a loud die on non-Int operands rather than a
silent i64 reinterpret.) Commit.

After Phase G the gate reliably distinguishes GAP/MISCOMPILE, enforces libperl-free
+ operand-rep + equivalence, and the two live emitter bugs (F6, F7) are gone. NOW the
node convergence can proceed on a trustworthy gate.

### Phase 0 — the trivial win (de-risks the convergence; do right after Phase G)
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
6.4 `typed-ir-representation.md`: STRIKE the answered open-questions Q2/Q3 (Coerce =
a node, parameterized — done); WRITE the realized representation lattice into the
model (the campaign added Bool/Str{ptr,len,encoding}/Slot{defined,payload}/Array/Hash/
Object/Undef — load-bearing but documented only by grepping the backend; this closes
Q1's silent drift). Update `Node.pm`'s representation-field comment (which lists only
Int/Num/Ptr/Struct/Scalar) to match.
6.5 `ir-lowering.md`: it describes only the Bootstrap-namespaced Perl/XS/C targets and
never mentions the LLVM target — update it to the `Chalk::Target::*` layer incl. LLVM.

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

### Phase G (gate hardening)
- A lowered-but-lli-rejected `.ll` is classified MISCOMPILE (not GAP) by the corpus
  gate, and the gate EMITS the MISCOMPILE label; `LLVMDriver`/`MdtestCorpus`/
  `LLVMGapMap` agree on the classification (F3).
- Every GREEN's `.ll` passes ONE central mechanical libperl-free guard
  (`Perl_|\bSV\b|sv_|\bAV\b|\bHV\b|\bPL_|newSV|libperl`); a leak FAILS the GREEN (F4).
- `TypedInvariant` checks operand reps for the array/hash/method/field/compare/logical
  ops, with bilateral `well-typed-graph.t` coverage; a mistyped operand FAILS (F5).
- A method body doing `Coerce(Bool->Str)` / hash-key compare emits NO undeclared-global
  IR (F6 fixed); an undef-repr node GAPs loudly instead of silently lowering as i64
  (F7 fixed).
- `*→Bool` truthiness goes through the explicit Coerce path OR loudly dies on a
  non-Int operand — no silent i64 reinterpret (F8).

### Node convergence (Findings 1 + F8/F9 dissolution)
- `lib/Chalk/IR/NodeFactory.pm` no longer registers the deleted parallel nodes; the
  deleted `.pm` files are gone.
- `Target::LLVM` lowers the canonical nodes (`Subscript`, `PostfixDeref`, `ArrayRef`,
  `HashRef`, `Length`, `Call`-method, `Assign`-over-lvalue, `FieldAccess`) and the
  MOP layer; it no longer dispatches the deleted ops.
- F9 dissolved: field store is `Assign(FieldAccess-lvalue)` carrying field_stash; no
  `_in_method_body` ambient operand-reinterpretation remains.
- references.md R1–R11 + classes.md 7 cases stay GREEN (lli==perl, libperl-free);
  full corpus+ir+codegen-harness sweep exit=0, no non-TODO failures.
- The corpus ir-blocks (the parser's spec) use ONLY canonical nodes; the F11
  parser-equivalence gate holds (canonical-shape graphs lower and match perl).

### Namespace (Finding 2)
- `Chalk::Target::LLVM` exists (narrow move done); `Chalk::Target` is the base;
  the interface divergence (F2-iface) is reconciled and recorded in the base class.
- The full `Bootstrap::*::Target` migration is filed as a separate rename-tied issue.

### Docs + cross-cutting
- `sea-of-nodes-ir.md` + `mop.md` match the implemented single IR; the realized
  representation lattice (Bool/Str{ptr,len,encoding}/Slot{defined,payload}/Array/Hash/
  Object/Undef) is written into `typed-ir-representation.md`; its answered Coerce
  Q2/Q3 are struck; `ir-lowering.md` reflects `Chalk::Target::*` + the LLVM target.
- F10 (the `Context`/`ElaboratedContext` control-processor duplication + the 2831-line
  Context cohesion) is FILED as a separate follow-up cleanup, not done here.
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

### Interface divergence (F2-iface, from the review)
The two target families have INCOMPATIBLE interfaces: `Chalk::Bootstrap::Target`
(the abstract base) declares `generate($ir)` / `generate_distribution($ir)`;
`Chalk::IR::Target::LLVM` exposes `lower($return_node)` / `lower_with_elaboration`
and does NOT inherit the base. So "target" is a naming convention today, not a shared
contract. When `Chalk::Target` becomes the common base, this MUST be reconciled —
otherwise the common namespace houses two unrelated APIs. Decide during the narrow
move: either (a) LLVM adopts a `generate`-shaped entry that wraps `lower`, or (b) the
`Chalk::Target` base is (re)defined around the entry both families can satisfy (e.g.
a `lower(graph) -> artifact` contract). Low effort but it should be a deliberate
choice, recorded in the base class, not left divergent.

### Recommendation
Do the **narrow** move (LLVM → `Chalk::Target::LLVM` + create `Chalk::Target` base,
+ reconcile the interface per F2-iface) as part of this reconciliation — it is cheap
(14 test-side refs), removes the "target under IR" wart immediately, and establishes
`Chalk::Target` as the canonical home so future targets land there. File the **full**
Bootstrap-target migration as a separate issue tied to the Bootstrap→Chalk rename (it
is mechanical but large and should not be smuggled into this node-reconciliation
work). Update `docs/architecture/ir-lowering.md` (which still describes the
Bootstrap-namespaced targets and never mentions the LLVM target) to reflect
`Chalk::Target::*` as the target layer.

## Execution disposition (to decide with perigrin after approval)
- **Phases:** G (gate hardening) → narrow namespace move + Phase 0 → Phases 1–6
  (node convergence) → Phase 6 docs. The full Bootstrap-target migration and the F10
  Context cleanup are their OWN separate issues.
- **Issue shape:** likely a small git-zhi chain — `Phase G` as the first issue (it
  stands alone and is valuable even if the convergence slips), then the convergence as
  one issue or a per-phase chain, then the namespace + docs. Phase G gates the rest.
- **Sequence relative to G6/G7:** STRONGLY prefer this whole reconciliation BEFORE
  G6/G7 build more LLVM lowering on the parallel vocabulary. G6's `RegexMatch` is
  already taxonomy-conformant; G7's $1 consumes G6's capture struct — neither should
  accrete more drift. The narrow `Chalk::Target::LLVM` move lands with Phase 0 so
  G6/G7's new code is written at the right namespace; **Phase G lands FIRST so G6/G7
  (and the convergence) are gated by a trustworthy harness.**
- **Why Phase G first (the review's key point):** F3/F4/F11 are gate-integrity
  defects — the harness can currently pass a malformed-IR case as a GAP, miss a
  libperl leak, and never compare canonical-shape graphs. A pure node-convergence
  built on that gate would inherit the blind spots (and F11's divergence ships at the
  moment convergence wires canonical nodes to LLVM). Harden the gate, THEN converge.
