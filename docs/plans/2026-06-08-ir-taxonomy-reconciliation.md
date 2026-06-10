# Target-Layer Reconciliation: single IR vocabulary + a common `Chalk::Target` home

**Date:** 2026-06-08 (revised 2026-06-09 to fold in the full architecture review)
**Status:** COMPLETE 2026-06-10 on branch `phase1-lateral-bindings`. Phase G
2026-06-09 (commits 4f359148 namespace, 9461893f G.1, 4da9373b G.2, 647b8e1f G.5,
c80532e8 G.6, 59293100 G.7); node-convergence Phases 0–3 = R2 (fa7c0715..af42bab2
+ the reopen), Phases 4–5 = R3 (5cd5324d..3d550d5f), Phase 6 docs (f94ea2a8).
Whole-branch review 2026-06-10 (paad/code-reviews/...-256a9b37-branch-agentic.md)
verified the acceptance criteria; deferral labels: TypedInvariant per-phase
coverage → zhi 019eaf54; the four follow-ups this plan referenced as "filed"
(Bootstrap-target migration, F8 §2-purity Coerce route, I3 parser→LLVM
equivalence gate, F10 Context split) are NOW actually filed (zhi 019eb316-*,
2026-06-10 — they had not been, contra the text below).

**G.0 Baseline (2026-06-09):**
Pre-existing failures at the start of Phase G work:
- t/bootstrap/mop/codegen-byte-compat.t: test 14 fails (Chalk__MOP__Class.pl.golden)
- t/bootstrap/mop/codegen-byte-compat-schedule.t: test 14 fails (same)
- t/bootstrap/mop/class-scope-vars.t: exits 255 at test 3
- t/bootstrap/mop/ir-completeness.t: tests 242-244 fail (all marked # TODO)
All ir/llvm-*.t, corpus/mdtest.t, codegen-harness/*.t: PASS.
These pre-existing failures are NOT ours (stalled-MOP-migration surface).

**F10 follow-up (deferred per I5):** The `LLVM.pm` `Context` package (2831 lines)
bundles 4 separable responsibilities; `_process_if_node`/`_wire_region_phis` are
duplicated between `Context` and `ElaboratedContext`. Pre-existing, orthogonal to
Phase G and the node-convergence. Filed as a separate cleanup to address when the
parallel node arms are deleted (Phase G reduces the problem surface; the real
split is valuable AFTER the convergence removes ~18 parallel dispatch arms and the
Context shrinks significantly). Deferral is labeled here, not drift.

**Phase G GREEN-set result:** No currently-GREEN corpus cases newly-failed.
All guards (G.1 MISCOMPILE classification, G.2 libperl-free, G.5 flag propagation,
G.6 undef-repr, G.7 Bool/Or truthiness) latently protect against future bugs;
no active corpus case exposed a pre-existing defect requiring triage.

REVISED 2026-06-09 to address the plan-review's 5 Critical + 8 Important holes (`paad/architecture-reviews/2026-06-09-reconciliation-plan-review.md`); awaiting perigrin's re-review. Fixes: C1 GREEN-invariant corrected for Phase G; C2 F8 = loud-die (verified it does NOT dissolve); C3 MOP-before-dispatch (Phases 4↔5 entangled, stated); C4 MOP phase decomposed 4.0–4.5; C5 TypedInvariant moved per-phase; I1/I2 ir-block syntaxes specified; I3 G.4 resolved; I4 nested-ref resolved; I6 G.0 baseline; I7 optimizer shape-oracle risk; I5 F10 filed in G.0.
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
| **F8** | `_lower_and`/`_lower_or` hardcode `icmp ne i64`; `_lower_not`/`_ensure_i1` do `*→Bool` truthiness INLINE — a §2 "coercion is a visible node" violation AND a latent miscompile for a Bool/Num operand. | Med (codegen) | **Phase G.7 — DOES NOT dissolve (C2, verified: And/Or/Not are canonical nodes the convergence never touches).** Fix = loud-die on non-Int operand (keeps L1/L2 green, no corpus change). The §2-purity route-through-Coerce is a tracked follow-up. |
| **F9** | `FieldWrite`/`FieldAccess` meaning depends on ambient `_in_method_body` state; FieldWrite dropped `field_stash`; 3 `_lower_field_write*` variants. | Med (codegen) | **Dissolves in Phase 4.4** (field store → `Assign(FieldAccess-lvalue)` carrying field_stash; ambient mode-flags removed). |
| **F2-iface** | The two target families have DIVERGENT interfaces — `Bootstrap::Target` defines `generate($ir)`; `IR::Target::LLVM` exposes `lower($return_node)` and does NOT inherit the base. | Med (namespace) | **Namespace section** — reconcile when `Chalk::Target` becomes the base. |
| **F10** | `LLVM.pm`'s 2831-line `Context` package bundles 4 separable responsibilities; `_process_if_node`/`_wire_region_phis` are duplicated (copy-paste-with-divergence) between `Context` and `ElaboratedContext`. | Med (cohesion) | **FILED as a separate issue in G.0 (I5)** — pre-existing control-processor duplication, orthogonal to G4/G5; the issue number/ref is recorded in G.0's note so the deferral is labeled, not drift (CLAUDE.md). Not done in this convergence. |

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

> **REVISED 2026-06-09** to fix the plan-review's 5 Critical + 8 Important holes
> (`paad/architecture-reviews/2026-06-09-reconciliation-plan-review.md`). Key changes:
> the GREEN invariant is corrected for Phase G (C1); F8 is an explicit loud-die fix
> (C2); old Phase 4 (Call dispatch) now FOLLOWS old Phase 5 (MOP structure) and they
> form one entangled set (C3); the MOP phase is decomposed (C4); TypedInvariant
> moves per-phase (C5); the missing ir-block syntaxes are specified (I1, I2); the
> nested-ref fold (I4) and G.4 ambiguity (I3) are resolved.

**Invariant — corrected (C1):**
- **Node-convergence phases (0–6):** the corpus cases MUST stay GREEN (lli==perl,
  libperl-free) at every step — the *observable* behavior must not change; only the
  IR shape + lowering does.
- **Phase G (gate hardening):** the GREEN set may legitimately SHRINK. Phase G EXISTS
  to make the gate fail things the lax gate wrongly passed. **Any case Phase G
  newly-fails is a real latent bug Phase G EXPOSED — NOT a regression.** Each such
  case is triaged: fix the underlying emitter bug, or correct an actually-wrong corpus
  ir-block. A smaller-but-honest GREEN set after Phase G is the intended outcome.

Order: **Phase G first** (trustworthy gate before the convergence relies on it), then
Phase 0, then the node phases. Within the node phases, **MOP structure precedes method
dispatch** (C3): the old "Phase 4 (Call dispatch)" now comes AFTER the MOP phase,
because `Call(dispatch_kind='method').target` is a `MOP::Method` that the MOP phase
introduces.

### Phase G — Gate hardening (FIRST)
The gate certifies "lli==perl, libperl-free, GAP-not-MISCOMPILE." The review found
silent-escape hatches. Harden it BEFORE the convergence depends on it. Each sub-step
is TDD. **Note (C5):** the TypedInvariant *extension* is NOT here — it is per-phase
(each node phase adds the invariant for its canonical op). Phase G keeps only the
gate-MECHANISM fixes that are independent of the final op set.

G.0 BASELINE (I6): before any change, run the FULL suite
(`$P -Ilib -It/lib t/bootstrap/**/*.t` + the corpus) and RECORD the failing set
(the known pre-existing failures: codegen-byte-compat{,-schedule}.t,
class-scope-vars.t — and anything else). This baseline is what "no NEW regression"
is measured against; without it, a Phase-G-exposed failure can't be told from a
pre-existing one. Commit the baseline as a note in the plan/PR.

G.1 (F3) Unify GAP-vs-MISCOMPILE across harnesses (HARNESS-side only, S3/M1): a
successfully-lowered `.ll` that lli REJECTS is a MISCOMPILE, NEVER a GAP. Align
`MdtestCorpus`'s classification with `LLVMGapMap`'s (`lli_exit!=0 → MISCOMPILE`) and
make the corpus gate EMIT the MISCOMPILE label. RED: a fixture that lowers but emits
malformed IR is classified MISCOMPILE (today: GAP/PASS). All fixes land in `t/lib`,
NOT in `LLVM.pm`. Commit.

G.2 (F4) ONE central mechanical libperl-free guard in the harness: grep every GREEN
`.ll` for `Perl_|\bSV\b|sv_|\bAV\b|\bHV\b|\bPL_|newSV|libperl`, FAIL the GREEN on any
hit. Replaces the absent/inconsistent per-`.t` `unlike()` calls. RED: a fixture whose
`.ll` contains a libperl symbol FAILS its GREEN. **Expect (C1): this may newly-fail
currently-GREEN cases** (classes.t etc. have no guard today) — triage each as a real
leak to fix or a clean case. Commit.

G.5 (F6) Fix the method-body `_need_*` flag propagation (a LIVE emitter bug,
independent of convergence): propagate ALL `_need_*` from `$body_ctx` to `$ctx` (or
lower bodies before assembling the prologue). RED: a method body doing
`Coerce(Bool->Str)` / hash-key compare must NOT emit undeclared-global IR. Commit.

G.6 (F7) Replace `representation // 'Int'` (~19 sites) with an explicit missing-repr
policy: an undef-repr node reaching lowering is a loud GAP/die ("node X has no
representation"), NOT a silent i64. RED: an undef-repr Constant GAPs, not
`add i64 0,$val`. (Make the rest consistent with `_ensure_i1`'s already-correct
undef-repr die.) Commit.

G.7 (F8) Fix the `*→Bool` truthiness inline-hardcoding. **DECIDED (C2): loud-die, NOT
route-through-Coerce.** `_lower_and`/`_lower_or`/`_lower_not`/`_ensure_i1` keep the
`icmp ne i64` path for Int operands but DIE LOUDLY on a non-Int operand
("`&&`/`||`/`!` operand has repr X; only Int truthiness is lowered runtime-free —
GAP") instead of silently reinterpreting it as i64. This removes the latent Bool/Num
miscompile and keeps L1/L2 (Int operands) GREEN with NO corpus change. RED: an
`And(Bool, Bool)` graph GAPs loudly, not a silent i64 misread. (The §2-purity fix —
routing truthiness through an explicit `Coerce(*→Bool)` node, which would require
adding Coerce edges to the logical.md ir-blocks — is a TRACKED FOLLOW-UP, filed in
G.0's note, NOT done here.) Commit.

> Removed from Phase G: the old G.3 (TypedInvariant extension) → now per-phase (C5).
> The old G.4 (parser-equivalence) is resolved as I3 below, not a Phase-G step.

After Phase G the gate distinguishes GAP/MISCOMPILE, mechanically enforces
libperl-free, the two live emitter bugs (F6/F7) are gone, and `*→Bool` fails loud
instead of silent. The GREEN set is now smaller-but-honest. NOW the convergence
proceeds on a trustworthy gate.

### ir-block syntax specifications (resolve BEFORE the phases that need them)

**I1 — lvalue store ir-block syntax (needed by Phase 3).** `build_graph_from_ir`
(`MdtestCorpus.pm` `_build_node_from_rhs`) has no lvalue-store form today. Specify:
an element/field store is `%r = Assign(%lvalue, %val)` where `%lvalue` is a
`Subscript`/`FieldAccess` node used in lvalue position. The builder's general N-ary
path already constructs `Assign(inputs => [%lvalue, %val])`; the LLVM `_lower_assign`
must detect when `inputs[0]->operation` is `Subscript`/`FieldAccess` and emit a STORE
(vs the scalar-rebind it does today). Add the builder support + this lowering branch
as the FIRST commit of Phase 3, with a RED test, before rewriting any corpus block.

**I2 — ClassInfo-as-input ir-block syntax (needed by the MOP phase).** Specify how a
class rides into a graph: `%ci = ClassInfo(name: "Pair", parent: "", fields: [...],
methods: [...])` is NOT expressible in the flat `key:value` grammar. RESOLUTION: the
builder gains a `ClassInfo(...)`/`MethodInfo(...)` constructor recognizer (like the
existing `Coerce`/`Constant`/`New` special-cases in `_build_node_from_rhs`) that
builds the immutable `Chalk::IR::ClassInfo`/`MethodInfo` object from named attrs +
`%ref` sub-lists, and consumers reference it via `%ci`. This reuses the existing
immutable classes (which have `id()`/`add_consumer`) WITHOUT wiring the stalled MOP
migration internals. Build + test this builder support as the FIRST commit of the
MOP phase, before rewriting any classes.md block.

**I3 (G.4 resolved) — the parser-equivalence "gate" is the corpus-rewrite itself.**
There is no separate parser→LLVM test in this work (the parser does not emit these
idioms yet — out of scope). The acceptance is: after the convergence, the corpus
ir-blocks use ONLY canonical nodes, so "the spec the parser must emit" and "what LLVM
lowers" are the SAME canonical vocabulary by construction. A TRUE
`Actions.pm → NodeFactory → LLVM → lli` equivalence test is a FUTURE gate, filed as a
follow-up (in G.0's note), to land when the parser is wired to LLVM (G6/G7-era).

**I4 (nested-ref fold) — RESOLVED before Phase 2.** R8 nests refs (`ArrayRef`-typed
slots holding inner arrayrefs). Decision: keep ONE canonical `ArrayRef` that ALWAYS
produces a ref-to-array; its element inputs may themselves be `ArrayRef`s (a ref of
refs — exactly R8). The unboxed `%Array` value is purely an emitter temp the
`_lower_array_ref` arm materializes then references; it is NEVER a separate IR node.
So `ArrayRef(%inner_ref0, %inner_ref1)` = "build an array whose two elements are the
two inner refs, return a ref to it." No ambiguity: construct-then-ref composes
because elements are just values (refs are values). Confirmed; Phase 2 proceeds on
this.

### Phase 0 — the trivial win (right after Phase G)
0.1 Fold `ScalarLen` → `Length`: rewrite R1's ir-block to `Length` (repr Array); add a
repr-aware arm to LLVM for `Length` (array-count vs str-length by repr); EXTEND
`TypedInvariant` for `Length` (operand must be Array or Str) + a bilateral
well-typed-graph.t case (C5); delete `ScalarLen.pm` + its NodeFactory entry + LLVM
arm. Sweep. Commit. (The narrow `Chalk::Target::LLVM` namespace move already landed
BEFORE Phase G per I8 — see the namespace section — so Phase 0's and Phase G's tests
are written against the final name.)

### Phase 1 — aggregate reads/derefs onto canonical nodes
1.1 `Subscript` lowering: teach LLVM to lower `Subscript` (inputs[0]=container,
inputs[1]=index/key), repr-dispatched on the container (Array → bounds-checked slot
load; Hash → memcmp key scan), reusing the `_lower_array_read`/`_lower_hash_read`
bodies. EXTEND `TypedInvariant`: `Subscript` container ∈ {Array,Hash}, index Int /
key Str (C5) + bilateral cases. Rewrite R2/R3/R5 ir-blocks to `Subscript`. Delete
`ArrayRead`/`HashRead`. Sweep. Commit.
1.2 `PostfixDeref` lowering: teach LLVM to lower `PostfixDeref` by `sigil` (`@`→array,
`%`→hash) reusing the deref bitcast bodies. EXTEND TypedInvariant for PostfixDeref.
Rewrite R4/R5/R8. Delete `ArrayDeref`/`HashDeref`. Sweep. Commit.

### Phase 2 — aggregate construction onto ArrayRef/HashRef
2.1 Fold `ArrayLiteral`/`MakeArrayRef` → `ArrayRef`; `HashLiteral`/`MakeHashRef` →
`HashRef` per the I4 resolution (one canonical ref-producing constructor; unboxed
`%Array`/`%Hash` is an emitter temp). Teach LLVM to lower `ArrayRef`/`HashRef`; EXTEND
TypedInvariant (elements + the resulting ArrayRef/HashRef repr). Rewrite R1/R4/R5
ir-blocks. Delete the 4 parallel construct nodes. Sweep. Commit.

### Phase 3 — element stores onto Assign-over-lvalue (uses the I1 syntax)
3.0 Add the lvalue-store builder support + `_lower_assign` Subscript-lvalue branch
(I1), with a RED test, BEFORE rewriting any block. Commit.
3.1 Element store: rewrite R6/R7 ir-blocks to `Assign(Subscript-lvalue, value)`; the
LLVM `_lower_assign` element-store path (from 3.0). EXTEND TypedInvariant. Delete
`ArrayWrite`/`HashWrite`. Sweep. Commit.
(Field store moves to the MOP phase, since it shares the classes.md blocks — see C3.)

### Phase 4 — MOP structure (was Phase 5; now BEFORE dispatch, per C3) — DECOMPOSED (C4)
This phase replaces the `ClassDecl`/`MethodDef`/`FieldDef`/`AdjustBlock` node subtree
with the MOP/`ClassInfo` layer the LLVM backend consumes — decomposed so each step
keeps the 7 classes.md cases GREEN independently.
4.0 (I2) Add the `ClassInfo`/`MethodInfo`-as-input builder support; teach LLVM to
CONSUME a `ClassInfo` to build the per-class vtable + object struct + ADJUST order —
WITHOUT yet deleting any parallel node (both paths coexist). RED/GREEN: a graph
carrying class via `ClassInfo` lowers identically to the `ClassDecl`-subtree version.
Commit.
4.1 Replace `ClassDecl` → `ClassInfo` in all 7 ir-blocks (the class anchor); delete
`ClassDecl`. Sweep. Commit.
4.2 Replace `MethodDef` → `MethodInfo` (method bodies via the MOP); delete `MethodDef`.
Sweep. Commit.
4.3 Replace `FieldDef` → `MOP::Field`; field READ stays `FieldAccess`
(field_index+field_stash); delete `FieldDef`. Sweep. Commit.
4.4 Field STORE → `Assign(FieldAccess-lvalue, value)` (carries field_index +
field_stash; F9 dissolves — the `_in_method_body` ambient operand-reinterpret is
removed); EXTEND TypedInvariant; delete `FieldWrite`. Sweep. Commit.
4.5 Replace `AdjustBlock` → `MOP::Phaser::Adjust`; delete `AdjustBlock`. Sweep. Commit.

### Phase 5 — method dispatch & construction onto Call (was Phase 4; now AFTER the MOP, per C3)
Now that the MOP structure exists (Phase 4), method dispatch can resolve from it.
5.1 Method dispatch: teach LLVM to lower `Call(dispatch_kind='method')` via the vtable
slot, resolving the callee from `Call.target` (a `MOP::Method`, now available from the
ClassInfo) or the class registry; EXTEND TypedInvariant (invocant repr = Object) +
bilateral cases. Rewrite the method-call ir-blocks to `Call(dispatch_kind='method')`.
Delete `MethodCall`. Sweep. Commit.
5.2 Construction: rewrite `Empty->new` to `Call(dispatch_kind='method', name='new')`;
move the malloc/vtable/:param/ADJUST lowering under the new-Call arm. Delete `New`.
Sweep. Commit.
(Phases 4+5 land as one entangled SET — a failure in 5 may require reverting parts of
4; they are NOT independently revertible from each other, though each is from the
earlier phases. Stated explicitly per C3.)

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
  **Mitigation:** the perl oracle is unchanged; lli==perl must hold at every
  node-convergence phase; the `behavior` blocks (perl results) are NOT edited — only
  the `ir` blocks.
- **Risk (I7 — optimizer dual-contract):** the corpus ir-blocks are BOTH a lowering
  spec AND the optimizer's output-SHAPE contract (corpus_dual_contract). The
  "behavior blocks unchanged" mitigation only covers BEHAVIOR; the SHAPE contract
  lives in the ir-blocks the convergence rewrites. **Mitigation:** as a FIRST step,
  audit whether any optimizer/codegen test consumes the corpus ir-blocks as a
  SHAPE oracle (not just behavior). Any such test is updated as part of the
  phase-by-phase ir-block rewrite, with the shape-change called out in the commit.
- **Risk:** `Subscript`/`PostfixDeref` are parser-level polymorphic; the repr to pick
  array-vs-hash lowering must be on the container input. **Mitigation:** the corpus
  ir-blocks set it explicitly; an undef-repr container hits G.6's loud-GAP policy (not
  a silent misread). A parser that doesn't set it is a TypeInference gap — filed, not
  silently defaulted.
- **Risk (C4):** the MOP phase (now Phase 4) is large. **Mitigation:** decomposed into
  4.0–4.5, each keeping the 7 cases GREEN; 4.0 establishes ClassInfo consumption
  WITHOUT deleting parallel arms (both coexist) so the cutover is incremental, NOT a
  big-bang. Consumes `ClassInfo` (immutable, id()) WITHOUT wiring the stalled
  MOP-migration internals.
- **Risk (C3):** Phases 4+5 are ENTANGLED (Call dispatch resolves from the MOP that
  Phase 4 builds). **Mitigation:** ordered MOP-before-dispatch; they land as one set
  and are NOT independently revertible from each other (each IS revertible from the
  earlier phases). Stated honestly rather than claimed otherwise.
- **Risk:** large refactor of gate-verified work. **Mitigation:** Phase G hardens the
  gate FIRST (against a G.0 baseline of pre-existing failures); then phase-by-phase
  full sweep + lli==perl after each. Each node phase (0–3) is independently revertible
  to GREEN; the MOP set (4–5) reverts as a unit. **The "independently revertible"
  claim applies PER-PHASE for 0–3 and PER-SET for 4–5 — not uniformly per-commit.**

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

### Node convergence (Finding 1; F9 dissolves in Phase 4.4; F8 fixed in Phase G.7)
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
- **Narrow (cheap, do BEFORE Phase G — I8):** move ONLY `Chalk::IR::Target::LLVM` →
  `Chalk::Target::LLVM` (git mv + package rename + update the 14 `use` lines, all in
  t/), and create `Chalk::Target` as the base (promote `Bootstrap::Target`, leaving a
  compat alias if the 153 Bootstrap consumers still reference the old base; reconcile
  the `generate`-vs-`lower` interface per F2-iface). **Do this FIRST so every Phase-G
  and convergence test is written against the FINAL namespace** — not against
  `Chalk::IR::Target::LLVM` then immediately renamed (I8). Fixes the "LLVM shouldn't
  live under IR" wart; the Perl/C/XS family stays put under a tracked follow-up.
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
