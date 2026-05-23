# SoN Scheduler — Design

**Date:** 2026-05-24
**Status:** Design. No code in this session. Implementation in follow-up.
**Branch:** `fixup-audit-baseline`
**Prep doc:** `docs/plans/2026-05-23-son-scheduler-prep.md`
**Predecessor design:** `docs/plans/2026-02-23-sea-of-nodes-cfg-design.md`
(lines 165-188, "XS Target: From Tree-Walk to Graph Scheduling")
**Supersedes:** `docs/plans/2026-02-23-eager-pinning-cfg-statements.md`
(cfg_state-based approach; cfg_state side-channel was deleted in Phase
3a-infra)

## Decisions (the 4 open questions, settled)

A summary up front so a reader can stop here if they only need the
decisions. Rationale for each appears in the relevant section below.

| # | Question | Decision |
|---|---|---|
| A | Eager pinning vs nesting-tree GCM | **Eager pinning.** Phase 3d already pinned every side-effect node to its control predecessor via `inputs[0]`. The scheduler walks that pinning; it does not recompute placement. |
| B | Source-form for `for` / `while` / `until` | **Preserve `foreach` vs `while`; normalize `until` to `while !cond`.** `foreach` carries iterator/list annotations on the Loop; `while` does not. `until`'s negation is already baked into the IR (PostfixModifier wraps the condition in `!`), so the distinction is unrecoverable and we accept the loss. C-style `for(init; cond; step)` emits as `for` when the pre-init VarDecl is recognizable; otherwise as `{ init; while(cond) { ...; step } }`. |
| C | `MOP::Method->body` lifecycle | **Delete entirely**, but only after the scheduler ships and the codegen MOP path is migrated. `body` exists today because codegen needs a statement list; once codegen consumes a schedule, `body` has no callers. Do not keep it as a debug aid — debug tooling belongs in a separate dumper. |
| D | Order of operations | **Scheduler first, then incremental codegen migration.** Build `Chalk::IR::Scheduler` as a new module that consumes a `MOP::Method`/`MOP::Sub` and produces a typed schedule. Add a second `_generate_from_schedule` path next to `_generate_from_mop` in `Target::Perl`. Once both produce byte-identical output across the golden corpus, switch over and delete `_generate_from_mop` + `body`. |

## 1. Scope

### What the scheduler does

The scheduler takes one `MOP::Method` or `MOP::Sub` and produces a
**Schedule**: a linear sequence of *Schedule Items*, each of which
either:

- emits a *statement* (a single side-effect IR node, with implicit
  data-flow dependencies via `inputs`), or
- opens / closes a *structured control block* (`if`/`else`/`elsif`,
  `while`, `for`, `foreach`, `try`/`catch`) annotated with the IR
  nodes that determined its shape (the controlling `If`, `Loop`,
  `TryCatch`, and their `Phi` merges).

The schedule is the input that codegen consumes; codegen no longer
walks `body`, no longer consults `cfg_state`, no longer needs the
refaddr-keyed `_cfg_lookup` side-table.

### Input contract

- A `MOP::Method` (or `MOP::Sub`) carrying:
  - `$graph` — a `Chalk::IR::Graph` whose `nodes()` returns all
    reachable IR nodes (effect chain + data flow + CFG control
    nodes) for this method.
  - `$params` — for emit context (`$self`, named params).
  - `$return_type` — for emit context.
  - `$lexical_bindings` — for VarDecl emission ordering.

The scheduler does **not** read `$body`. (It may not even exist by
the time the scheduler is callable; see Phase 5 below.)

### Output contract

A `Chalk::IR::Schedule` value, with a stable shape:

```
Schedule := [ Item, Item, ... ]

Item := { kind => 'stmt', node => $ir_node }
      | { kind => 'block_open', form => $form, meta => {...} }
      | { kind => 'block_close', form => $form }
      | { kind => 'else' }
      | { kind => 'elsif', meta => {...} }
      | { kind => 'catch', meta => {...} }
```

`$form` ∈ `qw(if while for foreach try)`. `meta` carries the
controlling IR node refs (`If`, `Loop`, `TryCatch`) and any
emit-time hints (foreach iterator + list nodes, for-init/for-step
references) that codegen needs without re-walking the graph.

A schedule is **flat** — nested control is represented by
matched `block_open`/`block_close` pairs in the sequence. This
mirrors how the codegen already emits (via `_emit_node` over a
statement list with the outer code recursing through `emit_cfg_*`);
flattening removes the recursion from the scheduler itself.

### What the scheduler does NOT do

The Click 1995 paper distinguishes scheduling from optimization;
the prep doc reiterates this. We hold that line:

- **No GVN.** Hash consing in `Graph::merge` already gives us
  per-method content-addressed dedup. Cross-method GVN is a
  separate pass.
- **No DCE.** Reading `inputs[0]` walks reachable nodes; unreachable
  nodes are simply absent from the schedule. There is no separate
  liveness pass.
- **No hoisting / sinking.** Eager pinning means every side-effect
  node stays in the block it was constructed in. Hoisting requires
  the kind of placement freedom that nesting-tree GCM gives, and we
  explicitly do not need that for byte-compat-with-source codegen.
- **No loop normalization, no `until` recovery.** `until` is already
  baked as `while !cond` in IR; the scheduler emits whatever shape
  the IR carries.

These are not the scheduler's job. They are downstream optimization
passes that may or may not exist, that operate on the graph before
or after scheduling.

## 2. Algorithm

### Why eager pinning, not GCM (Decision A)

The Click GCM algorithm needs a dominator tree because it does
late-binding placement: nodes float through the graph until they
hit their pinned dependencies, then they're placed at the latest
control point that still dominates all their uses.

Chalk doesn't need that. The IR comes out of a structured-source
parser. Every side-effect node is constructed *inside* a specific
block, by a specific semantic action, with a specific predecessor.
Phase 3d's Block control-chain fixup pass already writes that
predecessor into `inputs[0]`:

- For `VarDecl`, `Return`, `Unwind`, `Call`, `Assign`, `CompoundAssign`,
  `RegexSubst` — `inputs[0]` is the previous side-effect node in the
  same block, or `Start` for the first.
- For `If`, `Loop`, `TryCatch` — `inputs[0]` is the previous side-effect
  node, set by the same fixup pass via `set_control_in`. The post-
  control of an `If` is `$if->region`; of a `Loop` is `$loop->region`.

This is precisely the "tag each IR node with its control region at
creation time" that the Feb 23 conversation labeled *Eager Pinning*
(the Turboshaft / V8 approach). We don't need to recompute it —
it's the wiring we already have.

The scheduler's job, therefore, is **not** to decide where nodes go.
It is to **walk the existing pinning and emit a linear order**.

### Two-phase scheduling

Phase 1 — **chain walk**. Starting from the unique `Return` (or
`Unwind`) node in the method's graph, walk backward via
`inputs[0]` collecting side-effect nodes into a list. Reverse the
list to get source order. This produces the **top-level statement
sequence** for the method body.

Phase 2 — **structured expansion**. For each statement in the
top-level sequence, dispatch on type:

- Plain side-effect node (`Call`, `Assign`, `VarDecl`, `Return`,
  ...) → emit one `{ kind => 'stmt' }` item.
- `If` node → emit `{ kind => 'block_open', form => 'if', ... }`,
  recurse into the true branch (chain walk + structured expansion
  starting from the node whose `control_in` is the `TrueProj`,
  stopping at the `Region` join), emit any `{ kind => 'else' }` or
  `{ kind => 'elsif' }` items, recurse into the false branch,
  emit `{ kind => 'block_close' }`.
- `Loop` node → emit `{ kind => 'block_open', form => 'while' or
  'foreach' or 'for', ... }`, recurse into the body (chain walk
  starting from the node whose `control_in` is the loop's
  `body_proj`, stopping at the `Loop`'s backedge), emit
  `{ kind => 'block_close' }`.
- `TryCatch` node → emit `{ kind => 'block_open', form => 'try' }`,
  recurse into the try body, emit `{ kind => 'catch', ... }`,
  recurse into the catch body, emit `{ kind => 'block_close' }`.

### Chain-walk primitive (the one operation the scheduler needs)

```
sub chain_segment($start_node, $stop_predicate) {
    my @nodes;
    my $cur = $start_node;
    while (defined $cur && !$stop_predicate->($cur)) {
        last if $cur->isa('Chalk::IR::Node::Start');
        push @nodes, $cur;
        $cur = $cur->control_in();  # NB: virtual via inputs[0] override on CFG nodes
    }
    return reverse @nodes;
}
```

This is the same shape as `_body_from_graph` in `Target/Perl.pm`,
generalized with a stop predicate so it can walk segments rather
than whole-method chains. The top-level walk uses
`$stop = sub { $_[0] isa Start }`; the if-branch walk uses
`$stop = sub { $_[0] == $if->region }`; the loop-body walk uses
`$stop = sub { $_[0] == $loop }` (because the backedge points back
to the Loop header).

### Complexity

Each IR node appears in exactly one chain segment, so each is
visited O(1) times. Total work is O(n) where n is the number of
side-effect nodes in the method. There is no dominator-tree
construction, no fixed-point iteration, no work-list. This is the
selling point of the eager-pinning approach — it inherits its O(n)
bound from the fact that the graph is already a series of linear
chains stitched together at If/Loop/TryCatch joins.

### Edge case: side-effect-free expression in statement position

Possible today: a method whose only body is `42;`. The parser
synthesizes a `Return(synthetic => true)` with a Constant input.
The chain walk from `Return` finds no intermediate side-effect
nodes (Return's `inputs[0]` is `Start`). The scheduler emits a
single `{ kind => 'stmt', node => $return }` item; codegen sees
the synthetic flag and emits a bare `42;` instead of
`return 42;`. The current `_is_explicit_exit` predicate moves
directly across to the schedule consumer.

### Edge case: dead branches inside a structured block

If the IR contains an `If` whose `TrueProj` chain is empty (e.g.
`if ($cond) {}`), the chain walk from `TrueProj`'s consumer
yields an empty segment. The scheduler still emits `block_open`
and `block_close` around an empty body. This matches existing
codegen behavior for empty blocks.

### Edge case: nested If inside a Loop body

The Loop body chain walk visits an `If` node. Phase 2 dispatch
recognizes it as a control node and recurses into structured
expansion. The recursion bottoms out at the `If`'s `Region`,
which is **not** the Loop's stop predicate's target, so the
chain walk continues past it through whatever comes next in
the loop body. This is why the stop predicates are
**identity-based** (`== $specific_node`) rather than type-based.

## 3. Structured reconstruction patterns

The scheduler emits `{ kind => 'block_open', form => $form, meta => ... }`;
codegen reads `$form` and `meta` to choose the surface syntax. The
patterns below specify what each `(if|while|for|foreach|try)` block
in the schedule corresponds to in IR-graph shape, so the
implementation can verify it.

### Pattern: If + Region → `if` / `if`-`else` / `if`-`elsif`-`else`

IR shape:

```
... → If(ctrl, cond) → { TrueProj(0), FalseProj(1) }
        ↓                       ↓
    [chain segment]      [chain segment]
        ↓                       ↓
        Region(true_exit_ctrl, false_exit_ctrl)
```

`If->region` is the joining `Region`. Both branches' chain
segments terminate at that `Region`.

Schedule emit:

```
{ kind => 'block_open', form => 'if', meta => { if_node => $if } }
  ... true-branch items ...
{ kind => 'else' }                                                   # only if false-branch nonempty
  ... false-branch items ...
{ kind => 'block_close', form => 'if' }
```

#### `elsif` recognition

If the false branch chain is exactly *one* `If` node and that
`If`'s `Region` matches the outer `If`'s `Region` (the two
joins are the same merge point), emit `{ kind => 'elsif', ... }`
in place of `{ kind => 'else' }` followed by `{ kind => 'block_open' }`.

This is identical to the elsif recognition in
`emit_cfg_if`/`Target/Perl.pm:1102-1118`, just lifted out of
the emitter into the scheduler so codegen doesn't have to
re-derive it.

#### `unless`

The parser does *not* normalize `unless` to `if !cond`. If we
ever add such normalization in IR, the scheduler doesn't need
to change — it would emit `if`, and the IR-level normalization
would have lost the source distinction. Today: the `If` node
carries a marker (or the condition is wrapped in a `!`
distinguishable from `unless` by source-position annotation)
that codegen reads. **Scheduler is form-agnostic; codegen
makes the surface-syntax choice.**

#### Loop-jump shortcut (`next if`, `last unless`)

The current `_emit_loop_jump` emits `next if $cond;` for an `If`
inside a Loop body when the `If` is marked `loop_jump`. This is
a codegen surface choice, not a scheduler structural choice.
The scheduler still emits the `If` as a normal `block_open`
sequence; codegen sees the `loop_jump` annotation on the `If`
(carried via the Context annotations the parser already wires
up) and collapses the block to a one-liner. **Move the
`loop_jump` annotation off Context and onto the `If` node
itself** as part of Phase 1 (see Implementation phases) so the
scheduler / codegen don't depend on Context after the cutover.

### Pattern: Loop + If + Region → `while`

IR shape:

```
... → Loop(entry_ctrl, backedge_ctrl) → If(Loop, cond) → BodyProj(0)
                                                       → ExitProj(1)
                                                          ↓
                                                       Region(ExitProj)
```

`Loop->region` is the post-loop merge. The `body_proj` is the
control input for body statements; `exit_proj` is the entry
control for the post-loop continuation.

Schedule emit (while):

```
{ kind => 'block_open', form => 'while', meta => { loop => $loop, cond => $cond } }
  ... body items, found by chain walk from $body_proj's first consumer
      with stop predicate "== $loop" ...
{ kind => 'block_close', form => 'while' }
```

The body chain walk stops at the `Loop` node itself because the
last body statement's `control_in` is wired back to `Loop` via
`set_backedge_ctrl`.

### Pattern: Loop + iterator/list metadata → `foreach`

Same IR shape as `while`. The difference is on the Loop **node's
parse-time annotations**: `iterator` (a Constant node holding the
variable name like `$n`) and `list` (the list expression IR node
or arrayref of element nodes).

Today these annotations live on the parsing Context
(`update_annotations`); the codegen reads them via
`_build_cfg_lookup` and `cfg_state`. For the scheduler we need
them on the **Loop node** directly. Phase 1 of implementation
moves them.

Schedule emit (foreach):

```
{ kind => 'block_open', form => 'foreach',
  meta => { loop => $loop, iterator => $iter, list => $list } }
  ... body items ...
{ kind => 'block_close', form => 'foreach' }
```

### Pattern: VarDecl(s) + Loop → C-style `for`

Source: `for (my $i = 0; $i < 10; $i++) { ... }`.

IR shape (today, after Phase 3e): the for-init VarDecl lands in
the *enclosing* block's chain, immediately before the `Loop`. The
`Loop`'s condition tests `$i`. The "step" expression appears as
the last statement in the body (the parser wires it there).

Recognizing this as a `for` instead of `{ VarDecl; while }`
requires a node-level annotation on the Loop:
`for_style => 1`, set by `ForStatement` action and absent on
`WhileStatement` / `ForeachStatement`.

Schedule emit:

```
{ kind => 'block_open', form => 'for',
  meta => { loop => $loop, init => $init_vardecl, step => $step_node } }
  ... body items, excluding $step ...
{ kind => 'block_close', form => 'for' }
```

The init VarDecl is still in the enclosing chain at chain-walk
time; the scheduler **must** remove it from the enclosing chain
and attach it to the Loop's meta when it recognizes the for-style
pattern. The step node is the last body-chain item; same
treatment.

**This is the one place where the scheduler does graph rewriting
during walk**, and it's the price we pay for source-form
preservation. The rewriting is local (one chain entry moved into
meta) and reversible (codegen could emit the desugared form by
ignoring `for_style`).

If the for-init/step recognition fails (e.g. the init isn't a
single VarDecl), emit the desugared `{ VarDecl; while; }` form.
Correct, not pretty.

### Pattern: TryCatch + chain → `try` / `catch`

IR shape (current): `TryCatch` node with `inputs[0] = control_in`,
plus side-channel annotations `try_stmts`, `catch_var`,
`catch_stmts` on the Context.

Same migration as foreach iterator/list: move the annotations
onto the `TryCatch` node directly, then the scheduler reads them
without Context dependency. The `try_stmts` and `catch_stmts`
become chain segments rooted in nodes whose `control_in` is the
TryCatch's two output projections (or whatever the IR shape is
post-migration; today these aren't proper Projs, and that's a
bug-class hazard we should fix as part of Phase 1).

Schedule emit:

```
{ kind => 'block_open', form => 'try', meta => { try => $try } }
  ... try-body items ...
{ kind => 'catch', meta => { var => $catch_var } }
  ... catch-body items ...
{ kind => 'block_close', form => 'try' }
```

### Pattern not listed: `do { ... } while/until`

Not implemented today. The IR currently has no `do_while` node
and no parser action; if Chalk acquires one, the scheduler gains
a corresponding `{ form => 'do_while' }`. Out of scope.

## 4. Phi → variable mapping

Phi nodes appear at:

- **If joins.** A variable that was assigned in the then-branch
  and/or the else-branch becomes a `Phi(region, then_val, else_val)`
  in the post-if scope.
- **Loop headers.** A variable that gets reassigned in the body
  becomes a `Phi(loop, entry_val, backedge_val)` in the loop body's
  scope.

### Existing emit strategy (`emit_cfg_phi_if`)

`Target/Perl.pm:1137-1156` emits an if-Phi as:

```perl
my $_phi_<id>;
if ($cond) {
    $_phi_<id> = $val_a;
} else {
    $_phi_<id> = $val_b;
}
```

This works for codegen-level correctness but generates `$_phi_*`
synthetic identifiers, which is bad for byte-compat with hand-
written source.

### Target strategy: Phi → declared-variable slot

Most Phi nodes in real code come from `my $x = ...; if (...) { $x = ...; }`.
The pre-existing VarDecl already declares `$x`. The Phi's emit
slot should reuse `$x`, not synthesize `$_phi_42`.

The scheduler resolves Phi → emit-slot mapping by walking the
Phi's `inputs` for the most-recent VarDecl that names the same
variable. That VarDecl is the slot. The scheduler attaches a
`{ kind => 'stmt', node => $vardecl, role => 'phi_slot', phi => $phi }`
hint to the chain item, telling codegen to *initialize* the slot
with the Phi's pre-control input value. Inside the if-branches,
the assignments stay as plain `Assign` nodes; the Phi itself
isn't emitted as a separate statement.

### Loop-Phi → loop-carried variable

For a `Phi(loop, entry, backedge)` where `entry` is a value from
before the loop and `backedge` is the body's assigned value, the
emit slot is again the pre-loop VarDecl. The body's assignment to
that variable is what produces the backedge value. No separate
emission of the Phi is needed.

### When no VarDecl exists for the Phi

Possible only for synthetic Phis introduced by future optimization
passes. The scheduler falls back to `$_phi_<id>` naming. We never
hit this in the byte-compat corpus (Phi-slot recovery is the
common case).

### Concrete example

Source:

```perl
my $x = 0;
if ($cond) { $x = 1; } else { $x = 2; }
return $x;
```

IR (sketched):

```
Start → VarDecl($x=0) → If(cond) → TrueProj → Assign($x, 1) → Region
                                  → FalseProj → Assign($x, 2) →  ↗
                                  Phi(Region, 1, 2) for $x
                                  → Return(Phi($x))
```

Schedule:

```
{ kind => 'stmt', node => VarDecl($x=0) }                  # codegen: my $x = 0;
{ kind => 'block_open', form => 'if', meta => {...} }
  { kind => 'stmt', node => Assign($x, 1) }                # codegen: $x = 1;
{ kind => 'else' }
  { kind => 'stmt', node => Assign($x, 2) }                # codegen: $x = 2;
{ kind => 'block_close', form => 'if' }
{ kind => 'stmt', node => Return(Phi) }                    # codegen: return $x;
                                                            # — Phi resolves to $x because
                                                            # the slot map says so
```

The Phi is **not** emitted as a statement; it's a *value* that the
return reads. The Phi-slot map ensures `$x` is the surface
identifier.

## 5. What `MOP::Method->body` becomes (Decision C)

**`MOP::Method->body` is deleted**, along with `MOP::Sub->body`
and the population code in `Perl::Actions` that maintains them.

Today's `body` exists because:
1. The parser's `Block` action collected statement nodes.
2. The codegen needed a statement list to iterate.

With the scheduler, (2) goes away — codegen iterates the
schedule. And (1) is redundant — the chain walk recovers the
statement list from the graph.

The right time to delete `body` is after Phase 5 of the
implementation (see below): after codegen is on the schedule
path *and* the byte-compat goldens still pass.

There is no debug-aid argument worth keeping `body` for. If
debugging needs a statement-list dump, write a 30-line dumper
that runs `Chalk::IR::Scheduler` and prints the result. Don't
keep parallel state in the MOP forever.

## 6. What `MethodInfo` / `ClassInfo` / `SubInfo` becomes

These three classes (`lib/Chalk/IR/MethodInfo.pm`,
`lib/Chalk/IR/ClassInfo.pm`, `lib/Chalk/IR/SubInfo.pm`) exist as
the *legacy emit-shaped wrappers* that pre-MOP codegen consumed.
The current MOP path (`_generate_from_mop`) synthesizes them at
runtime so it can call the existing `_emit_class_decl` /
`_emit_method_decl` / `_emit_sub_decl` helpers unchanged.

After the scheduler ships and codegen switches to consuming
schedules + MOP entities directly:

- `_emit_class_decl($class_info)` becomes
  `_emit_class($mop_class)` — reads name/parent/fields/methods
  from the MOP::Class directly.
- `_emit_method_decl($method_info)` becomes
  `_emit_method($mop_method, $schedule)` — reads name/params
  from MOP::Method and iterates the schedule.
- `_emit_sub_decl($sub_info)` becomes `_emit_sub($mop_sub, $schedule)`.
- `_emit_field_decl($field_info)` becomes `_emit_field($mop_field)`.

`MethodInfo` / `ClassInfo` / `SubInfo` / `FieldInfo` (and
`UseInfo`, by parallel reasoning) are **deleted** in Phase 6.

This is the right time for that deletion because:
- The scheduler-driven codegen path doesn't need them.
- The `_generate_from_mop` synthesis goes away when the synth
  path is replaced by direct MOP traversal.
- The legacy `_emit_program` path (Program IR + `_generate_with_cfg`)
  also goes away — `Program` and `IR::ClassInfo` are part of the
  pre-Phase-4 design and shouldn't survive Phase 4 finish-up.

## 7. Implementation phases

Each phase produces commits independently testable against the
existing byte-compat golden corpus
(`t/bootstrap/mop/codegen-byte-compat.t`). No phase regresses the
goldens. The "rough effort" estimates are for one focused session
at the bench; treat as ranges.

### Phase 1 — Annotation cleanup (preparation, no scheduler yet)

**Goal:** Move per-control-node annotations from Context onto IR
nodes, so the scheduler reads from IR alone.

**Concrete moves:**
1. `iterator`, `list` from Context annotations onto `Loop` node
   as `field $iterator :reader; field $list :reader;`. Set in
   `ForeachStatement` action.
2. `loop_jump` from Context annotations onto `If` node as
   `field $loop_jump :reader = undef;`. Set in `PostfixModifier`
   action when the loop-jump form is detected.
3. `for_style` flag on `Loop` node as `field $for_style :reader = false;`.
   Set in `ForStatement` action.
4. `try_stmts` / `catch_stmts` / `catch_var` from Context
   annotations onto `TryCatch` node. (Today `TryCatch` is almost
   empty — just an `operation` method. It needs real fields and a
   proper structure: control inputs for try-region and
   catch-region, a `var` for the caught exception name. This is a
   small but real IR change.)

**Test gate:** byte-compat goldens pass. The codegen's existing
`cfg_state` reader is *still* in use during Phase 1 — we move the
data into the IR alongside the side-channel population, not in
place of it. This is the safe order: add a new source-of-truth,
keep the old one wired, then in Phase 2 the scheduler reads the
new source.

**Effort:** 1 session.

**Risk:** Low. The IR fields are additive; the Context
annotations stay too. Failures look like missing-field accessors
or set-to-undef being treated as set.

### Phase 2 — Schedule data type + Phase 1 verification

**Goal:** Define `Chalk::IR::Schedule` and `Chalk::IR::Schedule::Item`
as data types. No producer yet; just the shape and trivial
constructors. Write a few hand-built `Schedule` fixtures and
unit-test their structure (e.g., open/close balance).

**Concrete files:**
- `lib/Chalk/IR/Schedule.pm` — class with `field @items :reader`
  and `method push_item($item)`.
- `lib/Chalk/IR/Schedule/Item.pm` — class with `field $kind :param :reader;
  field $form :param :reader = undef; field $node :param :reader = undef;
  field $meta :param :reader = {};`.

**Test gate:** new `t/bootstrap/scheduler/schedule-shape.t` —
hand-built schedules round-trip through items.

**Effort:** 0.5 session.

**Risk:** Trivial.

### Phase 3 — Scheduler producer (straight-line bodies only)

**Goal:** `Chalk::IR::Scheduler->schedule($method)` produces a
schedule for methods that contain only side-effect statements +
Return (no `if`, no loops, no try). The chain walk from the
Return; no structured expansion.

**Concrete files:**
- `lib/Chalk/IR/Scheduler.pm` — class with `method schedule($method)`
  returning a `Chalk::IR::Schedule`. Implements the chain-walk
  primitive and the straight-line case.
- `t/bootstrap/scheduler/straight-line.t` — feeds methods with
  only VarDecl/Assign/Call/Return through the scheduler and
  asserts schedule equals expected fixture.

**Test gate:** new test passes; byte-compat goldens still pass
(they don't use the scheduler yet).

**Effort:** 1 session.

**Risk:** Low. The chain walk is the same shape as
`_body_from_graph`, which already works.

### Phase 4 — Scheduler structured expansion (if + loop + try)

**Goal:** Scheduler handles `If`/`Loop`/`TryCatch` via Phase 2
structured-expansion logic. After this phase the scheduler is
**complete** for the existing IR shape.

**Concrete files:**
- `lib/Chalk/IR/Scheduler.pm` — extended.
- `t/bootstrap/scheduler/if-else.t`,
  `t/bootstrap/scheduler/while-loop.t`,
  `t/bootstrap/scheduler/foreach-loop.t`,
  `t/bootstrap/scheduler/for-style.t`,
  `t/bootstrap/scheduler/try-catch.t`,
  `t/bootstrap/scheduler/nested.t` — fixture tests for each
  pattern.

**Test gate:** all new scheduler tests pass; byte-compat goldens
still pass.

**Effort:** 2 sessions (one for if/loop/try, one for nested + for-style).

**Risk:** Medium. The `for_style` recognition is the tricky case
because it requires moving init/step from chain into meta.

### Phase 5 — Codegen consumes schedule (new path, opt-in)

**Goal:** Add `_generate_from_schedule($mop)` to
`Target::Perl`, parallel to `_generate_from_mop`. New path:
- For each MOP::Class, iterate methods.
- For each method, build a schedule via the scheduler.
- Emit code by walking the schedule (linear iteration with a
  block-open/close stack for indentation).
- Emit Phi-slot resolutions per Section 4.

Add a build-time switch or a test-only call site that exercises
the new path against the same goldens.

**Test gate:** new path produces byte-identical output against
the byte-compat golden corpus. Add a parallel test
`t/bootstrap/mop/codegen-byte-compat-schedule.t` that runs the
same comparison via the schedule path.

**Effort:** 2-3 sessions.

**Risk:** Medium-high. Output divergence between paths is where
real bugs hide. The mitigation is the side-by-side comparison
test, run on every fixture.

### Phase 6 — Switchover

**Goal:** Make schedule-driven path the default. Delete:
1. `_generate_from_mop` (synthesis layer).
2. `_generate_with_cfg` and `_build_cfg_lookup` and
   `_cfg_lookup` and `cfg_state()` reader.
3. `_body_from_graph` (replaced by scheduler chain walk).
4. `emit_cfg_if`, `emit_cfg_loop`, `emit_cfg_try_catch`,
   `emit_from_cfg_state`, `_emit_loop_jump`, `emit_cfg_phi_if`
   (replaced by schedule-walking emit).
5. `MOP::Method->body`, `MOP::Sub->body`, and the population
   code in `Perl::Actions`.
6. `MethodInfo`, `ClassInfo`, `SubInfo`, `FieldInfo`, `UseInfo`,
   `Program`, and the `_emit_program` /
   `_emit_*_decl(InfoStruct)` helpers — replaced by direct
   MOP traversal.

**Test gate:** all existing tests pass. Goldens unchanged. The
codebase is meaningfully smaller (we expect ~30-40% reduction
in `Target/Perl.pm`).

**Effort:** 1-2 sessions, mostly deletion + test sweep.

**Risk:** Low if Phase 5 was thorough. The deletes are
mechanical; misses show as failing tests.

### Phase 7 — XS / C target migration (separate plan)

The `Bootstrap::Perl::Target::C` and any future XS target take
the same approach: replace tree-walking with schedule-walking.
This is a separate session's work; this design doc establishes
the schedule contract so the C target can target it without
re-deciding the shape.

**Out of scope for the schedule design.** The schedule is
*target-agnostic*; what each target does with `{ form => 'while' }`
is its own concern.

## 8. Test strategy

### Primary regression gate: byte-compat golden corpus

`t/bootstrap/mop/codegen-byte-compat.t` already exists and runs
`generate($mop)` against ~N captured `*.pl.golden` files in
`t/fixtures/codegen-goldens/`. The schedule-driven path **must
not change golden output**. Any byte-level difference is either
a scheduler bug or an intentional change (in which case the
golden gets updated explicitly).

**Side-by-side comparison test (Phase 5):** new test file
`t/bootstrap/mop/codegen-byte-compat-schedule.t` runs the same
fixture-set through `_generate_from_schedule` and compares to
the same goldens. The two-test setup means we catch divergence
during the migration window.

### Scheduler unit tests

For each structured pattern (Phase 4), a small focused fixture:

- Build a `MOP::Method` programmatically with a known IR shape.
- Call `Chalk::IR::Scheduler->schedule($method)`.
- Assert the resulting schedule equals an expected sequence of
  items.

Compared to running the full parse pipeline, this isolates
scheduler logic from parser changes and gives readable failure
messages when the schedule shape drifts.

### Property: open/close balance

A schedule is well-formed iff every `block_open` has a matching
`block_close` of the same `form`, and the `else`/`elsif`/`catch`
items appear only between matched open/close pairs. Write one
test that asserts this property over every fixture's output.
Catches structural bugs (missed `block_close`) without depending
on emit specifics.

### Property: chain coverage

A second property test: every side-effect node in
`$method->graph->nodes()` appears as a `{ kind => 'stmt', node => $n }`
in the schedule (modulo for-init/for-step which get folded into
meta). No side-effect node is missing; no node is emitted twice.
This catches the bugs that the Phase 3d audit found.

### Performance check

The scheduler is O(n). A regression test that schedules the largest
method in the golden corpus and asserts a wall-clock budget (say,
< 5ms) prevents accidental quadratic behavior creeping in. Not a
sharp bound — just a sanity check.

### Anti-test: don't test what we'll change

We will NOT lock in the specific Phi-slot naming convention or
the for-style recognition as exhaustive tests. Those are
implementation details that future work may revise. We test
*outputs* (byte-compat goldens) and *structural invariants*
(open/close balance, chain coverage), not internal hooks.

## 9. Risks and prerequisites

### Prerequisites (must be true before Phase 3)

- **P1 — Phase 3d effect chain in place.** Every side-effect node
  has `inputs[0]` pointing at its chain predecessor. ✓ Shipped
  2026-05-22.
- **P2 — Bidirectional `Graph::nodes()`.** Chain-walk relies on
  `nodes()` being able to surface every node in the graph
  including via consumer edges. ✓ Shipped (Phase 7d, 2026-05-21).
- **P3 — Per-method graph isolation.** The scheduler operates on a
  single method's graph at a time and never reaches outside it.
  ✓ Holds since the Bootstrap singleton was deleted (Phase 7d).
- **P4 — `If->region`, `Loop->region` set.** ✓ Shipped (Phase 3d).

All prerequisites are satisfied today on `fixup-audit-baseline`.

### Risks

#### R1 — Hidden side-effect nodes not in the chain

If the audit work missed any statement-position node type, the
chain walk skips it; the scheduler emits an incomplete schedule;
codegen emits incomplete source. The 2026-05-22 IR completeness
audit found and closed these gaps for the existing corpus; the
risk is that new node types (added later) get the
chain-membership story wrong.

**Mitigation:** The "chain coverage" property test (Section 8)
fires on every method in the test corpus and asserts every
node in the graph is reachable from the schedule (modulo
data-only nodes). New node types regressing this property fail
loudly.

#### R2 — For-style recognition misclassifies

If a `Loop` is built by `ForStatement` but the init VarDecl
isn't adjacent (e.g., a parser bug introduces an intervening
statement), the scheduler can't fold the init into the for's
meta. Today's emit_cfg_loop has the same brittleness — this is
not a new risk.

**Mitigation:** When `for_style` is set but recognition fails,
emit the desugared `{ VarDecl; while }` form. Add a one-line
warning to the schedule's meta so a debugger can see it. The
output is correct, just uglier than the source.

#### R3 — Phi-slot resolution finds the wrong VarDecl

If two distinct `my $x` declarations exist in nested scopes and
a Phi merges values across both, the wrong VarDecl may be
chosen as the slot. The scheduler must use the inner-scope
VarDecl; today's Phase 3 SSA construction enforces lexical
scoping but Phi-slot lookup needs to honor it.

**Mitigation:** Slot resolution walks `inputs` of the Phi's
constituent values *backward through their VarDecl assignments*,
recovering the source-level identifier of the dominating
VarDecl. The byte-compat goldens will catch any mis-slotting
(generated code references the wrong identifier and fails to
compile or has wrong runtime behavior).

#### R4 — Codegen requires more context than the schedule carries

If `_emit_node` today reads something from Context that the
schedule omits (e.g., parent-form for tail-position recognition,
type information for typed emit), the schedule path emits less
optimal code. Found by golden mismatch.

**Mitigation:** The schedule's `meta` field is extensible. Any
context-derived data codegen needs gets attached to the
relevant schedule item when the scheduler builds it. If a
mismatch surfaces during Phase 5, extend `meta` rather than
fall back to Context reads.

#### R5 — Big-bang risk

Phases 5 and 6 together are a sizable behavior swap. If
something subtle breaks in the wild (a fixture not in the
golden corpus regresses), the rollback is non-trivial.

**Mitigation:**
1. Keep both paths live throughout Phase 5 (parallel test
   files exercising both `_generate_from_mop` and
   `_generate_from_schedule`).
2. Expand the golden corpus *before* Phase 5 starts. Any file
   in `lib/` that the parser accepts and the legacy codegen
   emits gets a `.pl.golden` captured. Phase 6 deletion is
   safe only if the new path matches goldens for every file
   in the audit corpus.
3. Phase 6 deletion is staged: first delete the synthesis
   layer (`_generate_from_mop`, `MethodInfo` etc.) while
   leaving `body` populated; second delete `body`; third
   delete the `cfg_state` reader. Each deletion runs the
   full test suite.

### Rollback path

If the schedule path produces wrong output for a non-golden
fixture discovered late, the rollback during Phase 5 is:
toggle the test/build flag back to `_generate_from_mop`.
After Phase 6 deletion, the rollback is the prior commit on
the branch. Phase 6 should be a *single* commit so revert is
clean.

## Cross-references

- Prep doc: `docs/plans/2026-05-23-son-scheduler-prep.md`
- Original CFG design (algorithm sketch lines 165-188):
  `docs/plans/2026-02-23-sea-of-nodes-cfg-design.md`
- Stale eager-pinning task plan (superseded):
  `docs/plans/2026-02-23-eager-pinning-cfg-statements.md`
- Phase 3d effect-chain closure:
  `docs/plans/2026-05-22-phase-3d-effect-chain-completion.md`
- IR completeness audit:
  `docs/plans/2026-05-22-ir-completeness-audit.md`
- IR/MOP alignment audit:
  `docs/plans/2026-05-22-ir-mop-alignment-audit.md`
- Self-host parse probe (post-cleanup readiness):
  `docs/plans/2026-05-23-self-host-parse-probe.md`
- Phase 3a-infra (deleted `cfg_state` side channel):
  `docs/plans/2026-05-20-mop-migration-3a-infra-status.md`
- MOP migration master plan (Phase 4 spec):
  `docs/plans/2026-04-21-chalk-mop-migration-plan.md`

## Reading-list residuals (not consumed in this session)

The prep doc named four external sources. We did not read three of
them in this session because the in-tree design (Feb 23 cfg-design
lines 165-188) already specified the algorithm at the abstraction
level we needed, and the eager-pinning vs GCM decision (A) was
the one place a literature check would have mattered. The Feb 23
conversation already settled that. The unread sources remain
relevant for the implementation session:

- **Click 1995 paper** — vocabulary for the implementation PR
  descriptions and any future GCM discussion.
- **Simple SoN repo, Chapters 5 and 7** — concrete code patterns
  for if/else and loop scheduling; worth a skim before writing
  Phase 4.
- **Turboshaft / V8 paper** — confirms the eager-pinning approach
  in a production compiler; useful as a citation, not a
  prerequisite.
- **Demange & Retana** — theoretical foundation for structured
  control flow in SoN; consult if a specific question arises about
  the semantics of `Region` or `Phi`.
