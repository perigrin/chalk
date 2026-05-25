# Phase 7d Design — Schedule-Driven Body Emission in Target::C

**Date:** 2026-05-25
**Status:** Design v3 — addresses spec-document-reviewer iteration 2 (2 Important findings about helper-signature contradiction + retired risk + missing block_close helper).
**Branch:** `fixup-audit-baseline` (continues from Phase 7c-proper commits
`d58ad846` + `c41589a6`).
**Predecessors:**
- `docs/plans/2026-05-24-target-c-migration-audit.md` §9 Phase 7d
  (lines 947-1020) — original audit prescription.
- `docs/plans/2026-05-25-phase-7c-proper-design.md` — what 7c-proper
  shipped (Target::C analyze layer reads MOP::Class).
- `docs/plans/2026-05-25-phase-7c-proper-plan.md` — execution log.

## Purpose

Migrate Target::C's method/sub body emission from `$method->body`
arrayref iteration to consuming `Chalk::IR::Schedule` instances
produced by `Chalk::IR::Scheduler::EagerPinning`. Mirrors what
Target::Perl already does via `_emit_scheduled_body` /
`_emit_schedule_item` (Perl.pm:234-326).

After 7d, Target::C and Target::Perl share the same
"build-schedule-then-walk" emission shape. The legacy `$body`
arrayref reader path is unused by Target::C's emission layer (it
remains alive on `MOP::Method`/`MOP::Sub` until Phase 7g deletes
the `body` field entirely).

## Scope

**Line citations verified against `fixup-audit-baseline` HEAD
(commit `c41589a6`) on 2026-05-25.** The audit document
(`2026-05-24-target-c-migration-audit.md §9 Phase 7d`) gives line
numbers offset by ~26 lines from current head; this spec
supersedes those numbers.

**In scope:**
- `_emit_method` (C.pm:98): switch to schedule-driven. Simple-body
  shortcuts migrate too (detected from schedule shape, not from
  `$body->[0]`).
- `_emit_complex_method` (C.pm:207): consume schedule for body
  iteration AND for the analysis helpers that drive its emission
  decisions.
- `_emit_sub` (C.pm:337): same migration as `_emit_method`,
  **with one critical caveat**: `_emit_sub` is NOT implemented
  as a call to `_emit_complex_method`. It duplicates the
  complex-method body-emission logic inline (lines 337-455),
  AND wraps the whole body in a try/catch with state save/restore
  for `_current_sub_name` and `_return_context` (lines 344-454).
  The migration must preserve the try/catch save/restore
  semantics — exceptions during body compilation must not leak
  state into subsequent method/sub compilation in the same class.
- New helpers: `_emit_scheduled_c_body($method)`,
  `_emit_c_schedule_item($item, ...)`, `_emit_c_block_open_head`,
  `_emit_c_if_head`, `_emit_c_while_head`, `_emit_c_foreach_head`,
  `_emit_c_for_head`, `_emit_c_catch_head` (the C-side mirror of
  Perl.pm's heads, with C syntax — `if (...) {`, `while (...) {`,
  `for (_i = 0; ...) {`, JMPENV_PUSH try/catch boilerplate from
  `emit_cfg_try_catch`).
- Analysis helpers, rewritten to consume `$schedule` instead of
  `$body` (verified line numbers from current head, NOT from the
  audit doc):
  - `_is_complex_method` (EmitHelpers.pm:542) — currently takes
    `$method_decl`; new shape takes `$schedule`.
  - `_has_early_return` (EmitHelpers.pm:571) — currently takes a
    `$nodes` arrayref and recurses into cfg_lookup
    `then_stmts`/`else_stmts`/`body_stmts`; new shape takes
    `$schedule`.
  - `_body_contains_return` (EmitHelpers.pm:599) — same.
  - `_body_contains_bare_return` (EmitHelpers.pm:624) — same.
  - `_is_bare_return_expr` (EmitHelpers.pm:633) — node-level
    helper, takes a single `$node`. Signature preserved; the
    helper inspects the node itself, not a body or schedule.
    Calling pattern changes: callers locate the relevant 'stmt'
    node via schedule iteration before invoking.
  - `_is_unambiguous_value_expr` (EmitHelpers.pm:648) — node-level
    helper, same as `_is_bare_return_expr`. Signature preserved.
  - `_is_single_stmt_return_expr` (EmitHelpers.pm:667) — node-level
    helper, signature preserved.

  **These three node-level helpers stay as `helper($node)` and
  are NOT in the schedule-substrate group.** The four schedule-
  walking helpers (`_has_early_return`, `_body_contains_return`,
  `_body_contains_bare_return`, `_collect_var_decls`,
  `_collect_all_var_refs`, `_is_complex_method`) take
  `$schedule`. The bullet list in "What ships" Item 5 below
  uses `$schedule` for ALL helpers and is wrong for these three
  — the corrected signatures match this scope section.
  - `_collect_var_decls` (EmitHelpers.pm:680) — currently takes
    `($nodes, $declared_vars)` and recurses into cfg_lookup
    `then_stmts`/`else_stmts`/`body_stmts`/`try_stmts`/`catch_stmts`
    AND extracts iterator-variable names from `$state->{iterator}`
    for foreach loops; new shape takes `($schedule, $declared_vars)`.
    See Section "Iterator-variable case" below for the iterator
    handling.
  - `_collect_all_var_refs` (EmitHelpers.pm:753) — same.
- Repair-mechanism investigation (pre-migration probe): determine
  whether `_repair_stale_merge` and `emit_cfg_loop`'s chart-re-read
  patch are still load-bearing. Dead ones get deleted in 7d. Live
  ones get understood-then-decided.

**Out of scope:**
- **Deletion of cfg_lookup infrastructure** (`%_cfg_lookup`,
  `_build_cfg_lookup`, `emit_cfg_if`, `emit_cfg_phi_if`,
  `emit_cfg_loop`, `emit_cfg_try_catch`, `emit_from_cfg_state`,
  `_emit_loop_jump`, `_set_sa`, `_set_ctx`). These survive 7d as
  unreachable code that 7g sweeps. (Per Question 1 answer: scope
  A — migration only.)
- **Deletion of `MOP::Method.body` / `MOP::Sub.body`** — 7g.
- **Deletion of legacy IR structs** (`Chalk::IR::Program`,
  `ClassInfo`, etc.) — 7g.
- **TestXSHelpers + hand-built test migration** — Phase 7e.
- **StructPromotion `_analyze_mop` body→graph** — Phase 7f.
- **Modification of Target::Perl** — already schedule-driven.

## Framing: what changes and what doesn't

### What changes

Method/sub body emission becomes a two-step process:

1. **Build schedule.** `my $schedule =
   Chalk::IR::Scheduler::EagerPinning->new->schedule($method)`
2. **Walk schedule items.** For each `Chalk::IR::Schedule::Item`,
   dispatch on `$item->kind` ('stmt', 'block_open', 'block_close',
   'else', 'elsif', 'catch'). The 'stmt' case emits a single
   IR-node statement via the existing `_emit_stmt` / `_emit_node`
   primitives. The structural-marker cases (block_open, etc.) emit
   the C-syntax head/tail.

The analysis helpers (`_has_early_return` etc.) take the
`$schedule` they were just handed and grep its items, rather than
walking `$body->@*` and recursing into `cfg_state` nested arrays.

`_emit_method`'s simple-body shortcuts (lines 111-200) get
rewritten to inspect the schedule:

- Empty body: `$schedule->items->@* == 0`.
- Simple-return: exactly one `'stmt'` item whose node is a Return
  of a Constant/Interpolate.
- Simple-die: exactly one `'stmt'` item whose node is an Unwind.

The simple-body emission templates themselves (the `newSViv`,
`croak`, etc. one-liners) are unchanged; only the detection
switches from "look at `$body->[0]`" to "look at `$schedule->items`".

### Why the flat schedule walk is semantically equivalent to the legacy cfg_lookup recursion

The legacy analysis helpers walk a `$body` arrayref and use
`%_cfg_lookup` to recurse INTO each cfg_state's `then_stmts` /
`else_stmts` / `body_stmts`. This recursion exists because, in
the legacy IR shape, a control-flow node (If, Loop, TryCatch)
appears in `$body` as a SINGLE node, and its nested statements
are stored in the cfg_state side-channel.

In the schedule shape, the scheduler has already flattened the
control flow: every statement that appears anywhere inside any
control-flow branch is emitted as its own `'stmt'` item in
`$schedule->items`, interleaved with `block_open` / `block_close`
markers. **A `return` inside an if-branch appears as a `'stmt'`
item between a `block_open(form='if')` and `block_close(form='if')`
pair.**

Concretely, for the legacy code:
```perl
# Legacy _has_early_return walking body=[$if_node]:
# - finds $if_node in cfg_lookup
# - recurses into $state->{then_stmts}
# - finds Return → returns true
```

The schedule equivalent is:
```perl
# Schedule items for the same source: [
#   block_open(form='if', node=$if_node),
#   stmt(node=$return_node),     # ← the early return
#   block_close(form='if'),
# ]
# _has_early_return walks items, finds stmt(node=Return), returns true.
```

**Both produce the same answer for the same source.** The
correctness invariant: the scheduler guarantees that every IR
node that the legacy cfg_lookup recursion would visit appears
as a 'stmt' item in the schedule's flat sequence. This invariant
is what `Chalk::IR::Scheduler::EagerPinning` is designed to
provide; it's exercised by
`t/bootstrap/scheduler/schedule-data-*.t`.

Therefore: the rewritten helpers do NOT special-case "is this
stmt inside a block?" Every 'stmt' item is, by definition, at
the depth where it should be considered. The block_open/close
markers exist for emission-side brace tracking, not for
analyzer-side scope decisions.

### Iterator-variable case (`_collect_var_decls`)

The one legacy behavior that requires explicit schedule handling
is the foreach iterator name. The legacy `_collect_var_decls`
extracts `$state->{iterator}` from cfg_lookup entries for
foreach loops and registers it in `%declared_vars`. The schedule
equivalent: when iterating items, a `block_open` item with
`form eq 'foreach'` whose `node` is a Loop has the iterator
on `$item->node->schedule_data->iterator`. The rewritten
`_collect_var_decls` must extract and register this name.

```perl
# Pseudocode for the rewritten helper:
method _collect_var_decls($schedule, $declared_vars) {
    for my $item ($schedule->items->@*) {
        if ($item->kind eq 'stmt') {
            my $node = $item->node;
            # Existing VarDecl detection logic, unchanged.
            $self->_register_var_decl_from_node($node, $declared_vars);
        } elsif ($item->kind eq 'block_open' && $item->form eq 'foreach') {
            my $iter = $item->node->schedule_data->iterator;
            # Same name-extraction logic the legacy used on
            # $state->{iterator}.
            $self->_register_iterator_name($iter, $declared_vars);
        }
    }
}
```

Same pattern for `_collect_all_var_refs`. The legacy logic at
EmitHelpers.pm:684-717 (`_collect_var_decls`) and 776-783
(`_collect_all_var_refs`) shows the iterator/catch_var/key
extraction; port each to the schedule-walk equivalent.

### What doesn't change

- The `$method` / `$sub` parameter shape: still receives a
  `MOP::Method` / `MOP::Sub` (per 7c-proper Commit 2).
- `_emit_node`, `_emit_stmt`, `_emit_expr`, the typed-node
  dispatch table, the `eval_pv` fallback machinery: unchanged.
  The schedule's 'stmt' case calls `_emit_stmt($item->node, ...)`,
  same as the legacy body loop called `_emit_stmt($body_item, ...)`.
- The wrapper logic in `_emit_complex_method` (param collection,
  `%declared_vars`, RETVAL declaration, function template, XSUB
  registration): unchanged. Only the body iteration inside it
  changes.
- The legacy cfg_lookup machinery (`%_cfg_lookup`, `emit_cfg_*`):
  stays alive but becomes unreachable from `_emit_method` /
  `_emit_complex_method` / `_emit_sub`. Phase 7g deletes it.

## What ships

This effort lands as **three commits** on `fixup-audit-baseline`.

### Commit 1 — `chore(target-c): instrument repair mechanisms for 7d retirement audit`

**Purpose:** pre-migration probe (per Question 3/4 answer: option D).
Determine which textual repair mechanisms still fire on real input
before the migration changes the emitted C shape.

**Changes:**

1. Add a `field %_repair_counters;` to EmitHelpers plus a
   `_record_repair($name)` method that increments the counter.
2. Inside each repair entry-point — `_repair_stale_merge`
   (EmitHelpers.pm:330), `_is_stale_merge` (line 315),
   `emit_cfg_loop`'s chart-re-read branch (line ~1207), and any
   other post-emission fixup (`_fixup_xs_list_destructuring`,
   `_fixup_ternary_assignment`, `_fixup_filtercomposite_add_destructuring`,
   `_fix_postfix_chain` if applicable) — call `_record_repair("name")`
   the moment the patch fires (after the regex matches, before the
   substitution).
3. Add a `repair_counters()` accessor on EmitHelpers that returns
   a copy of the counters hash.
4. Add a test `t/bootstrap/c-repair-coverage.t` that:
   - Resets the counters.
   - Runs `bnf-target-c.t`-equivalent emission for a small corpus
     (Boolean.pm, Structural.pm, Symbol.pm — 3 small real classes).
   - For each repair name, reports the count.
   - The test PASSES regardless of counts; its purpose is to
     produce evidence in a single test run. Add a `diag` for each
     non-zero counter so the output captures the live-vs-dead
     question.

**This commit is a measurement instrument.** No production-behavior
change; no test gates beyond "the instrumented code still runs and
the tests still pass." After 7d-proper completes, Commit 1 stays
alive as a regression-coverage tool (if a future change reintroduces
a dead-repair firing, the diag output flags it).

### Commit 2 — `feat(target-c): Phase 7d — schedule-driven body emission`

**Purpose:** the migration itself. Builds on Commit 1's evidence
to decide which repairs to delete vs. port-or-fix.

**Pre-Commit-2 decision gate:** read Commit 1's repair counter
output. Repairs with zero counts get deleted (option D's "dead
ones get retired"). Repairs with non-zero counts get a paragraph
in this commit's message documenting (a) what they patch and
(b) why the schedule path doesn't make them obsolete (if they
genuinely don't) or (c) what the new path needs to do (port,
fix at source, or skip and rely on the source-fix's existing
coverage).

**Changes:**

1. **New helpers in C.pm** (mirror Perl.pm's structure):

   - `_emit_scheduled_c_body($method)` — builds schedule, walks
     items, returns body C lines as an arrayref.
   - `_emit_c_schedule_item($item, $lines, $indent_ref, $scheduler, $declared_vars)`
     — dispatches per `$item->kind`. 'stmt' calls `_emit_stmt` on
     `$item->node`; block_open/close/else/elsif/catch call the
     appropriate head emitter.
   - `_emit_c_block_open_head($item)` — switches on `$item->form`
     ('if', 'while', 'for', 'foreach', 'try'); calls the
     form-specific head emitter.
   - `_emit_c_if_head($if_node)` — `if (COND) {` (C syntax).
   - `_emit_c_while_head($loop)` — `while (COND) {`.
   - `_emit_c_for_head($loop)` — C-style for: `for (init; cond; step) {`.
   - `_emit_c_foreach_head($loop)` — the C transliteration of
     Perl's `for my $x (LIST) {` (typically renders as
     `{ AV *list = ...; for (IV _i = 0; _i < av_len(list)+1; _i++) { SV *x = *av_fetch(list, _i, 0); ...`).
     This is more involved than Perl's one-line head — it likely
     produces a multi-line wrapper. The block_close handler for
     'foreach' must close BOTH braces.
   - `_emit_c_catch_head($item)` — JMPENV_PUSH-style catch
     boilerplate from the legacy `emit_cfg_try_catch`. Same shape
     the legacy path produced; port the JMPENV machinery to live
     inside the schedule path's catch-head handler.
   - `_emit_c_block_close_tail($item)` — emits the closing tail
     for a `block_close` item. For most forms ('if', 'while',
     'for', 'try'), emits a single `}`. **For `form eq 'foreach'`,
     emits TWO `}` (one for the for-loop, one for the
     AV/iterator scope)** — see Risk #2 for the brace-pairing
     rationale. The schedule's `is_balanced` invariant is
     unaffected; the asymmetric C text is an emitter-side
     concern, not a schedule-side one.

2. **`_emit_method` rewrite:**

   ```perl
   method _emit_method($method) {
       my $name = $method->name;
       my $factory = Chalk::IR::NodeFactory->new();
       my $params = [
           map { $factory->make('Constant', const_type => 'variable', value => $_) }
               $method->params->@*
       ];
       my $func_name = "${\  $self->_get_current_slug()}_${name}";

       my $scheduler = Chalk::IR::Scheduler::EagerPinning->new;
       my $schedule  = $scheduler->schedule($method);

       # Simple-body shortcuts (schedule-driven):
       my @items = $schedule->items->@*;
       if (@items == 0) {
           return $self->_emit_simple_empty_method($func_name);
       }
       if (@items == 1 && $items[0]->kind eq 'stmt') {
           my $node = $items[0]->node;
           if ($node isa Chalk::IR::Node::Return) {
               my $value = $node->inputs->[1];
               my $simple = $self->_classify_simple_return_value($value);
               return $self->_emit_simple_return_method(
                   $func_name, $params, $value, $simple
               ) if defined $simple;
           }
           if ($node isa Chalk::IR::Node::Unwind) {
               return $self->_emit_simple_die_method(
                   $func_name, $params, $node
               );
           }
       }

       my $return_type = $method->return_type;
       return $self->_emit_complex_method(
           $name, $params, $schedule, $scheduler, $return_type
       );
   }
   ```

   The simple-body emission templates (`newSViv`, `croak`, empty)
   move into named helpers (`_emit_simple_empty_method`,
   `_emit_simple_return_method`, `_emit_simple_die_method`) — pure
   refactor extraction from the existing code, no behavior change.
   `_classify_simple_return_value` returns a tag describing whether
   the value is a numeric literal, a string literal, undef/true/false,
   or interpolate (or undef for "not simple"); replaces the inline
   if-else chain at C.pm:121-137.

3. **`_emit_complex_method` rewrite:**

   ```perl
   method _emit_complex_method($name, $params, $schedule, $scheduler, $ir_return_type = undef) {
       # ... wrapper code unchanged ...
       # body emission:
       my @body_lines;
       my $indent = 0;
       for my $item ($schedule->items->@*) {
           $self->_emit_c_schedule_item(
               $item, \@body_lines, \$indent, $scheduler, \%declared_vars
           );
       }
       # ... RETVAL handling, post-processing unchanged ...
   }
   ```

   The wrapper logic (param decls, `%declared_vars`, retval
   detection, function template) stays. Only the inner body loop
   swaps from `for my $stmt ($body->@*) { ... emit ... }` to the
   schedule-walking form above.

4. **`_emit_sub` rewrite (NOT a thin wrapper around `_emit_method`).**

   `_emit_sub` (C.pm:337-455) is currently a standalone
   ~120-line implementation that:
   - Takes `($name, $params, $body)` (NOT a MOP::Sub).
   - Wraps the whole body in `try { ... } catch ($e) { $caught_error = $e }`.
   - Save/restores `_current_sub_name` and `_return_context` BEFORE
     and AFTER the try block, so an exception during body
     compilation does not leak state into subsequent
     method/sub compilation in the same class.
   - Has a slightly different last-stmt classification than
     `_emit_method`: it counts `Constant->value() eq 'return'`
     as a `$last_is_return` (line 355-357).
   - Emits a `static SV *helper_name(...)` (NOT exported, NOT
     in the .h file) — class-scope subs are static helpers.

   **Required signature change for the schedule path:** `_emit_sub`
   must build the schedule from a MOP::Sub, but currently receives
   only `($name, $params, $body)`. Two options:
   - **(a)** Change `_emit_sub`'s signature to `_emit_sub($sub)`
     where `$sub isa Chalk::MOP::Sub`; update the caller in
     `_generate_c_files` (the sub-emission loop currently at
     C.pm:1585-1604) to pass `$sub` directly. Smaller call-site
     change; `_emit_sub` builds its own schedule.
   - **(b)** Change the caller to build the schedule before calling
     `_emit_sub`, and pass `_emit_sub($name, $params, $schedule, $scheduler)`.
     Bigger call-site change; `_emit_sub` doesn't need to know
     about the scheduler.

   **Choose (a).** Symmetric with the `_emit_method($method)`
   shape from 7c-proper; `_emit_sub` already needs to read other
   MOP::Sub fields conceptually (return_type, body for the
   schedule construction), so passing the whole MOP object is
   cleaner.

   **State save/restore must be preserved exactly.** The pattern
   from the legacy code:
   ```perl
   method _emit_sub($sub) {
       my $name = $sub->name;
       my $params = $sub->params;

       my $prev_sub_name = $self->_get_current_sub_name();
       my $prev_return_context = $self->_get_return_context();
       $self->_set_current_sub_name($name);

       my $result;
       my $caught_error;
       try {
           my $scheduler = Chalk::IR::Scheduler::EagerPinning->new;
           my $schedule  = $scheduler->schedule($sub);

           # Simple-body shortcuts (same pattern as _emit_method):
           # ... empty / simple-return / simple-die detection ...

           # Otherwise complex emission with state save/restore wrapper:
           $result = $self->_emit_complex_sub_body(
               $name, $params, $schedule, $scheduler
           );
       } catch ($e) {
           $caught_error = $e;
       }

       # Always restore state, even if body compilation threw.
       $self->_set_current_sub_name($prev_sub_name);
       $self->_set_return_context($prev_return_context);

       die $caught_error if defined $caught_error;
       return $result;
   }
   ```

   The new `_emit_complex_sub_body` is the schedule-driven
   equivalent of the inline body-emission loop currently at
   C.pm:386-442. It's separate from `_emit_complex_method`
   because the sub case emits `static SV *` (not exported) and
   handles the `Constant->value() eq 'return'` last-stmt case.
   Shared logic between the two (RETVAL handling, the per-stmt
   loop) goes into a small shared helper (`_emit_complex_body_lines`?)
   if the duplication is non-trivial; otherwise duplicate the few
   lines and document the divergence.

   **Test gate for the try/catch invariant:** add a test that
   exercises the state-leak case. Compile a class with two subs
   where the first sub's body raises an exception during
   compilation; assert that the second sub's compilation sees a
   clean `_current_sub_name` and `_return_context` (i.e., not the
   first sub's leaked values). The test can use a deliberately-
   malformed sub body to force the exception path.

   The update needed at the caller (the loop in
   `_generate_c_files` currently at C.pm:1585-1604) is mechanical:
   ```perl
   # Before: $result = $self->_emit_sub($sname, $sparams, $sbody);
   # After:  $result = $self->_emit_sub($sub);
   ```
   Remove the `$sname` / `$sparams` / `$sbody` extraction at
   lines 1586-1589 (those reads are 7d-transitional per
   7c-proper's commit message; this removes them).

5. **Analysis helpers (all 9) rewrite to take `$schedule`** (per
   Question 5 answer: B — uniform schedule substrate):
   - `_has_early_return($schedule)` — walks all 'stmt' items
     EXCEPT the schedule's terminal synthetic-Return (the one
     that wraps the implicit fall-through value, if present);
     returns true if any walked item's node is a non-synthetic
     Return. Per the "Why the flat schedule walk is semantically
     equivalent" section above, branch-internal Returns ARE
     counted — they appear as their own 'stmt' items in the
     flat sequence between block_open/block_close markers, and
     a Return inside an if-branch IS an early return that
     requires the `xsreturn:` label.
   - `_body_contains_return($schedule)` — any 'stmt' item with a
     Return node (non-synthetic).
   - `_body_contains_bare_return($schedule)` — any 'stmt' item
     with a Return node whose inputs[1] is undef.
   - `_collect_var_decls($schedule)` — every 'stmt' item whose
     node isa VarDecl, collected.
   - `_collect_all_var_refs($schedule)` — walks every 'stmt'
     item's node and collects Constant nodes with `const_type
     eq 'variable'`. Recursive walk WITHIN each stmt node's
     `->inputs->@*` chain.
   - `_is_unambiguous_value_expr($node)` — node-level (signature
     preserved). Callers locate the relevant 'stmt' node from
     `$schedule->items` and pass its `->node` here.
   - `_is_bare_return_expr($node)` — node-level (signature
     preserved). Same calling-pattern note as
     `_is_unambiguous_value_expr`.
   - `_is_single_stmt_return_expr($node)` — node-level (signature
     preserved). Callers determine "single stmt" by checking
     `scalar grep { $_->kind eq 'stmt' } $schedule->items->@* == 1`,
     then pass that one item's `->node` here.
   - `_is_complex_method($schedule)` — schedule has block_open
     items, OR has more than one 'stmt' item, OR has 'stmt' items
     whose node is a control-flow primitive.

   None of these helpers RECURSE into `cfg_state` — they iterate
   `$schedule->items->@*` flat, descending into a stmt node's
   `inputs` for the var-ref / var-decl collection cases. The
   structured-block information they used to recover from
   `cfg_state` is already explicit in the schedule's `block_open`
   markers.

6. **Repair-mechanism handling** (decided post-Commit-1):
   - Repairs with zero counts: **delete**. Methods and their
     callers, plus any `_record_repair("name")` calls from Commit 1.
   - Repairs with non-zero counts: **document in commit message**
     why they survive. Port to schedule path if the new emission
     produces the same artifact; leave alone if it doesn't (the
     `_record_repair` call from Commit 1 then continues to
     monitor whether they fire post-migration).

7. **`_get_class_methods` / `_class_methods` cache** (populated by
   `_scan_class_methods` in 7c-proper): unchanged. The schedule
   path doesn't affect the pre-scan; the cache is read by
   `_emit_method_call_expr` during stmt emission.

### Commit 3 — `chore(target-c): document repair-counter audit outcome`

**Always ships, with conditional content based on Commit 2's
deletion decisions.** Two cases:

- **Case A: all repairs were dead, all deleted in Commit 2.**
  Commit 3 deletes the `%_repair_counters` field, the
  `_record_repair` method, the `repair_counters()` accessor,
  and `t/bootstrap/c-repair-coverage.t`. Commit message
  documents: "All N pre-migration repairs (`<list>`) showed
  zero fires across the corpus; deleted in Commit 2. Counters
  retired as monitoring infrastructure with nothing left to
  count."

- **Case B: at least one repair survived Commit 2.** Commit 3
  is a documentation commit (no production-code change) that
  amends the surviving counters with a comment explaining what
  they monitor and under what conditions they should fire.
  The counter infrastructure stays alive. Commit message
  documents: "Repairs `<list>` remain load-bearing; counters
  retained for ongoing monitoring." This avoids the v1 spec's
  "did Commit 3 ship?" ambiguity (S4 from reviewer iteration 1)
  — Commit 3 always lands; only its CONTENT varies.

Either way the branch has exactly 3 commits and the audit trail
is unambiguous.

## Risks

### Per-commit risks

**Commit 1:**
1. **Counter overhead may slow `bnf-target-c.t`.** Hash insert per
   repair fire; negligible compared to compilation time, but worth
   noting. Mitigation: the counters are localized (field on
   EmitHelpers); test runtime should be within noise.

**Commit 2:**

1. **Schedule walker doesn't replicate all cfg_lookup behavior.**
   Per audit Risk #1: cfg_lookup carries `loop_jump` (distinguishes
   postfix `next if X` from a real if-block), `then_stmts` /
   `else_stmts`, `iterator` / `list` for foreach, `scope` for
   variable resolution. The schedule path's equivalent is
   `EagerPinning::If.is_loop_jump`, `EagerPinning::Loop.iterator`/
   `.list`, etc.

   **Concrete pre-Commit-2 task (NOT "verify with tests" hand-wave):**
   Inspect each `_cfg_lookup{refaddr(...)}` read site in
   EmitHelpers (verified locations at current head: lines 574,
   603, 684, 734, 776, 1305) and for each cfg_state KEY read
   (e.g., `$state->{then_stmts}`, `$state->{iterator}`,
   `$state->{loop_jump}`), document the schedule_data field that
   provides the equivalent in the new path. Output as a
   six-row table (one row per cfg_lookup site, columns: site,
   cfg_state keys read, schedule_data field used, mapping
   notes). If any cfg_state key has no schedule_data equivalent,
   Commit 2 pauses until the scheduler provides one (out-of-7d
   concern; needs separate spec).

   **Where this lives:** Commit 2's commit message body OR a
   sibling design-amendment doc (`2026-05-25-phase-7d-schedule-data-coverage.md`).
   The 6-row table is small; commit-message-inline is fine if
   it stays under ~30 lines.

2. **The C-side foreach head is more involved than the Perl-side
   one.** Perl emits `for my $x (LIST) {` as a single line; C
   needs `{ AV *list = ...; for (IV _i = 0; _i < av_len(list)+1; _i++) { SV *x = *av_fetch(list, _i, 0); ...`,
   which means the block_open emits TWO open braces and the
   matching block_close must emit TWO close braces.

   **Why this doesn't violate `Chalk::IR::Schedule::is_balanced`'s
   invariant:** `is_balanced` (Schedule.pm:16-33) checks that
   each `block_open` has a matching `block_close` with the same
   `form` string in the schedule's item sequence — it does NOT
   check that the emitted C text contains symmetric braces.
   A single `block_open(form='foreach')` paired with a single
   `block_close(form='foreach')` is balanced regardless of how
   many C-side `{` / `}` each emits. The brace counting is the
   emitter's responsibility, not the schedule's invariant.

   **Mitigation:** model the foreach head as emitting the outer
   `{` and the inner `for(...) {`. The block_close handler for
   `form eq 'foreach'` emits both `}}` (one `}` for the for-loop,
   one `}` for the AV/iterator scope). Port the brace structure
   from the existing `emit_cfg_loop` foreach branch starting at
   EmitHelpers.pm:1083 (the chart-re-read injection is a SEPARATE
   concern starting around line 1207; that's tracked via the
   repair-counter mechanism, not the foreach-head port).

3. **(Retired in v2.)** Originally framed as "the flat
   iteration might miss branch-internal early returns." The
   "Why the flat schedule walk is semantically equivalent"
   section in Framing definitively shows that branch-internal
   stmts ARE seen by the flat walk, and that counting them as
   early returns IS the correct legacy-equivalent behavior. The
   risk Q1 raised has been resolved by the correctness
   invariant, not deferred. Helper-by-helper correctness is
   verified by the test gates listed in "Test gate updates from
   v2 revisions" (sub-state-leak test, VarDecl-with-control-init
   smoke test) plus the existing `bnf-target-c.t` byte-compat
   coverage.

4. **The simple-body shortcut migration changes the IR
   classification.** Pre-7d: `body->[0] isa Return` directly. Post-7d:
   the schedule may have a `block_open`/`stmt`/`block_close` triple
   even for trivially simple cases if `_expand_node` decided to.
   Verify by emitting Boolean.pm through both old and new paths
   and confirming the simple-body shortcuts still fire for the
   right methods. If the schedule wraps trivially-simple bodies in
   block markers, the shortcut detection needs adjustment.
   **Mitigation:** add `t/bootstrap/c-simple-body-shortcuts.t`
   asserting that a method with `method foo { 1 }` source emits
   `return newSViv(1)` via the schedule path (not the complex
   path's `RETVAL = newSViv(1); return RETVAL;`).

5. **`_emit_complex_method` signature change.** Pre-7d: takes
   `($name, $params, $body, $ir_return_type)`. Post-7d: takes
   `($name, $params, $schedule, $scheduler, $ir_return_type)`.
   Callers (only `_emit_method` and `_emit_sub`) update accordingly.
   No external test fixtures call it directly (verified by grep);
   if any do, they need updating. Mitigation: grep
   `_emit_complex_method` callsites before landing; update all.

6. **Pre-existing failures (`xs-polymorphic-dispatch.t` 59/60,
   `xs-int-specialization.t` 2/6) must not regress.** These predate
   7d; 7d must not make them worse. Mitigation: include in 7d test
   gates with explicit "expected count" assertions.

**Commit 3:**
1. **Premature deletion if a repair lurks.** Only ship Commit 3 if
   Commit 1's counters showed zero fires AND Commit 2 deleted the
   corresponding helpers. If any repair remains in EmitHelpers
   post-Commit-2, do NOT ship Commit 3 — the counters stay alive
   as monitoring.

### Cross-commit risk

**Bisect-friendliness.** Each commit individually should leave the
test suite in a known state:
- After Commit 1: same green/red as baseline + new (always-passing)
  c-repair-coverage.t.
- After Commit 2: same green/red as baseline (plus new
  c-simple-body-shortcuts.t green).
- After Commit 3: same green/red as Commit 2 minus the deleted
  c-repair-coverage.t.

If a Commit 2 regression surfaces later, `git bisect` between
Commit 1 and Commit 2 isolates the migration from the
instrumentation.

## Test gates

**Before Commit 1 (baseline capture):**
- Same gates as 7c-proper's final state. Pre-existing failure
  counts: xs-polymorphic-dispatch.t 59/60, xs-int-specialization.t
  2/6, build-chalk-so-generated fails at Phase 2.5 (StructPromotion).
- `bnf-target-c.t`: 178/178.
- `c-emit-helpers-inheritance.t`: 55/55.
- `xs-isa-inheritance.t`: 10/10.
- `xs-athx-no-args.t`: 7/7.
- All mop/*.t green at current counts.

**After Commit 1:**
- All above unchanged.
- New: `t/bootstrap/c-repair-coverage.t` passes (always; reports
  counts via diag).
- Diag output captured as evidence for Commit 2's deletion decisions.

**After Commit 2:**
- All above unchanged.
- New: `t/bootstrap/c-simple-body-shortcuts.t` passes (verifies
  simple-body detection still fires on trivial methods).
- `bnf-target-c.t` stays at 178/178 (the migration must not change
  C output for any class the test exercises).
- `c-emit-helpers-inheritance.t`: count drops by however many
  `can(...)` assertions reference deleted helpers (per repair
  deletions). Net change documented in commit message.

**After Commit 3 (if shipped):**
- Same as Commit 2 but c-repair-coverage.t is gone.
- `c-emit-helpers-inheritance.t`: count drops further if
  `repair_counters`-related `can` assertions exist.

## Acceptance

This design is approved when:

1. **Scope boundary against 7g is clear.** 7d migrates; 7g deletes
   the cfg_lookup/emit_cfg_* infrastructure that becomes
   unreachable. No "delete the old path NOW" in 7d.

2. **Simple-body shortcuts read the schedule.** Post-7d,
   `_emit_method` does NOT read `$method->body` at all (verified
   by grep).

3. **The repair-mechanism investigation is pre-migration, not
   post-hoc.** Commit 1 ships counters and Commit 2 reads them
   before deciding what to delete. No "we'll figure it out as
   tests fail" approach.

4. **Analysis helpers all migrate to schedule substrate in the
   same commit (Commit 2).** No half-migrated state where some
   helpers take `$schedule` and others take `$body`.

5. **The C-side foreach head migration is explicit about brace
   pairing.** The block_close handler for `form eq 'foreach'`
   closes both braces; the design's foreach-head section above
   spells this out.

6. **Pre-existing failures preserved at baseline counts.** No
   regression in xs-polymorphic-dispatch.t (59/60) or
   xs-int-specialization.t (2/6); no improvement either (those
   failures are out of 7d's scope).

7. **Bisect-friendliness.** Each of the three commits individually
   leaves the test suite in a known-good state per the test-gates
   section above.

User approval gate at brainstorming time (2026-05-25 — decisions
A/B/D/A/B per Q1-Q5). Implementation plan to follow via
writing-plans skill after spec-document-reviewer approval.

## Tracked: pre-emission fixup audit (Phase 7d-aux, future)

The post-emission textual repairs in EmitHelpers
(`_repair_stale_merge`, the chart-re-read patch in
`emit_cfg_loop`, `_fixup_xs_list_destructuring`, etc.) are not
the only suspicious-looking workarounds. `lib/Chalk/Bootstrap/Perl/Actions.pm`
carries a sibling set of **pre-emission fixups** —
`_fix_postfix_chain`, `_fix_postfix_chain_deep`,
`_push_deref_inward`, `_push_methodcall_inward`, and the related
PostfixDeref/MethodCall workarounds documented in the MEMORY.md
"Earley Stale-Value Merge Workarounds" section.

These patches operate on IR shape (not emitted text) and
exist for the same root cause: filter-gap-merge artifacts in
Earley's `add()` merging stale pre-merge values. They predate
the propagation fix shipped in Phase 7c-proper Commit 1
(`d58ad846`). Some have already been retired (per MEMORY.md:
"_unwrap_condition_corruption REMOVED — was stripping legitimate
subscripts that _fix_postfix_chain had correctly pushed in").
The remainder may be in a dead-or-load-bearing state similar to
EmitHelpers' post-emission repairs.

**Why this is NOT in 7d's scope:**
- Pre-emission fixups live in Actions.pm (the parser/semantic-
  action layer). They affect both Target::Perl and Target::C
  equally. They are not a Target::C body-emission concern.
- Including them would dilute 7d's "schedule-driven body
  emission" focus and double the implementation work.

**Tracked for Phase 7d-aux (separate brainstorm → spec →
execution cycle):**
Apply the same delete-if-dead instrumentation pattern from
7d's Commit 1 to the Actions.pm fixup sites:
- Identify each fixup (initial inventory: `_fix_postfix_chain`,
  `_fix_postfix_chain_deep`, `_push_deref_inward`,
  `_push_methodcall_inward`; complete inventory done in 7d-aux's
  brainstorm).
- Instrument each with a fire counter.
- Run the full test suite and the bnf-target-c corpus.
- Dead fixups get deleted. Live ones get understood-then-decided
  (port forward, fix at parser source, or document why they
  remain load-bearing).

**When:** after 7d ships. Phase 7d-aux's brainstorm should
happen before Phase 7e (which migrates the test-helpers and
hand-built tests) because the audit may surface parser-layer
issues that the test migration would otherwise paper over.

## Resolved open questions (post-review iteration 1)

The spec's v1 deferred several decisions to "open question."
Reviewer correctly flagged that some of these are decisions, not
questions. Resolved here:

1. **Scheduler coverage of every node type Target::C currently
   emits.** ANSWER (decision, not question): Risk #1's mitigation
   is the implementation step. Before Commit 2, run
   `t/bootstrap/scheduler/schedule-data-*.t` AND inspect each
   `_cfg_lookup` read site in EmitHelpers (lines 574, 603, 684,
   734, 776, 1305 — verified against current head) to confirm
   the corresponding `schedule_data` field exists. The audit
   doc's claim that schedule_data covers cfg_lookup is plausible
   but unverified at spec-writing time; the cross-reference is
   Commit 2's first task. If a missing field surfaces, the
   migration pauses for the scheduler to gain that field —
   that's an out-of-7d concern. Document any such finding in the
   7d completion notes.

2. **VarDecl whose init is a control-flow node** (If/Loop/TryCatch).
   ANSWER: **yes, Target::C MUST replicate Perl.pm's
   `_expand_node` recursion.** Per Perl.pm:260-286, when a
   `synthetic` Return wraps a value that is itself a control
   node, the emitter recursively expands the control node through
   the scheduler to get the structured block_open/.../block_close
   sequence, then replays each sub-item through
   `_emit_schedule_item`. The C path must do the same in
   `_emit_c_schedule_item` for the same reason — emitting a
   control-flow node as a bare expression (the implicit
   fall-through return form) requires the structured-block
   expansion.

   Implementation: `_emit_c_schedule_item` checks if the 'stmt'
   case's node is a synthetic Return whose value is an
   If/Loop/TryCatch; if so, recursively expands via
   `$scheduler->_expand_node($val)` and replays each sub-item
   through `_emit_c_schedule_item`. Mirrors Perl.pm:260-286.

3. **Is `_emit_sub` a thin wrapper around `_emit_complex_method`?**
   ANSWER: **no**. Verified at C.pm:337-455. `_emit_sub`
   duplicates the complex-method logic inline with three
   differences: (a) the try/catch save/restore wrapper for
   `_current_sub_name` and `_return_context`; (b) the
   `Constant->value() eq 'return'` last-stmt case; (c) the
   `static SV *` (not exported) function template. The 7d
   migration produces `_emit_complex_sub_body` separate from
   `_emit_complex_method`; shared helpers extracted only if
   duplication is non-trivial.

4. **Repair counters: per-method or per-emission-pass?** ANSWER:
   **per-pass with per-repair name**. Each repair counter
   accumulates across all methods/subs in one
   `_generate_c_files` call. The test
   (`c-repair-coverage.t`) resets the counters before each
   `_generate_c_files` call on each corpus file, then reports the
   total per repair. Per-method counters would be overkill for
   the "is this dead?" question; per-pass is enough evidence
   to inform Commit 2's deletion decisions.

## Test gate updates from v2 revisions

In addition to the gates in the "Test gates" section above,
v2's revisions add:

- **Sub-state-leak test:** verifies `_emit_sub`'s try/catch
  save/restore preserves `_current_sub_name` and
  `_return_context` across a compilation exception. Add as
  `t/bootstrap/c-sub-state-leak.t`. Required before Commit 2
  lands.

- **VarDecl-with-control-init smoke test:** verifies
  `_emit_c_schedule_item` correctly handles a synthetic Return
  wrapping a control-flow node value. Either find an existing
  corpus method that exercises the pattern or construct a
  minimal MOP fixture. Required before Commit 2 lands.

- **cfg_lookup → schedule_data cross-reference report:** a
  one-time analysis (not a test) documenting which cfg_lookup
  field each EmitHelpers read site needs and which
  schedule_data field provides the equivalent. Captured in the
  Commit 2 message or in a sibling design-amendment doc.
