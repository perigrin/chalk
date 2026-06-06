# Adversarial Review: Phase 1 NOT-YET-COVERED Audit

**Date**: 2026-06-06
**Reviewer role**: skeptic / plan-vs-code verifier (read-only)
**Document under review**: `docs/plans/2026-06-06-phase1-not-yet-covered-audit.md`
**Question**: Is the 1a/1b/1c decomposition safe to turn into git-zhi child issues as-is?

**Bottom line up front**: **NOT safe as-is.** The bucket *counts* are roughly
right and bucket-1 (data-only) is genuinely tractable — I verified three of its
riskiest members end-to-end against real `perl`. But the audit's bucket-2
("CFG") analysis is built on the **wrong code path**: it describes the
`cfg_state` / `emit_cfg_if` / `true_proj`-`false_proj` machinery, which the
hand-graph harness **never executes**. The harness path is MOP → `generate` →
`_generate_from_schedule` → `Chalk::IR::Scheduler::EagerPinning` → schedule
items. Every "IR Structure" diagram and every "line 1327 / line 1403" emitter
citation in bucket-2 points at dead-on-this-path code. The real bucket-2 work
is *schedule_data* construction (`EagerPinning::If/Loop/TryCatch`) plus
`control_in`/`set_region`/`head` chain wiring — different, and not described
anywhere in the audit. That is the single biggest risk to the decomposition.

---

## Evidence base

Read in full: the audit; `gap-map.json`; `ir-audit-corpus.pl` (all 78 idiom
sources); `HandGraphs.pm` (the 5 working builders); `Target/Perl.pm` (emitter +
both emit paths); `Scheduler/EagerPinning.pm` and the `EagerPinning::If/Loop`
schedule-meta classes; `Harness.pm`, `PerlDriver.pm`, `Comparator.pm`; the IR
node classes (`VarDecl`, `Ref`, `UnaryOp`, `AnonSub`, `If`, `Loop`, `Region`,
`Phi`, base `Node`); `Actions.pm` unary/increment construction.

Ran three live probes under `perl 5.42.0` (`A2`, `H1`, `M19`) through the real
`Target::Perl->generate` to test the "mechanical" claim with perl as oracle.

---

## Per-claim verdicts

### CLAIM 1 — "BUCKET-1 (41) is purely mechanical, hand-graph only, all emitters exist."
**Verdict: VERIFIED (with two re-bucketings INTO bucket-1, and calibration notes).**

The harness drives a MOP through `_generate_from_schedule`. For a body with no
top-level control node, the scheduler produces a flat list of `stmt` items and
each expression/Return is emitted by `_emit_node`/`_emit_expr`. That is exactly
the A1/A4/A5/E1/F3 pattern. I confirmed three of the *riskiest* bucket-1 members
actually emit behaviorally-correct Perl:

- **A2** (`my @list = (1,2,3); return scalar @list`): generated
  `my @list = (1, 2, 3); return scalar(@list);` — returns 3. PASS.
- **H1** (map BLOCK): generated `my @r = map { $_ * 2; } 1, 2, 3; return scalar(@r);`
  — returns 3. PASS. **The block body is NOT scheduler/Region/Phi work**: an
  `AnonSub` node carries its body as a plain `inputs[1]` statement array, and
  `_emit_builtin_call` / `_emit_anon_sub_expr` emit each body stmt via
  `_emit_node`. So **H1–H4 (map/grep/sort/anon-sub) are correctly bucket-1** —
  my initial suspicion that they were secretly bucket-2 is **refuted by direct
  evidence**. The one caveat: an AnonSub body that itself contained control flow
  would break (it bypasses the scheduler), but no H-group corpus body does.
- The G group (deref/subscript) and M3/M4 (interpolation) read straightforward
  inputs layouts; interpolation needs the author to split the literal into
  Constant parts (variable vs literal), marginally more than A2 but still
  data-only.

Calibration correction to the audit's "~30 LOC, identical to A1" framing: the 5
existing builders are linear `Start → VarDecl → Return` chains. Several bucket-1
members need an extra idiom the audit glosses: aggregate-var return values use
the `scalar(@x)` builtin-call shape (as F3 does for `foo`), and the author must
remember to set `const_type => 'variable'` vs `'string'` correctly (this is the
exact bug class that bit E1 historically). These are still mechanical but they
are *copy-from-F3*, not *copy-from-A1*. Budget accordingly.

**Re-bucketing INTO bucket-1 (see Claim 4): M10, M11.** They are not emitter
gaps. See below.

### CLAIM 2 — "25 control idioms collapse to ~6 CFG patterns; solving 1,3,4 unlocks 13."
**Verdict: WRONG (as written) — analysis targets a code path the harness never runs.**

The audit's bucket-2 is grounded entirely in the `cfg_state` side-table path:
`emit_cfg_if` ("line 1327"), `emit_cfg_loop` ("line 1403"), `true_proj`/
`false_proj`, "wire cfg_state with if_node/then_stmts/else_stmts". I traced the
harness:

- `PerlDriver->run` calls `Target::Perl->generate($mop)`.
- `generate` on a `Chalk::MOP` calls `_generate_from_schedule` (Perl.pm:78-79).
- That runs `Chalk::IR::Scheduler::EagerPinning->schedule($method)` and emits
  schedule items via `_emit_schedule_item`.
- `_generate_with_cfg` / `emit_from_cfg_state` / `emit_cfg_if` / `emit_cfg_loop`
  are reachable **only** from `_emit_program` on a `Chalk::IR::Program` with a
  parser-supplied `$sa`/`$ctx` (Perl.pm:494-496). The hand-graph harness has no
  Program and no `$sa`/`$ctx`. Those methods are dead on this path.

So the *real* bucket-2 contract is: build `If`/`Loop`/`TryCatch` IR nodes, call
`set_region`/`set_control_in` so the scheduler's backward chain-walk
(`schedule`, EagerPinning.pm:57-89) reaches them through `control_in` and
`Region->head`, and attach `set_schedule_data(EagerPinning::If->new(then_stmts
=>…, else_stmts=>…))` / `EagerPinning::Loop->new(body_stmts=>…, iterator=>…,
list=>…))`. The good news the audit accidentally gets right: branch/loop bodies
live in *arrays* on schedule_data (`then_stmts`/`else_stmts`/`body_stmts`), so
**no real Region+Phi data-flow threading is required to emit branch bodies** —
the value-merge Phi machinery the audit draws is not needed for these corpus
idioms at all. That makes bucket-2 *more* tractable than the audit's diagrams
imply, but for a completely different reason than the audit states.

"Solving patterns 1,3,4 unlocks 13" is therefore **asserted, not real**: the
structural sharing the audit claims is sharing among `cfg_state` shapes that
won't be built. The genuine sharing axis is "one schedule_data builder per
control node type" (If, Loop, TryCatch) — about **3** builders, not 6 patterns —
plus per-idiom body wiring. The "13" number should be discarded.

One concrete latent gap the wrong-path analysis hides: **M17/M18 (`next if`/
`last if`).** The `is_loop_jump` shortcut that emits `next if COND` lives only in
the `cfg_state` `_emit_node` branch (Perl.pm:629-635) and in `EagerPinning::If`'s
`is_loop_jump` field — which **nothing in the scheduler/`_emit_schedule_item`
path ever reads.** Via the scheduler an `is_loop_jump` If emits as a full
`if (COND) { next; }` block. That is *behaviorally* correct (and `next`/`last`
bare Constants are handled at Perl.pm:668), so M17/M18 are still achievable — but
not the way the audit describes, and the `is_loop_jump` field is dead code on
this path.

### CLAIM 3 — week estimates ("1 week" / "2-3 weeks" / "1-2 weeks").
**Verdict: OVERSTATED / decorative.** This is an AI-driven process; calendar
weeks measure nothing here. Worse, the LOC estimates inherit the wrong-path
error: "600-800 LOC (6 CFG patterns)" is sized against `cfg_state` wiring that
won't be written. The honest unit of uncertainty is **distinct construction
recipes**, not idioms or weeks:
- bucket-1: ~1 recipe (linear chain) with ~4 sub-variants (scalar-wrap,
  interpolation-parts, anon-sub-body-array, aggregate subscript). Low risk.
- bucket-2: ~3 recipes (If, Loop, TryCatch schedule_data + chain wiring),
  proven to exist (see `t/bootstrap/scheduler/schedule-data-*.t`) but never
  exercised from a *hand* graph. Medium, with one unknown: getting
  `_pick_outer_return` + Region/head walk to terminate correctly on
  hand-built multi-Return bodies (E2/E3 have two Returns).
- bucket-3: 1 genuine unknown (M19), the rest trivial or non-issues.
Strip the week columns from the child issues; they will anchor wrong.

### CLAIM 4 — bucket-3 "6 emitter gaps".
**Verdict: OVERSTATED in aggregate; one item (M19) is a buried deep unknown,
two items (M10/M11) are non-issues, two (B8/K2) are not gaps.**

- **M10/M11 (`\@list`, `\%hash`) — NOT a gap; move to bucket-1.** The audit
  worries the "Ref emitter path is unclear." It isn't. `Actions.pm:2017` builds
  every unary (including `\` → `Ref` via `%UNOP_MAP`) as
  `inputs => [op_const, operand]`, which is exactly the layout `_emit_unary_expr`
  reads (`inputs[0]->value()` = op, `inputs[1]` = operand). A Ref hand graph
  built that way emits `\@list` correctly; the follow-on `$r->[0]` is data-only.
  The `UnaryOp.operand` field and `op_str()` method are simply unused by the
  emitter — no conflict. Re-bucket M10/M11 to 1a.
- **B8 (`warn`) — real but trivial.** Not in the no-parens list (Perl.pm:1297);
  emits `warn("hi")`. Behaviorally identical to `warn "hi"` for the corpus.
  **But note the Comparator compares `stderr` *exactly* (Comparator.pm:79)** —
  `warn "hi"` appends `" at … line N."` to stderr in both S and P, so as long
  as both run the same warn it matches. The 1-line fix is correct; keep it.
- **K2 (`$i++`) — NOT blocked for this corpus.** Audit says "K2 cannot PASS
  until a PreIncrement/PostIncrement node lands." False for the actual corpus
  idiom: `my $i = 0; $i++; return $i;` returns 1 whether emitted as `$i++` or
  `$i += 1` (which is what CompoundAssign yields). Pre/post distinction is
  *invisible* unless the increment's own value is consumed in-expression, which
  this corpus never does. K2 is a mechanical bucket-1 win today. (The deferred
  typed node remains correct as a *general* statement, just not needed here.)
- **D6 (ternary) — bucket-1, not a question.** Corpus is
  `my $x = $n > 0 ? 1 : 2;` — a pure expression. `_emit_ternary_expr` exists and
  `TernaryExpr` is dispatched in `_emit_expr` (Perl.pm:983). Mechanical. The
  "ternary-as-control" speculation is a non-problem; drop it.
- **M19 (`my ($a,$b) = (1,2)`) — VERIFIED deep unknown; UNDER-rated, not over.**
  I probed it: there is **no IR node** for list/tuple declaration (`ls
  lib/Chalk/IR/Node/` confirms VarDecl/Assign/ExpressionList only; no
  MultiAssign/destructuring). The only hack — stuffing `($a, $b)` into the
  VarDecl name Constant — produces `my ($a, $b) = [1, 2];` (probe output), which
  **miscompiles**: `$a` gets the arrayref, `$b` is undef. `_emit_init_expr`'s
  list-flattening is keyed on a leading `@`/`%` sigil (Perl.pm:1016/1025), which
  a `($a,$b)` name never matches. M19 needs a new IR node or a real emitter
  change, plus list-context init handling. This is the worst hidden risk and it
  is mis-filed as one of "6 idioms, parallel, low-priority."

### CLAIM 5 — bucket-4 = 0 (nothing out-of-subset).
**Verdict: OVERSTATED — at least M20/M21 are unresolved scope decisions, not
codegen work.** The audit itself flags `do {}` (M20) and `eval {}` (M21) as
"design TBD … may defer to Phase 2" inside bucket-2, then reports bucket-4 = 0.
That is double-counting them as in-scope. Note MEMORY records the project
explicitly excludes `eval` in all forms in favor of `try`/`catch`
("try/catch, not eval blocks"). `eval { }` (M21) is therefore plausibly
**out-of-subset by an existing project decision**, and `do { }` as an
expression has no IR representation today (the audit admits "UNCLEAR — requires
design spike"). These belong in a scope-decision bucket, not silently inside
"control flow we'll wire." Zero is not credible; the honest count is at least
2 scope-decisions (M20, M21).

### CLAIM 6 (meta) — does 1a/1b/1c reduce risk or front-load easy wins?
**Verdict: OVERSTATED.** The split *does* cleanly isolate the genuinely-easy 41,
which is real value. But "tractable, not open-ended" is a hopeful gloss for two
reasons: (1) **all the real risk is concentrated in 1b**, and 1b's entire
technical description is wrong-path, so the issue text would mislead whoever
picks it up; (2) **1c hides M19**, the one item that may need new IR, behind
five non-problems (M10/M11/B8/K2/D6 are either bucket-1 or trivial). Front-
loading 1a manufactures visible green (46/78) while the two things that can
actually stall Phase 1 — scheduler-based control construction and M19 — are
described inaccurately and buried respectively. That is exactly the 80%-then-
drift pattern CLAUDE.md warns about.

---

## Mis-bucketed idioms (corrected)

| Idiom | Audit bucket | Correct bucket | Why |
|-------|--------------|----------------|-----|
| M10 `\@list` | 3 (emitter gap) | **1 (data-only)** | Ref builds as `inputs=[\,operand]`; `_emit_unary_expr` already correct. Probe-adjacent: parser path proven in Actions.pm:2017. |
| M11 `\%hash` | 3 | **1** | Same as M10. |
| K2 `$i++` | 3 (blocked) | **1** | CompoundAssign `$i+=1` is behaviorally identical for the corpus; return value independent of pre/post. |
| D6 ternary | 3 (clarify) | **1** | Pure expression; `_emit_ternary_expr` + dispatch exist. |
| M17/M18 next/last | 2 (loop_jump pattern) | 2, **but recipe is If-with-`next` body via scheduler**, NOT the `is_loop_jump`/`_emit_loop_jump` path (dead on harness path). |
| M20 do / M21 eval | 2 (control) | **4 (scope decision)** | No IR for `do`-as-expression; `eval` excluded by project policy. Decide scope before coding. |
| M19 tuple-assign | 3 (one of 6) | **own spike** | No tuple/list IR node; naive emission miscompiles (verified). |

Net effect on counts: bucket-1 ≈ **45** (41 + M10, M11, K2, D6), bucket-2 ≈ **21**
(25 − D6 − M19 − M20 − M21, with M17/M18 recipe corrected), bucket-3/scope ≈
**B8 (trivial) + M19 (spike) + M20/M21 (scope)**.

---

## Worst hidden risk (ranked)

1. **Bucket-2 is documented against the wrong emitter path.** Anyone starting 1b
   from this doc will try to populate `cfg_state` and call `emit_cfg_if`, which
   the harness never invokes, and lose time discovering the scheduler path. This
   is the highest-leverage correction. The 1b issue must be rewritten around
   `Chalk::IR::Scheduler::EagerPinning` + `EagerPinning::If/Loop/TryCatch`
   schedule_data + `set_region`/`set_control_in`/`head` wiring, with the existing
   `t/bootstrap/scheduler/schedule-data-*.t` tests cited as the construction
   reference.
2. **M19 is a possible new-IR-node requirement buried as "low-priority."** A
   single new node type / emitter change is more Phase-1-blocking than all 45
   bucket-1 idioms combined. Give it its own spike issue.
3. **Comparator compares stderr and exception messages exactly.** "Emitter
   exists" ≠ "S=P". Any idiom that warns (B8), prints, or dies (B4, E4, M12)
   passes only if the *byte-exact* stderr/exception text matches the oracle.
   Bucket-1 builders for these must be validated against perl, not eyeballed —
   the same way E1 once emitted plausible-but-wrong output.
4. **Hand-built multi-Return bodies (E2/E3) lean on `_pick_outer_return`
   heuristics** (EagerPinning.pm:98-145) that have only ever run on
   parser-produced graphs. Hand graphs must satisfy the deepest-chain heuristic
   or the wrong Return becomes the method exit. Flag as a 1b sub-risk.

---

## Is it safe to turn into git-zhi 1a/1b/1c child issues as-is?

**No. Two required revisions before decomposition; two recommended.**

**Required:**
- **R1. Rewrite the 1b technical body around the scheduler path.** Remove all
  `cfg_state` / `emit_cfg_if` / `true_proj`-`false_proj` / "line 1327/1403"
  references. Replace with: build If/Loop/TryCatch nodes, `set_schedule_data`
  with `EagerPinning::If/Loop/TryCatch`, wire `control_in`/`set_region`/`head`,
  stash branch/body stmts in `then_stmts`/`else_stmts`/`body_stmts`. Cite
  `t/bootstrap/scheduler/schedule-data-*.t` as the recipe. Recast "6 patterns /
  unlock 13" as "3 schedule_data recipes (If/Loop/TryCatch) + per-idiom body
  wiring."
- **R2. Pull M19 out of 1c into its own spike issue** titled e.g. "tuple/list
  declaration: new IR node or list-context VarDecl init." Include the probe
  finding (`my ($a,$b) = [1,2]` miscompile) as the motivating evidence.

**Recommended:**
- **R3. Re-bucket M10, M11, K2, D6 into 1a** (data-only). Shrinks 1c to B8
  (trivial) and clears phantom risk. Re-label M17/M18's recipe note.
- **R4. Add an explicit scope-decision issue for M20 (`do`) and M21 (`eval`)**
  before any coding; do not carry them as in-scope control flow. Reconcile M21
  with the existing "no eval" project decision. Correct bucket-4 from 0.

With R1–R4 applied, the decomposition is sound and the "tractable" verdict is
defensible — but only because bucket-1 is genuinely easy (verified) and bucket-2
is easier-than-drawn for a reason the audit didn't identify, not because the
audit's risk map is correct.

---

## Files / evidence cited
- `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` — `generate`:78; `_generate_from_schedule`:91;
  `_emit_schedule_item`:251; scheduler-path `_emit_node`:621 (loop_jump only at 629-635);
  `_emit_unary_expr`:1044; `_emit_init_expr`:1014; `_emit_builtin_call`:1273 (no-parens list 1297);
  `_generate_with_cfg`:494 (requires Program); `emit_cfg_if`:1327 / `emit_cfg_loop`:1403 (dead on harness path).
- `lib/Chalk/IR/Scheduler/EagerPinning.pm` — `schedule` chain-walk:57; `_pick_outer_return`:98; `_expand_if/_loop/_try`.
- `lib/Chalk/Scheduler/EagerPinning/{If,Loop}.pm` — then/else/body_stmts, is_loop_jump (unread on harness path).
- `lib/Chalk/CodeGen/Harness/{Harness,PerlDriver,Comparator}.pm` — harness drives `generate(MOP)`; Comparator exact stderr/exception axes.
- `lib/Chalk/IR/Node/` — no tuple/multi-assign node; `Ref` isa `UnaryOp`; `AnonSub` body via inputs.
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — `%UNOP_MAP` (`\`→Ref):72; `UnaryExpression` inputs layout:2017; Pre/PostIncDec → CompoundAssign:2311.
- Live probes under perl 5.42.0: A2 (PASS), H1 map-block (PASS), M19 (MISCOMPILE: `my ($a,$b) = [1,2]`).
