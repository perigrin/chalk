# Agentic Code Review: phase1-lateral-bindings (WHOLE BRANCH vs pu — Phase-4-readiness)

**Date:** 2026-06-13 13:47:41
**Branch:** phase1-lateral-bindings -> pu
**Commit:** aee6d5c89ba11a0ea057fb8ca1c25c756d717b90
**Files changed:** 125 | **Lines changed:** +12840 / -3358
**Diff size category:** Large

**Scope:** the integrated whole — R1 (Target namespace) + R2/R3 (node
convergence + taxonomy deletion) + G6/G7 (regex + host) + 019eb316
(value-cache/statement-identity family) + 019eb42a (LLVM-reads-MOP-direct +
seal) + 019eb6ff (cache/identity follow-ups, the Phase-4 Gate 0). Each piece
had a per-issue review with fixes applied (paad/code-reviews/*). This review
hunts the CROSS-ISSUE SEAMS those per-issue reviews could not see, plus the
genuinely-new lightly-reviewed surface (TypedInvariant +99, the namespace
base classes, the corpus harness rewrite).

**Method note:** the parallel-subagent + verifier technique was followed in
spirit, but the Agent/Task dispatch tool is unavailable in this environment;
the specialist lenses (Logic-A/B, Error/Edge, Contract, State, Security, Plan
Alignment) and the Verifier pass were executed inline by one reviewer. Every
asserted bug was confirmed by BUILDING A SMALL GRAPH and running it through
`Chalk::Target::LLVM->lower()` + lli against a perl oracle, or rejected when
the probe disproved it. Probes are at /tmp/probe_*.pl.

## Executive Summary

The branch is **sound to start Phase 4 (B::SoN) on top of.** The full ir/ +
corpus + serialize suites are green (34 LLVM tests, 14 corpus/serialize tests,
seal.t — all pass), the three known G.0 baseline failures are pre-existing and
on untouched goldens, and the heavily-reviewed fix families (value-cache
staleness, statement-effect per-call identity, MOP-direct + seal, inheritance
flatten, alias allocation) were each independently re-verified GREEN by
executable probe at the integrated HEAD — including cases the per-issue
reviews left as filed follow-notes (postfix-deref-after-reassign is actually
CORRECT here; identical-ArrayRef aliasing is fixed end-to-end).

ONE cross-issue seam is a genuine, non-pre-existing finding: the 019eb6ff
identity table widened `%STATEMENT_EFFECT_OPS` to nine ops, three of which
(`NotMatch`, `BacktickExpr`, `TryCatch`) have NO `lower_value` case — so a
statement-position occurrence of any of them is now COLLECTED by the control
collectors and routed to `lower_value`, which dies with a generic non-GAP
message. Latent today (no parse path feeds LLVM), loud not silent — but it is
exactly the class of input Phase 4 will flush (real lib/ is try/catch-heavy),
so it is an Important Phase-4-readiness gap, not a Suggestion.

## Critical Issues

None found.

## Important Issues

### [I1] Three statement-effect ops (NotMatch, BacktickExpr, TryCatch) are collected but have no backend lowering → generic non-GAP die at the control position

- **File:** `lib/Chalk/IR/NodeFactory.pm:198-201` (`%STATEMENT_EFFECT_OPS`)
  × `lib/Chalk/Target/LLVM.pm:2994` (`process_control_node` →
  `lower_value`) × `lib/Chalk/Target/LLVM.pm:1587-1593` (`lower_value`
  else-branch: no NotMatch/BacktickExpr/TryCatch case).
- **Bug:** 019eb6ff widened `%STATEMENT_EFFECT_OPS` to
  `Assign CompoundAssign RegexSubst TryCatch Call RegexMatch Match NotMatch
  BacktickExpr` (correct for per-call IDENTITY). `is_statement_node()` is
  derived from that table, and the three control collectors —
  `process_control_node` (LLVM.pm:2994), `_collect_body_recursive`
  (LLVM.pm:3411), `Elaborate.pm:372` — now collect ALL nine and route each
  to `lower_value`. But `lower_value` has cases for only six; NotMatch,
  BacktickExpr, and TryCatch fall through to
  `die "LLVM backend: cannot lower op=$op (not in literal-arithmetic
  slice)"` (LLVM.pm:1592). On `pu` the collector op-list was the hardcoded
  `VarDecl|Assign|CompoundAssign`, so these ops were SKIPPED (not lowered) —
  the branch converts silent-skip into a generic loud die.
- **Executable proof:** /tmp/probe_notmatch_stmt.pl — a statement-position
  `NotMatch` with `set_control_in` → `LOWER DIED: LLVM backend: cannot
  lower op=NotMatch (not in literal-arithmetic slice) at
  lib/Chalk/Target/LLVM.pm line 1592.`
- **Reachability:** latent today (the parse path does not feed LLVM — it is
  corpus-driven). But `Actions.pm:1228` threads `control_in` onto the
  TryCatch node (`_thread_control_head`), and `!~` produces NotMatch
  (`Actions.pm:60`), so a parse-produced statement-position `$x !~ /re/;`,
  `qx(cmd);`, or void-context `try {...} catch {...}` WILL reach the
  collector and die. Phase 4 feeds exactly this (try/catch-heavy real lib/).
- **Why it matters (Phase-4 lens):** the gate doc
  (`2026-06-12-phase4-bson-brief.md`) makes "a divergence is a B::SoN bug"
  the debugging rule, sound only if the backend has no surprises of its own.
  A confusing generic die (vs a clean `GAP:` message naming the unsupported
  op) on the FIRST try/catch from B::SoN will misdirect debugging toward
  B::SoN when the gap is the backend's.
- **Suggested fix:** in `lower_value`, give NotMatch/BacktickExpr/TryCatch
  explicit `die "GAP: op=$op not lowered runtime-free ..."` arms (matching
  the existing GAP-message style), OR exclude the non-lowerable ops from
  `is_statement_node`'s collection set while keeping them in the identity
  table (identity and collectability are separable concerns — the table
  comment already notes identity is the table's job). The first is cleaner:
  a GAP is the honest verdict and the corpus harness already classifies a
  lowering-die as GAP, not MISCOMPILE.
- **Confidence:** High (die reproduced; reachability traced to Actions).
- **Found by:** Logic-A (lower_value seam), Contract (collector-vs-lowerer
  op-set drift) — same finding from two lenses.

## Suggestions

- `lib/Chalk/Target/LLVM.pm:634` and `:332`-region: `return_repr // 'Int'`
  and `field_repr // 'Int'` silent defaults survive (architecture-review
  F7). `_populate_registry_from_mop_class` already `_require_repr`s the
  method body root before this point, so the `// 'Int'` at emission is
  dead-defensive — but it is a silent-garbage channel if a future path
  reaches emission without the upstream guard. Replace with a loud
  missing-repr die. (Pre-existing; deferred F7.)
- `lib/Chalk/Target/LLVM.pm:2333` Assign(Array-lvalue) with container
  repr=`'Array'` (unboxed `%Array*`) GEPs a value that lowered to `i8*`
  (probe /tmp/probe_alloc_alias.pl, first run, repr='Array' → lli "defined
  with type 'i8*' but expected '%Array*'"). REACHABLE ONLY via a malformed
  repr combination the corpus never produces (raw arrays are consistently
  'ArrayRef'/i8* there). Loud, not silent. Pre-existing STATE-F5; a
  representation-discipline assertion (`Array` container ⇒ value must be a
  `%Array*` producer) would convert the late type error into an early GAP.
- `Chalk::Target::LLVM` lives under the `Chalk::Target::*` namespace but
  `use parent 'Chalk::IR::Target'` (the `lower` contract), NOT
  `Chalk::Target` (the `generate` contract). Inheritance is CORRECT (it gets
  the right stub); only the namespace prefix is misleading. Pre-flagged as
  F2-iface, reconciliation deferred to "when Chalk::Target becomes the
  base." Naming smell, not a bug.

## Verified clean (probes that DISPROVED a suspected bug)

- **Postfix-deref after ref-reassign is CORRECT** (the 019eb6ff filed
  follow-note). `@$ref`/`%$ref` route through `_lower_array_deref`/
  `_lower_hash_deref` (bitcast + cache-by-id), which the value-cache fix did
  not touch — BUT `PostfixDeref` IS in `%PURE_DESCEND_OPS`
  (LLVM.pm:1394), so `_reads_mutable_location` descends through it to the
  `PadAccess`, the read-side cache bypass (LLVM.pm:1457) fires, and the
  deref re-lowers with the fresh ref. Probe /tmp/probe_deref_reassign.pl:
  `my $r=[1,2]; @$r; $r=[9,9,9]; @$r; $a+$b` → lli **Int:5** (correct), not
  stale Int:4. The follow-note's worry does not materialize on this path.
- **Identical ArrayRef literals do NOT alias** (019eb316 P4). Probe
  /tmp/probe_alloc_alias.pl (corrected to ArrayRef repr): distinct ids
  (ArrayRef#1 vs #4); `my @a=(1,2); @a[0]=9; my @b=(1,2); @b[0]` → lli
  **Int:1** (correct), not aliased 9. `%ALLOC_OPS` per-call identity works
  end-to-end through PadAccess/VarDecl.
- **Multi-level / child-sorts-before-parent inheritance + inherited ADJUST**
  (019eb6ff C1). `llvm-inherited-adjust.t` passes incl. the 3-level
  field+ADJUST chain and inherited-:reader+override cases. The struct-type
  pre-pass (LLVM.pm:587-611, hoists every class's vtable+obj type before any
  body) holds — no "base element of getelementptr must be sized".
- **No live references to any deleted node type in lib/.** Grepped all 18
  deleted types (ClassDecl/MethodDef/FieldDef/FieldWrite/MethodCall/New/
  AdjustBlock/Array{Read,Write,Literal,Deref}/Hash{Read,Write,Literal,Deref}/
  Make{Array,Hash}Ref/ScalarLen) for live `make('X')`/`->op eq 'X'`/`isa
  Node::X` — zero hits. The only residual literals are sub-NAMES
  (`_lower_array_read`/`_require_repr($n,'ArrayRead')` error-context strings,
  LLVM.pm:3707/3808 — these handle the surviving `Subscript` op) and grammar
  RULE names (`'MethodCall'` in Structural/Precedence semirings) — none is a
  live IR op. Contract concern fully clear.
- **Serializer round-trips the new vocabulary.** Serialize/JSON.pm carries
  Call.param_names + Call.class_name (both arms), RegexCapture.n, EnvRead.key
  (the I3/I4 omission patterns from the prior reviews); ir-serialize-json.t +
  cross-load-son-json.t green.
- **Determinism holds.** Zero unsorted `keys`/`values` hash iteration in
  LLVM.pm's registry/emission/flatten code. `Graph::members()` returns
  `values %cache` (order-undefined) but its ONLY consumer
  (`_phaser_body_in_control_order`) re-establishes order via the control
  chain walk (single-head die + follow control_in), so the membership-set
  non-determinism never reaches output.
- **seal() is enforced loudly.** `_build_registry_from_mop` dies if the MOP
  is not sealed (LLVM.pm:324); every `declare_*` on MOP + MOP::Class dies
  after seal; seal is idempotent and propagates; the corpus harness seals
  before lowering (MdtestCorpus.pm:341). seal.t green (4/4).
- **Corpus gate hardening (F3/F4) is real.** `_run_l_verdict_check`
  three-way-classifies GAP (lowering died) vs MISCOMPILE (.ll produced, lli
  rejected) vs GREEN (lli==perl-oracle, type-tagged exact compare), and the
  central libperl-free guard fires on EVERY GREEN (payload-stripped grep for
  `Perl_|SV|sv_|AV|HV|PL_|newSV|libperl`). Laundering of lli-rejected .ll as
  passing-GAP is closed.
- **TypedInvariant (+99) is sound and tested.** Polymorphic single-op
  (`Length => [Array,ArrayRef,Str]`) and per-position
  (`Subscript`/`PostfixDeref` container constraints) checking; the
  `next unless $node->can('operation')` guard correctly skips metadata
  objects mixed into node lists. well-typed-graph.t green (27/27, with
  bilateral pass/fail cases). No op is in both %OP_REQUIRED_REPR and
  %OP_PER_POSITION_REPR, so the early-`next` after per-position checking
  cannot skip a required-repr check (latent only if a future op joins both).

## Plan Alignment (Phase-4-readiness oriented)

Plan docs consulted: 2026-06-08-ir-taxonomy-reconciliation.md,
2026-06-11-llvm-reads-mop-directly.md,
2026-06-11-target-ir-architecture-review-resolution.md,
2026-06-12-phase4-bson-brief.md,
2026-06-06-three-axis-codegen-and-typed-ir-contract.md.

- **Implemented (acceptance criteria met):**
  - Taxonomy reconciliation COMPLETE — the 7 parallel G5 nodes + the
    aggregate Array*/Hash* node families deleted; lib/ carries zero live
    references; canonical Call/FieldAccess/Assign-over-lvalue/Subscript
    vocabulary is the sole surface.
  - LLVM-reads-MOP-direct COMPLETE — Call.class_name + seal() + registry
    from sealed MOP; ClassInfo bridge deleted from the LLVM tier (the
    structs survive only for the legacy Program-path, owned by MOP-migration
    4/4 per the resolution doc — confirmed no NEW permanent LLVM consumer
    was built on the Info structs).
  - Statement-effect per-call identity (the Phase-4 B::SoN contract
    enumerated in the brief: `%STATEMENT_EFFECT_OPS` = Assign, CompoundAssign,
    RegexSubst, TryCatch, Call) is the single shared table feeding make(),
    the Actions Block fixup, and the backend collectors. Serializer
    preserves it across round-trip.
  - Gate 0 (019eb6ff) — the per-issue review's three hard-gate miscompiles
    (RegexMatch/Match identity, loop-exit phi wiring, _arr_table keying) are
    FIXED and re-verified GREEN here.
- **Deviations from plan:** finding I1 above is a small deviation from the
  Phase-4 brief's own intent — the brief lists TryCatch as a
  statement-effect op for identity, and the backend now collects it, but the
  backend cannot lower it and fails with a non-GAP message. The brief's
  "multi-exit method bodies are an EXPECTED gap-map entry" discipline should
  extend to these ops: they want clean GAP arms, not generic dies.
- **Not yet implemented (neutral — expected):** the parse path does not yet
  seal or feed a MOP to LLVM (lands when the parse pipeline grows an LLVM
  consumer — i.e. Phase 4 itself); F2-iface namespace reconciliation; F7
  `// 'Int'` hardening; STATE-F5 Array-container assertion; the F10 Context
  split. All labeled deferrals, not drift.

**Phase-4 verdict:** SOUND to build B::SoN on top of. The trusted-backend
precondition the brief requires ("the backend has no known miscompiles of its
own") holds — the Gate 0 miscompiles are closed and re-verified. Fixing I1
before 4d (the regex/host/try tier) would make the L-corner's first contact
with real lib/ idioms produce honest gap-map entries instead of a misleading
die; it is cheap (three GAP arms) and need not block 4a/4b.

## Review Metadata

- **Lenses applied (inline, single reviewer — Agent dispatch unavailable):**
  Logic-A (LLVM value/control lowering core), Logic-B (MOP/class +
  IR-layer), Error Handling & Edge Cases, Contract & Integration
  (collector-vs-lowerer op-set, deleted-type references, serializer),
  Concurrency/State (value cache, alias, determinism), Security (folded:
  determinism + loud-vs-silent for this single-threaded compiler tier),
  Plan Alignment. Verifier pass: each finding's code re-read and each
  suspicion probe-tested before keeping.
- **Scope:** lib/Chalk/Target/LLVM.pm (5609 lines), NodeFactory.pm,
  Graph.pm, Node/Call.pm, Serialize/JSON.pm, MOP.pm, MOP/Class.pm,
  MOP/Import.pm, Schedule/Elaborate.pm, Graph/TypedInvariant.pm, ClassInfo.pm,
  MethodInfo.pm, Node.pm, Target.pm + IR/Target.pm + Bootstrap/Target.pm,
  t/lib/.../MdtestCorpus.pm; callers traced into Bootstrap/Perl/Actions.pm,
  Target/Perl.pm, LLVMDriver.pm.
- **Raw suspicions:** 6 | **Verified findings:** 1 Important + 3 Suggestions
  | **Disproved by probe:** 2 (postfix-deref-reassign, ArrayRef-alias —
  both CORRECT at HEAD).
- **Executable probes:** /tmp/probe_notmatch_stmt.pl (I1, die reproduced),
  /tmp/probe_deref_reassign.pl (clean, Int:5), /tmp/probe_alloc_alias.pl
  (clean, Int:1).
- **Prior reviews consulted (to avoid re-reporting fixed issues):**
  256a9b37-branch (whole-branch 2026-06-10), d4823444-019eb316,
  a360849e-019eb42a, 3de55c3a-019eb6ff, plus G6/G7/R1/R2/R3.
- **Test evidence:** 34/34 llvm+identity+seal ir tests pass; 14/14
  corpus+serialize tests pass; the 3 mop failures (codegen-byte-compat t14
  on the untouched Chalk__MOP__Class.pl.golden; class-scope-vars exit 255;
  ir-completeness TODOs) match the documented G.0 baseline and are on files
  unchanged by this branch — NOT branch-attributable. (Caveat: G.0-baseline
  identity confirmed by the prior reviews + untouched-golden evidence, not
  re-run on a pu checkout in this session.)
- **Steering files consulted:** ~/.claude/CLAUDE.md (global),
  <repo>/CLAUDE.md (project), MEMORY.md. No steering-vs-code contradiction
  found beyond the already-flagged CLAUDE.md Plan-Discipline item 3
  staleness (compat_class surface gone) — pre-existing, noted in the
  2026-06-10 review, awaiting perigrin's re-audit.
