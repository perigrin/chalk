# Block Control-Chain Rebuild — Deletion-Readiness Audit

**Date:** 2026-06-04
**Branch:** phase1-lateral-bindings @ 00a3df7f (clean tree)
**Auditor role:** read-only. No `lib/` or `t/` modifications. Probes ran in `/tmp` and were deleted.
**Subject:** can the Block control-chain rebuild (`Actions.pm` 1644-1727, toggled by
`disable_control_rebuild`/`enable_control_rebuild`, default ENABLED) be safely DELETED?

## VERDICT: RED — deletion is a regression today.

The during-parse lateral-seed channel does **NOT** reproduce the rebuild's chain for
**postfix-modifier statements** (`STMT if/unless/while/until/for/foreach COND;`). With the
rebuild OFF, a statement that *precedes* a postfix-modifier statement in the same method body
is **orphaned from the Return-chain and dropped by codegen**, producing broken output. This
is confirmed end-to-end: at least one real source file (`lib/Chalk/Grammar/Symbol.pm`)
generates structurally-broken Perl with the rebuild disabled.

The rebuild is the **last writer that corrects the postfix-modifier `If`/`Loop`'s control
predecessor**. Deleting it without first teaching the during-parse channel (or a replacement
pass) to thread control across postfix modifiers is a regression. The brief's recorded "12-shape
ON==OFF equivalence" did **not** include a postfix modifier — that is the coverage gap that
hid this.

The latent-debt acceptance criterion ("no pass reads `control_in` outside the Return-chain
walk") is **met** (see Finding 2 inventory: all readers are accounted-for). But idempotence is
**not** met, so the criterion alone does not green-light deletion.

---

## Summary

| Category | Count |
|---|---|
| Confirmed deletion blockers | 1 (postfix-modifier control-threading gap) |
| Pre-existing bugs found in passing (out of scope, documented) | 1 (StructPromotion VarDecl input-shape) |
| `control_in`/`control()` reader sites inventoried | 11 distinct sites |
| Category (c) blocking readers | 0 (all readers are chain-walk or value-position or during-parse propagation) |
| Shapes where scheduled output / generated Perl ON==OFF | 10/10 synthetic + 15/16 real goldens |
| Shapes where generated Perl DIVERGES ON vs OFF | postfix-if / -unless / -while / -for (all 4) + real file `Chalk::Grammar::Symbol` |
| Gate suites passing at HEAD (rebuild ON, as shipped) | control-threading 39/39, codegen-byte-compat 19/19, codegen-byte-compat-schedule 19/19, control-uniform-representation 14/14 |

---

## Confirmed findings

### Finding 1 (BLOCKER): during-parse channel drops the predecessor of a postfix-modifier statement

**Trigger / minimal failing case:**
```perl
class T { method m() { my $a = 1; foo() if $c; return $a; } }
```
With the rebuild **OFF**, the generated Perl is:
```perl
class T {
    method m() {
        if (defined($q)) { ... }   # the `my $a = 1;` is GONE
        return $a;
    }
}
```
The leading `my $a = 1;` (or `my $str = ...` in the real file) is **dropped**. The remaining
statements still reference the now-undeclared variable — the output is broken code.

**Discriminating dimension (isolation-confirmed, one dimension per probe):**
- `my $a=1; foo() if $c; return $a;` → DIFF (postfix `if`)
- `my $a=1; foo() unless $c; ...` → DIFF (postfix `unless`)
- `my $a=1; foo() while $c; ...` → DIFF (postfix `while`)
- `my $a=1; foo() for @x; ...` → DIFF (postfix `for`)
- `my $a=1; if (...) { ... } return $a;` (BLOCK if) → **OK** (block form is handled)
- `my $str = $self->t() ? a : b; foo(); return $str;` (ternary, no postfix) → **OK**
- `my $str = $self->t()?a:b; $str .= $q; return $str;` (no postfix) → **OK**

The trigger is the **postfix modifier**, not the ternary, not the method call, not the block-if.
A plain leading `my $a = 1;` is sufficient; the ternary in the real file is a red herring.

**Root cause (control_in level, rebuild OFF, for `my $str=$value; $str .= $q if defined $q; return $str;`):**
```
stmt[0] VarDecl   control_in=Start          # correct
stmt[1] If        control_in=Start  <-- WRONG; should be VarDecl
stmt[2] Return    control_in=Region         # correct
```
With rebuild ON, `stmt[1] If` has `control_in=VarDecl`. The scheduler
(`Chalk::IR::Scheduler::EagerPinning::schedule`, lines 57-81) walks backward from the Return
through `control_in`; when the postfix `If`'s `control_in` is `Start`, the walk terminates
**before reaching the VarDecl**, so the VarDecl never enters `@body` and codegen never emits it.

**Layer responsible:** parser action layer / during-parse channel.
`Actions.pm::PostfixModifier` (lines 2551-2612 for if/unless, 2484-2549 for loop forms) reads
`my $control = $ctx->control_head // Start` (line 2556 / 2488) and builds the `If`/`Loop` with
`control => $control`. At PostfixModifier fire-time `$ctx->control_head` is still **Start** —
the postfix modifier is parsed inside the *same* StatementItem as its body expression
(`Expression WS PostfixModifier`), so the lateral seed that would carry the *preceding*
statement has not been threaded into this item's control_head. The rebuild's If/Loop branch
(`Actions.pm` 1711-1726) is the only place that later rewires `inputs[0]` to the chain tail
(the VarDecl). Disabling the rebuild loses that correction.

**Evidence:**
- Per-flavor codegen ON-vs-OFF probe: all four postfix flavors DIFF; block forms OK.
- control_in dump (above) shows `If.control_in=Start` (OFF) vs `=VarDecl` (ON).
- Real file: `lib/Chalk/Grammar/Symbol.pm` `to_string()` — OFF drops
  `my $str = $self->is_terminal() ? "/$value/" : $value;` (the method uses
  `$str .= $quantifier if defined $quantifier;`, a postfix `if`).
- 1/16 golden source files regress under rebuild-OFF codegen (Symbol.pm). The pattern itself
  is widespread — 39 files under `lib/` contain postfix-modifier-shaped lines — Symbol is
  simply the golden-set file where a *preceding same-method statement* makes the loss
  observable end-to-end.

**Suggested remediation shape (NOT performed):** teach the during-parse channel to deliver the
preceding statement's `control_head` to PostfixModifier before it constructs the If/Loop — e.g.
seed the StatementItem's control_head so it is visible at PostfixModifier fire-time, or have the
StatementItem layer (which already runs `_thread_control_head` for plain side-effect nodes at
~357-364) also rewire the control of an If/Loop returned from a postfix-modifier statement to the
arriving control_head. This is the same class of "frontier" the if/else-join spike deferred for
loop region-advance: a control-flow node constructed mid-statement does not see its left sibling.

**Side effects of the fix:** must preserve the inner-body-tail-leak guard (control-threading.t
targets 4/5: the If/Loop's *own* control_in must be the preceding statement, not a node from
inside its body) and the determinism of Region ids. Any rewire must be idempotent under
rebuild-ON so the differential oracle keeps matching during the transition.

---

### Finding 2 (NOT a blocker, inventory + invariant check): control_in / control() reader inventory

Every site in `lib/` that READS a node's control predecessor, classified per the brief's
(a)/(b)/(c) scheme. **No category (c) blocker exists** — no pass iterates `$graph->nodes` and
reads `control_in` for ordering in a way that would observe stray nested values.

| # | Site | Reads | Category | Notes |
|---|---|---|---|---|
| 1 | `IR/Scheduler/EagerPinning.pm:58` | `$exit->control_in` | (a) sanctioned | start of Return-chain walk |
| 2 | `IR/Scheduler/EagerPinning.pm:66,71` | `$cur->control_in` | (a) sanctioned | chain-walk step |
| 3 | `IR/Scheduler/EagerPinning.pm:105,111,123` | `$r->control_in`, `$cur->control_in`, `$head->control_in` | (a) sanctioned | `_pick_outer_return` chain-depth count |
| 4 | `Actions.pm:121` | `$node->control_in` (defined-check) | propagation | `_thread_control_head` guard — no-op if already set |
| 5 | `Actions.pm:1105` | `$n->control_in` | reachability seed | `_finalize_body_graph` transitive seeding; pushes the predecessor into the seed worklist for graph membership. Reads control_in on every transitively-walked node — relies on data-position nodes carrying `control_in=undef` (invariant confirmed below). Not an ordering reader. |
| 6 | `Actions.pm:1667,1684,1706-1707,1719` | `$s->control_in` / `$s->inputs->[0]` | the rebuild itself | the code under audit |
| 7 | `Actions.pm:2391` | `$target->control_in` | propagation | init-fold copies the bare VarDecl's control onto the refined VarDecl via `set_control_in` |
| 8 | `IR/Node/VarDecl.pm:27` | `method control() { control_in }` | accessor def | used by StructPromotion (Finding 3) |
| 9 | `Optimizer/StructPromotion.pm:767` | `$stmt->control()` | (c)-shaped but pre-broken | see Finding 3; not in the standard Perl-codegen path |
| 10 | `IR/Node/If.pm`, `Loop.pm`, `Region.pm` | `control_in()` override → `inputs[0]` / `head` | accessor def | the inputs[0]-vs-control_in asymmetry; see brief step 4 below |
| 11 | `Bootstrap/Context.pm:182` | comment only (`$scope->control()`) | n/a | docstring, not a node read |

**Codegen value-position reads (category (b) — read inputs[0] as VALUE, not control):** confirmed
correct and migrated to `->value()`/`->name()`/`->init()` accessors —
`Target/Perl.pm:877` (`$node->value`), `EmitHelpers.pm:2266` (`$node->value`),
`StructPromotion.pm:395` (`$node->value`). VarDecl readers use `->name()` (inputs[0]) and
`->init()` (inputs[1]). None of these read control.

**Data-position undef invariant (brief step 1) — CONFIRMED HOLDS at HEAD.** Probe on
`bar(foo()); return 1;` with rebuild OFF:
```
outer bar() control_in = Start      # statement position — correct
inner foo() control_in = undef      # data position — correct (a109dcfd invariant intact)
```
No reader chokes on `undef`: site #5 guards with `defined`, the scheduler chain-walk never
visits data-position nodes, and value-position readers don't read control. **The latent-debt
acceptance criterion is satisfied.**

---

### Finding 3 (PRE-EXISTING bug, out of scope, documented per anti-pattern-7): StructPromotion builds VarDecl with the OLD input shape

`lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm:766-768`:
```perl
my $new_var_decl = $typed->make('VarDecl',
    inputs       => [$stmt->control(), $var_node, $struct_ref],
);
```
This is the **pre-Proposal-2 3-input shape** `[control, name, init]`. After commit d01bfea3,
`VarDecl` carries control in the `control_in` decoration and inputs are `[name, init]`
(`VarDecl.pm:28-29`). So this construction now mis-assigns: `name()` becomes `$stmt->control()`
(the control predecessor node), `init()` becomes `$var_node`, the third slot is ignored, and
`control_in` is never set. The same file READS VarDecl with the migrated `->name()` accessor
(line 744) but WRITES with the old shape — an internal inconsistency.

**This is independent of the rebuild** and not a deletion blocker. StructPromotion is invoked
only from `script/build-chalk-so-generated` (the XS/C build path), not the standard
`Target::Perl::generate` path. Its test `t/bootstrap/struct-promotion/ir-rewriter.t` passes
(4/4) because it asserts presence of StructRef/FieldAccess nodes, not the VarDecl input shape.
Recorded here so it does not become undocumented drift. **Where it belongs:** a StructPromotion
Proposal-2 migration follow-up; this audit does not fix it.

---

## Step 2 — Idempotence findings (scheduled output + generated Perl diff)

Two probes, both ON-vs-OFF, parsing each shape twice (rebuild enabled = oracle, disabled =
during-parse-only) and diffing.

**Probe A — scheduled item sequence** (`EagerPinning::schedule`, `kind:form:operation` per item):
all 10 synthetic shapes ON==OFF, including:
```
OK 1-flat            OK 6-ifelse-join
OK 2-mixed           OK 7-trycatch
OK 3-callseq         OK 8-loop-then-if
OK 4-loop-carried    OK 9-nested-loop
OK 5-nested-if       OK 10-loop-var-use
```

**Probe B — full generated Perl** (`Target::Perl::generate($mop)->{'main.pm'}`, byte compare):
- 10/10 synthetic shapes ON==OFF (including loop-carried `my $x=0; while($c){$x=$x+1} foo(); return $x;`
  and try/catch — both emit complete, correct, structurally-identical code).
- Real goldens (16 files, parsed from `lib/.../*.pm`): **15 same, 1 DIFF, 0 err.** The DIFF is
  `Chalk__Grammar__Symbol.pl.golden` (Finding 1). Diff:
  ```
  21d20
  <         my $str = $self->is_terminal() ? "/$value/" : $value;
  ```

**Conclusion:** scheduled output and generated code are byte-identical ON-vs-OFF for every
non-postfix-modifier shape tested, including loops and try/catch. The single divergence is
Finding 1. The brief's hypothesis that loops/Phi or the `*_stmts` ScheduleMeta arrays might
diverge is **NOT borne out** — those are populated by the If/Loop/TryCatch actions
themselves (Actions.pm 518-566, 1208-1221, 2532-2547, 2763-2772, etc.), never by the rebuild,
so disabling the rebuild does not touch them.

---

## Step 3 — Loop / Phi frontier findings

The brief flagged loops (back-edges, loop-carried dependence, header Phis) as a suspected
frontier. **Result: loops are SAFE under rebuild-OFF for the cases tested.**

- `my $x=0; while($c){ $x=$x+1; } foo(); return $x;` (loop-carried) — generated Perl ON==OFF,
  structurally complete (the `while` body, the post-loop `foo()`, and `return $x` all present).
- `my $sum=0; while($c){ $sum=$sum+$c; } return $sum;` (loop var used after) — ON==OFF.
- `while($a){ while($b){ $x=$x+1; } } return $x;` (nested loop) — ON==OFF.
- `while($c){foo();} if($d){bar();} return 1;` (loop-then-if) — ON==OFF.

Block-form loops thread correctly because `WhileStatement`/`ForStatement` actions construct the
Loop *as a statement* and `update_control_head(region)` is published at the statement boundary;
the next statement's lateral seed picks up the Region. The Loop's own `control_in` (entry_ctrl)
is the preceding statement in both modes (control-threading.t target 5 pins this and passes).

The loop-carried Phi machinery is read from `schedule_data`/Region and is unaffected by the
rebuild. **Loops are not a blocker. Only the *postfix-modifier* loop/if forms are** (Finding 1).

---

## Step 4 — If/Loop inputs[0] vs control_in asymmetry

Confirmed working as the brief describes, **for block-form If/Loop**. `If.pm`/`Loop.pm` override
`control_in()` to read `inputs[0]` (the real dataflow control edge the Region/merge machinery
uses); the scheduler's unified reader (`$cur->control_in`) gets the override for If/Loop and the
base field for everyone else. With rebuild OFF, block-form `If`/`Loop` correctly show their
preceding statement as predecessor (shapes 4/6/8/9 and control-threading.t targets 4/5, all
green). This is the override path working, not an accident.

**The asymmetry is exactly where Finding 1 bites:** the rebuild rewrites If/Loop `inputs[0]` at
`Actions.pm:1719-1723` via `set_control_in`. For a *postfix-modifier* If/Loop, that rewrite is
the **only** correction of `inputs[0]` — the action set it to `Start` (control_head at fire-time),
and nothing else fixes it. So deleting the rebuild leaves postfix-modifier If/Loop pointing at
Start.

---

## Step 5 — Test coverage for deletion

**Tests that exercise the rebuild toggle:** exactly one — `t/bootstrap/control-threading.t`
(the only file matching `disable_control_rebuild`/`control_rebuild` in `t/`). It has 39 subtests:
single-statement, if/else-join (targets 2-4), loop-with-body (target 5), and a 6-shape ON==OFF
suite (flat / mixed / call-seq / loop / nested-if / if-else-join). **It does NOT cover any
postfix-modifier statement** — that is the gap that let Finding 1 ship undetected.

**Would deletion be caught by existing tests?** Only partially. With the rebuild deleted:
- `control-threading.t` targets that assert `control_in` directly under rebuild-OFF would still
  pass (they don't use postfix modifiers).
- The byte-compat golden suites (`codegen-byte-compat.t`, `codegen-byte-compat-schedule.t`,
  19/19 each) run with the rebuild at its default (ON). They would only catch the regression if
  re-baselined to rebuild-OFF — and then `Chalk__Grammar__Symbol.pl.golden` would fail (Symbol
  is in the golden set; confirmed it diverges). So the golden suite **would** catch it *iff* the
  goldens are regenerated rebuild-OFF, which is what deletion implies.

**Tests requiring rewrite/deletion if the rebuild is removed:** `control-threading.t`'s
"rebuild active" oracle assertions (e.g. lines 44-55, 197-216, 337-349, 408-419) parse with the
rebuild ON to establish the differential target. With the rebuild gone, the toggle API
(`disable/enable_control_rebuild`, Actions.pm 91-94) disappears and those oracle blocks must be
restructured to compare against a fixed golden instead of against rebuild-ON. This is the same
shape of change as the C3 `control-input.t` precedent the brief references — expect to migrate,
not merely delete, this test.

**Prerequisite test before deletion can be green-lit:** add postfix-modifier coverage to the
ON==OFF suite (`STMT if/unless/while/until/for COND` preceded by a leading statement). That
single addition would have turned Finding 1 RED at implementation time. Per CLAUDE.md
bilateral/nested-context coverage rules, also cover `f X if C` chained with a following
statement and a preceding statement (the leading-statement-loss case).

---

## Deletion plan (for when the blocker is cleared — YELLOW path)

Deletion becomes safe once **Finding 1** is fixed (postfix-modifier control threading lands in
the during-parse channel) AND a postfix-modifier ON==OFF case is added to `control-threading.t`
and passes. At that point:

1. Re-run Probe B (full generated Perl ON-vs-OFF) across all 31 source files; require 0 DIFFs.
2. Add the postfix-modifier shape (all 5 flavors, each preceded by a statement) to the ON==OFF
   suite; require green rebuild-OFF.
3. Re-baseline `codegen-byte-compat` goldens rebuild-OFF and confirm byte-identical to the
   rebuild-ON goldens (they should be, if idempotence is complete).
4. Delete `Actions.pm` 1644-1727 (rebuild loop), the toggle API (91-94), and migrate
   `control-threading.t`'s rebuild-ON oracle blocks to fixed goldens.
5. Independently fix Finding 3 (StructPromotion VarDecl shape) — orthogonal but should not be
   left as drift.

---

## Acceptance-criteria verification

- **Latent-debt criterion** ("no pass reads `control_in` outside the Return-chain walk; a future
  pass iterating `$graph->nodes` reading `control_in` would observe stray nested values") —
  **MET.** Inventory (Finding 2) shows all readers are chain-walk (a), value-position (b),
  reachability-seed/propagation with `defined` guards, or the rebuild itself. Data-position
  nodes carry `control_in=undef` (confirmed). No `$graph->nodes`-iterating ordering reader exists.
- **Broader idempotence question** ("is the rebuild truly idempotent for EVERY case") —
  **NOT MET.** Postfix-modifier statements diverge (Finding 1), confirmed at scheduled-output,
  generated-Perl, and real-file (Symbol.pm) levels.

## Cross-references

- `docs/plans/2026-06-02-control-wiring-trio-comparison.md` — execution log; this audit is the
  "separate step" its final paragraph names. Finding 1 should be appended to that log's
  remaining-work before the capstone is called complete.
- `docs/plans/2026-06-01-merge-and-control-implementation-plan.md` — Phase 2 problem statement;
  postfix-modifier mid-statement control is the same class as the deferred "loop region-advance"
  frontier.
- Memory: `block_action_workaround_accretion.md`, `phi_merge_strategy.md` — Block action
  workarounds; the postfix-modifier `If`/`Loop` is constructed mid-statement and is exactly the
  "node never gets its left sibling" failure mode those notes describe.
