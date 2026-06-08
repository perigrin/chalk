# Architecture Report — Chalk Target/IR Layer

**Date:** 2026-06-08
**Commit:** a8a176478a1897912bf78f2ea536d7887c5f9cbd
**Languages:** Perl 5.42 (feature class), LLVM IR (emitted)
**Key directories:** lib/Chalk/IR/Target/, lib/Chalk/IR/Node/, lib/Chalk/IR/Graph/,
lib/Chalk/MOP/, lib/Chalk/Bootstrap/*/Target/, t/lib/Chalk/CodeGen/Harness/
**Scope:** the target/IR layer as built by the G2–G5 runtime-free GAP-clearing
campaign (commits 3435b75a..5f6a9f63) + its design docs.
**Method:** 5 parallel specialists (structure, coupling, typed-IR, error/GAP
discipline, coverage/dead-code) + a verifier pass on the severe new findings.

## Executive verdict

- **Findings 1 & 2 (node-taxonomy drift, target namespace): CONFIRMED, and the
  reconciliation plan's direction is correct.** No node is mis-classified by the
  plan; the canonical surface (`Call`+dispatch_kind, `FieldAccess`, `Assign`,
  `Subscript`) is structurally ready to absorb the parallel tier; `Chalk::IR::Target`
  is a genuine layering inversion (a consumer inside the IR namespace) and
  `Chalk::Target::*` is the right home.
- **The review surfaced 6 NEW latent hazards the campaign's gate missed** — because
  the corpus doesn't yet trigger them. All 6 verified. **None is an active
  miscompile today; all are real defects-in-waiting**, and two (V3, V4) are
  gate-integrity flaws that weaken trust in every GREEN/GAP the harness reports.
- The functionally-correct, gate-verified campaign behavior (4 corpus files GREEN,
  lli==perl, libperl-free for the cases tested) STANDS. These findings are about the
  robustness of the guards and the cleanliness of the structure, not a broken build.

## Strengths (protect these)

### [S1] repr-out-of-content_hash discipline holds everywhere — High
Verified across all 22 node subclasses: none folds `representation` into
`content_hash`. `Node.pm:41-52,92-94`. Value identity is never split by a lowering
decision — the typed-SoN model done right. *(typed-IR + structure specialists)*

### [S2] Coerce is a clean, hash-distinct, explicit-on-edge node — High
`Coerce.pm:24-29` — `from`/`to` in content_hash, parameterized (not sub-kinded);
LLVM materializes each as a visible conversion. Resolves typed-ir-representation.md's
own open questions Q2/Q3 exactly as the doc planned. NOT drift. *(coupling + typed-IR)*

### [S3] Stable, acyclic dependency direction; no production→test dependency — High
Target → IR → MOP is acyclic; IR never names a target (0 hits). No `lib/` → `t/lib/`
dependency (the LLVM backend consumes hand-authored/MOP graphs, never the untrusted
parser/SA path). `LLVM.pm:7-9`. *(coupling specialist)*

### [S4] NodeFactory two-class discipline survived the G4/G5 proliferation — Med
Hash-consed data nodes vs per-position CFG nodes, with documented routing for
side-effect nodes; LLVM constructs zero nodes (pure reader). `NodeFactory.pm:96-124,
249-288`. *(structure + coupling)*

### [S5] The GAP-vs-MISCOMPILE taxonomy + type-tag oracle is a strong error model — High
`Comparator.pm:38-234` decides GAP first (can't be laundered), MISCOMPILE never
backlog, with coverage + empty-record + F7-identity guards. TypeTag makes `Bool:`
vs `Str:` distinct (catches the string-blind miscompile class). The model is
well-designed — its defect is *non-uniform enforcement* (see F5/F6), not the model.
*(error-discipline specialist)*

### [S6] Adversarial loud-failures + constructive corpus spec — High
MethodCall-on-absent-method/undeclared-class die loudly at lowering (verified);
OOB-read/missing-key → Undef; honest `L: GAP` is a test-enforced verdict; the
corpus ir-blocks are executable (`build_graph_from_ir`), not commentary. *(coverage)*

## Flaws / Risks (severity-ranked; all verified)

### [F1] Two disconnected IR tiers; the backend lowers only the parser-unreachable one — High (KNOWN = Finding 1)
`LLVM.pm` dispatch (~1047-1201) has arms for the 18 parallel G4/G5 nodes and **zero**
arms for canonical `Subscript`/`PostfixDeref`/`ArrayRef`/`HashRef`/`Call`/`Length`,
which the parser DOES emit (`Actions.pm` make() ×many). `Length` is fully dead (no
producer, no arm); `ScalarLen`/`MakeArrayRef`/`MethodCall`/etc. duplicate canonical
nodes. **This is the reconciliation plan's central diagnosis — confirmed.** The plan
correctly labels element/field store (ArrayWrite/HashWrite/FieldWrite) as
genuinely-new *behavior* (→ Assign-over-lvalue), which is new modeling work, not a
mechanical deletion. *(structure, coupling, coverage all agreed)*

### [F2] Target-namespace layering inversion — High (KNOWN = Finding 2)
`Chalk::IR::Target::LLVM` is a consumer packaged inside the IR namespace; the other
targets are `Chalk::Bootstrap::*::Target::*`. Decided: common `Chalk::Target::*`.
Narrow move (LLVM, 14 test-side refs) carries near-zero risk (S3 holds). **Also: the
two target families have DIVERGENT interfaces** — `Bootstrap::Target` defines
`generate($ir)`; `IR::Target::LLVM` exposes `lower($return_node)` and does NOT inherit
the base. When `Chalk::Target` becomes the base, this interface divergence must be
reconciled (`Target.pm:7-15` vs `LLVM.pm:46`). *(coupling specialist — F3)*

### [F3] Harness launders a lowered-but-lli-rejected `.ll` as a passing GAP — High (NEW, verified)
`LLVMDriver.pm:105` sets `emitted_for_every_construct=(lli_exit==0)`;
`MdtestCorpus.pm:1115` maps `!emitted → GAP`. So a graph that LOWERS but emits
malformed IR (lli rejects, nonzero exit) is classified GAP — and a GAP-declared case
with a buildable graph would PASS. `LLVMGapMap.pm:779` does the OPPOSITE
(`lli_exit!=0 → MISCOMPILE`). **The two harnesses contradict; the corpus gate never
emits the MISCOMPILE label.** Defeats "MISCOMPILE never backlog" — the single most
load-bearing discipline. **Latent only because every current GAP-declared block is
pure-GAP (no buildable graph), so the branch isn't exercised — one corpus edit away.**

### [F4] No mechanical libperl-free guard on corpus GREENs — High (NEW, verified)
`MdtestCorpus._run_l_verdict_check` classifies GREEN without ever grepping the `.ll`
for libperl symbols. The assertion exists only as per-`.t` `unlike(...)`: **absent
from increment.t, regex.t, variables.t, classes.t (comment only), subs.t (comment
only)** — 5 of 12 files, including classes.t (the highest-risk G5 MOP file) — and
inconsistent where present (some check only `/Perl_/`, missing `sv_`/`AV`/`HV`/`PL_`).
A libperl leak in those GREENs would ship uncaught. The runtime-free premise — the
whole point of the LLVM forcing-function — is not mechanically guaranteed on the
cases that count.

### [F5] TypedInvariant covers 6 ops; every G3–G5 op is unchecked — High (NEW, verified)
`TypedInvariant.pm:15-22` `%OP_REQUIRED_REPR` = Add/Subtract/Multiply/Divide/Modulo/
Concat only. ArrayRead/ArrayWrite/HashRead/HashWrite/MethodCall/New/FieldWrite/
FieldAccess + all comparisons + all logical ops are UNCHECKED, and it's the ONLY
operand-rep guard — `_lower_array_read` (2847+) GEPs `inputs[0]` as `%Array*` with no
Object/Array-rep check; `_lower_method_call` (3450+) bitcasts the invocant to the
object struct without checking it's an Object rep. A mistyped operand passes the
invariant and reaches a type-mismatched GEP/bitcast. **Latent** (corpus operands are
correctly typed); the "hand graph IS an auditable spec" claim holds only for the 6
listed ops. Fix is mechanical (extend the table + well-typed-graph.t cases).

### [F6] method-body `_need_*` flags not propagated → undeclared-global IR — High (NEW, verified)
Method bodies lower in a DISTINCT `$body_ctx` (`LLVM.pm:459`); only
`_need_malloc_memcpy`/`_need_strpair` propagate up (514-515). A method body doing
`Coerce(Bool->Str)` / `Coerce(Str->Num)` / a hash-key compare sets
`_need_bool_str_globals`/`_need_str_to_num_helper`/`_need_memcmp` on `$body_ctx`,
which the prologue (698-760) never reads (and runs BEFORE the bodies lower anyway).
Result: `.ll` referencing undeclared globals/helpers that lli rejects. **This is the
SAME silent-stub class the reconciliation already found for Coerce(Bool->Str), one
scope deeper.** Latent — current classes.md method bodies don't use those ops; a
`:reader` returning a stringified bool, or a method doing `$str+0`, would trigger it.

### [F7] `representation // 'Int'` defaulting bypasses the Scalar-GAP guards — Med (NEW, verified)
~19–21 sites use `my $repr = $node->representation // 'Int'`. An undef-repr node is
silently lowered as i64 BEFORE the `repr eq 'Scalar' → die` check runs;
`_lower_constant` (1209-1217) emits an undef-repr integer-looking Constant as
`add i64 0, $val` with no GAP. TypedInvariant waves undef through too (no backstop).
**Latent defense-in-depth weakness** (corpus nodes all carry explicit reps), but it
masks a class of upstream type-inference bug as plausible integer output.

### [F8] Truthiness coercion (`*→Bool`) done inline, hardcoded i64 — Med (NEW, verified)
`_lower_and` (1967) / `_lower_or` (2010) hardcode `icmp ne i64 …, 0`, assuming Int
operands; `_lower_not`/`_ensure_i1` emit truthiness inline. This violates
typed-ir-representation.md §2 ("coercion is a visible node") and is a latent
miscompile if a Bool(i1)/Num(double) operand hits `&&`/`||` (type-mismatched icmp,
lli-rejected). Note `_lower_coerce` DOES model `*→Bool` as an explicit node — so
there are TWO implementations of the same coercion, one on-graph, one inline.
**Latent** — current logical.md And/Or operands are all `:Int`.

### [F9] FieldWrite/FieldAccess meaning depends on ambient `_in_method_body` state — Med (NEW)
The same node shape means different operand interpretations selected by emitter state
(`_in_method_body`, `_method_class_name`), set via `local` on `$body_ctx`. FieldWrite
dropped `field_stash` (canonical FieldAccess carries it) and pushed the class into
mode-flags + three `_lower_field_write*` variants. Order-dependent ambient state that
leaked into the node's data model. The reconciliation plan's Phase 3 (field store →
Assign-over-FieldAccess-lvalue) is the intended fix. *(coupling + structure)*

### [F10] LLVM.pm Context package bundles 4 separable responsibilities + a duplication seam — Med
The 2831-line `Context` package mixes block-emission primitives, per-node lowering,
control-flow processing, and the G4/G5 aggregate/MOP lowering. `_process_if_node` /
`_wire_region_phis` exist in BOTH `Context` and `ElaboratedContext`
(copy-paste-with-divergence). Not a god-object by tangle, but the seams are
separable; worth a split once the reconciliation deletes the parallel arms. This
control-processor duplication is pre-existing and orthogonal to G4/G5 — track
separately. *(structure specialist)*

### [F11] No parser→graph→LLVM equivalence test — Med (NEW, the dual-contract's unguarded leg)
The corpus is the SOLE producer of the parallel tier; the parser emits the canonical
tier; **no test compares them.** A parser wired to LLVM today would mismatch by
construction and nothing would fail. The reconciliation's convergence is what
finally wires parser-shape nodes to LLVM — so the plan MUST add a parser-equivalence
gate as its acceptance criterion, or the divergence ships silently at that moment.
*(coverage specialist)*

## Open-questions status (the live doc questions)

| Question (doc) | Status | Recommendation |
|---|---|---|
| typed-ir Q1 — representation lattice members | **Answered by campaign, NOT written back** — LLVM dispatches on 11 reprs (Bool/Str/Slot/Array/Hash/Object/Undef/…); Str `encoding` + Slot `{defined,payload}` are load-bearing but undocumented | Write the realized lattice into typed-ir-representation.md; the lattice is "defined only by grepping the backend" today |
| typed-ir Q2/Q3 — Coerce node-vs-edge, parameterized | **Answered (node, parameterized)** — strike from the doc's open-questions | Doc-staleness fix |
| runtime-free-boundary Q1 — ref-address/hash-order normalization | **Genuinely open** — G4 hashes don't iterate (R-cases single-key); ref-address stringification unaddressed | Decide when iteration/ref-stringify idioms land |
| runtime-free-boundary Q3 — Num→Str exact formatting | **Partially answered** (inf/nan/-Inf slice done in strtod follow-up); %.15g/neg-zero/very-large unvalidated | Validate when Num→Str idioms broaden |
| runtime-free-boundary Q4 — regex DFA-core vs OOS tail | **= the G6 scope decision** (spiked, paused) — feature ladder + lib/ census done | Resolve via the G6 Option-B-vs-C decision |
| runtime-free-boundary Q5 — overload/tie literal-class | **Partially answered** — not used by lib/; G5b deferred with the unified vtable-slot model captured | Resolve if/when overload/tie is taken up |
| three-axis Q4 — tier-3/capstone serial vs parallel with LLVM axis | **Genuinely open** | A sequencing decision for after the reconciliation |

## Doc-update list
1. `typed-ir-representation.md` — strike answered Q2/Q3; write the realized
   representation lattice (Bool/Str{ptr,len,encoding}/Slot{defined,payload}/Array/
   Hash/Object/Undef) into the model (closes Q1's silent drift).
2. `ir-lowering.md` — never mentions the LLVM target / `Chalk::Target`; describes
   only Bootstrap-namespaced Perl/XS/C. Update to the `Chalk::Target::*` layer.
3. `sea-of-nodes-ir.md` — document the canonical aggregate/call/field nodes as the
   single vocabulary + the element/field-store = Assign-over-lvalue model (per the
   reconciliation plan's outcome).
4. `llvm-target.md` — already updated this session (cites the three-axis doc). ✓

## Hotspots
1. `lib/Chalk/IR/Target/LLVM.pm` — F1 (parallel-tier arms), F6/F7/F8 (silent
   hazards), F10 (Context cohesion). The center of both the drift and the hazards.
2. `t/lib/Chalk/CodeGen/Harness/{LLVMDriver,MdtestCorpus,LLVMGapMap}.pm` — F3/F4
   (gate-integrity: GAP-laundering + no central libperl guard + contradictory
   harnesses). The gate itself needs hardening.
3. `lib/Chalk/IR/Graph/TypedInvariant.pm` — F5 (the well-typed-graph guard covers 6
   of ~20 ops; the largest groups are unchecked).

## Next questions
1. Should the reconciliation plan ADD gate-hardening (F3 unify GAP/MISCOMPILE across
   harnesses; F4 central libperl-free guard; F5 extend TypedInvariant; F11 parser
   equivalence) as a Phase 0, since these defects survive — and could worsen — a
   pure node-convergence?
2. Is the corpus-as-sole-producer (no parser yet) acceptable until the reconciliation
   wires the canonical nodes, or does F11 warrant an interim guard now?
3. For F6/F8/F7 (latent silent-IR hazards): fix in the reconciliation (they
   disappear when lowering routes through canonical nodes + a complete invariant), or
   patch independently now since they're latent-but-real?
4. Does the `Context`/`ElaboratedContext` control-processor duplication (F10) get
   addressed in this work or tracked as its own cleanup?

## Analysis metadata
- Agents: 5 specialists (structure, coupling, typed-IR/representation, error/GAP
  discipline, coverage/dead-code) + 1 verifier.
- Raw findings: ~30 across specialists; verified/deduped to 11 flaws + 6 strengths.
- New (beyond the 2 known findings): 6 hazards, ALL verified, ALL latent (no current
  corpus case actively miscompiled) — gate-integrity (F3/F4), invariant coverage
  (F5), undeclared-global (F6), defaulting/inline-coercion (F7/F8), equivalence (F11).
- Steering files consulted: CLAUDE.md, the memory files, the 8 design docs.
