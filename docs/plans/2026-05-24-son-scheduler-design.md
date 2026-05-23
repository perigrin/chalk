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

## Decisions

A summary up front so a reader can stop here if they only need the
decisions. Rows A-D are the four open questions from the prep doc.
Rows E-F were added in the 2026-05-24 amendment, after a follow-up
conversation surfaced that the scheduler interface itself is a
load-bearing design decision (E) and that the byte-compat-vs-
semantic-equivalence distinction needed to be explicit rather than
implicit (F). Row G was added in a second 2026-05-24 amendment after
a follow-up conversation about where scheduler interpretations of IR
nodes should live; that conversation also refined E to clarify that
the contract includes ScheduleMeta population, not just Schedule
production. Rationale for each appears in the relevant section
below.

| # | Question | Decision |
|---|---|---|
| A | Eager pinning vs nesting-tree GCM | **Eager pinning, transitionally.** Phase 3d already pinned every side-effect node to its control predecessor via `inputs[0]`; the scheduler walks that pinning rather than recomputing placement. This is the *initial* scheduler, not the destination. Cliff Click's critique of eager pinning — that it forfeits the optimization payoff SoN exists to deliver — is valid, and we accept it for the transition phase. The destination algorithm is TBD pending the literature survey at `docs/research/2026-05-24-scheduler-literature-survey.md`; GCM is the current frontrunner. Phase 8 (added below) is the swap. |
| B | Source-form for `for` / `while` / `until` | **Preserve `foreach` vs `while`; normalize `until` to `while !cond`.** `foreach` carries iterator/list annotations on the Loop; `while` does not. `until`'s negation is already baked into the IR (PostfixModifier wraps the condition in `!`), so the distinction is unrecoverable and we accept the loss. C-style `for(init; cond; step)` emits as `for` when the pre-init VarDecl is recognizable; otherwise as `{ init; while(cond) { ...; step } }`. |
| C | `MOP::Method->body` lifecycle | **Delete entirely**, but only after the scheduler ships and the codegen MOP path is migrated. `body` exists today because codegen needs a statement list; once codegen consumes a schedule, `body` has no callers. Do not keep it as a debug aid — debug tooling belongs in a separate dumper. |
| D | Order of operations | **Scheduler first, then incremental codegen migration.** Build `Chalk::IR::Scheduler` as a new module that consumes a `MOP::Method`/`MOP::Sub` and produces a typed schedule. Add a second `_generate_from_schedule` path next to `_generate_from_mop` in `Target::Perl`. Once both produce byte-identical output across the golden corpus, switch over and delete `_generate_from_mop` + `body`. |
| E | Scheduler interface contract | **`Chalk::IR::Scheduler->schedule($method) → Schedule` is the contract, AND the scheduler populates `$node->schedule_data` on every node codegen will later interpret.** Any producer of a valid `Chalk::IR::Schedule` that also populates appropriate `Chalk::Scheduler::ScheduleMeta` subclasses on the nodes it emits is a drop-in replacement. The Schedule itself is minimal `{ kind, node }` items plus structural markers; the ScheduleMeta class tree IS the dialect (see G). The eager-pinning implementation and the eventual destination algorithm (GCM or whatever the survey names) are both behind this interface. This is what makes Phase 8 mechanical. |
| F | Test gate: byte-compat vs semantic equivalence | **Byte-compat is the migration gate (Phases 1-6); semantic equivalence is the durable contract.** During cutover from `_generate_from_mop` to `_generate_from_schedule`, byte-identical output against the golden corpus is the regression gate — it lets us swap implementations without arguing about whether output changes were intentional. Post-cutover (and especially across the Phase 8 algorithm swap) the contract becomes semantic equivalence: the same IR shape on round-trip, or the same runtime behavior on a corpus with known outputs. Byte-compat is a migration safety mechanism, not a design goal. |
| G | ScheduleMeta as the single annotation location | **All scheduler interpretations of IR nodes live in `$node->schedule_data`, an instance of a `Chalk::Scheduler::ScheduleMeta` subclass.** Schedule items carry `{ kind, node }` plus structural markers (`block_open`/`block_close`/`else`/`elsif`/`catch`) only — no `meta` dict, no `role`/`phi` fields on items. Each scheduler implementation owns its own class tree (`Chalk::Scheduler::Roundtrip::*` for the eager-pinning scheduler; `Chalk::Scheduler::GCM::*` for the Phase 8 destination, when it lands). Codegen gates ScheduleMeta access at the boundary using isa, role, can, or version checks; the gate style is implementation detail, the gating discipline is the contract. Failures are loud (codegen-for-Roundtrip given a node with no schedule_data, or with a GCM ScheduleMeta, dies at the gate) — no silent fallback, no "ignore unknown keys." This is more boilerplate than per-field IR additions, and we accept that cost for the architectural discipline of one typed location for scheduler decisions. |

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
      | { kind => 'block_open', form => $form, node => $control_node }
      | { kind => 'block_close', form => $form }
      | { kind => 'else' }
      | { kind => 'elsif', node => $control_node }
      | { kind => 'catch', node => $control_node }
```

`$form` ∈ `qw(if while for foreach try)`. Items are minimal —
`{ kind, node }` plus structural markers. **Schedule items carry no
`meta` dict and no scheduler-decision fields.** All scheduler
interpretations of the node (form-specific data like the foreach
iterator and list, the `for`-style init and step, the `If`'s
`loop_jump` shortcut, the `TryCatch`'s catch variable) live on
`$node->schedule_data`, a `Chalk::Scheduler::ScheduleMeta` instance
populated by the scheduler. See Section 10 for the ScheduleMeta
class tree and Decision G for the rationale.

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
  the kind of placement freedom that GCM (or similar) gives. We do
  not need that during the transition — byte-compat against the
  golden corpus is the migration gate, and byte-compat forbids
  motion. Once the destination scheduler lands in Phase 8, motion
  becomes available and the eager-pinning constraint dissolves.
- **No loop normalization, no `until` recovery.** `until` is already
  baked as `while !cond` in IR; the scheduler emits whatever shape
  the IR carries.

These are not the scheduler's job. They are downstream optimization
passes that may or may not exist, that operate on the graph before
or after scheduling.

### Durable goal vs migration gate

A point worth stating plainly because the rest of the document
talks about goldens a lot: the **durable contract** for codegen is
*semantic equivalence* — parsing source S and emitting it produces
either an IR isomorphic to the original parse of S, or an output
program with the same observable behavior as S on a corpus of
inputs. The byte-compat goldens enforce a stricter property
(byte-identical output) during the cutover from `_generate_from_mop`
to `_generate_from_schedule`; that strictness is a *migration safety
mechanism*, not the long-term contract. Once Phase 8 swaps the
scheduler implementation behind the `Schedule` interface, generated
output is expected to change in trivial ways (variable ordering,
choice between equivalent surface forms, fewer redundant
temporaries), and the test gate moves from "bytes match" to
"semantics match." See Section 7 Phase 8 and Decision F.

## 2. Algorithm

### Why eager pinning for the *initial* scheduler (Decision A)

The Click GCM algorithm needs a dominator tree because it does
late-binding placement: nodes float through the graph until they
hit their pinned dependencies, then they're placed at the latest
control point that still dominates all their uses. That's the
algorithm we expect to want eventually. The reasons it isn't the
algorithm we ship first are tactical, not principled.

Phase 3d's Block control-chain fixup pass already writes a
control predecessor into every side-effect node's `inputs[0]`:

- For `VarDecl`, `Return`, `Unwind`, `Call`, `Assign`, `CompoundAssign`,
  `RegexSubst` — `inputs[0]` is the previous side-effect node in the
  same block, or `Start` for the first.
- For `If`, `Loop`, `TryCatch` — `inputs[0]` is the previous side-effect
  node, set by the same fixup pass via `set_control_in`. The post-
  control of an `If` is `$if->region`; of a `Loop` is `$loop->region`.

This is the wiring the Feb 23 conversation labeled *Eager Pinning*
(the Turboshaft / V8 approach). Because Phase 3d already paid for
it, an eager-pinning scheduler costs us no additional infrastructure
work to ship.

The scheduler's job, in the eager-pinning version, is therefore
**not** to decide where nodes go. It is to **walk the existing
pinning and emit a linear order**.

This is transitional. Cliff Click's critique of eager pinning is
the one most worth quoting: an SSA/SoN form whose nodes are pinned
at construction forfeits the optimization payoff that motivated
SoN in the first place. Hoisting, sinking, and motion-based
redundancy elimination need placement freedom that eager pinning
denies. We are accepting that critique for the transition window
because the alternative — building GCM (or whichever destination
the literature survey names) and the parser-to-codegen byte-compat
proof at the same time — fails the "one variable at a time"
discipline that the Chalk MOP migration already taught us. See
Phase 8 (Section 7) for the swap. The destination algorithm is
**TBD pending the literature survey** at
`docs/research/2026-05-24-scheduler-literature-survey.md`; GCM is
the current frontrunner but the survey may name better candidates.

### The Schedule data type is the swap point

The scheduler's external contract is:

```
Chalk::IR::Scheduler->schedule($method) → Chalk::IR::Schedule
```

plus the side effect of populating `$node->schedule_data` on every
node codegen will later interpret. Anything that produces a valid
`Chalk::IR::Schedule` *and* populates appropriate ScheduleMeta
subclasses on those nodes is a drop-in replacement. The Schedule's
shape (Section 1 "Output contract") and the ScheduleMeta class tree
(Section 10) are the interface; the algorithm behind it is private.
Codegen consumes `Schedule` and reads `schedule_data`; codegen
knows nothing about how either was produced. This is what makes
Phase 8's algorithm swap mechanical — replace
`lib/Chalk/IR/Scheduler.pm` with a new implementation that produces
its own ScheduleMeta subclasses, gate codegen at the boundary, run
the test corpus, done. No changes to the rest of the IR.

A corollary, called out separately as R6 below: code outside the
scheduler must not read `inputs[0]` as if it were dominance
information. It is emit-order information for the eager-pinning
era. New code that wants dominance must compute it from the graph.

### ScheduleMeta population

The scheduler's structured-expansion pass visits each control-
affecting node (`Loop`, `If`, `TryCatch`, `Phi`) and populates that
node's `schedule_data` field with the appropriate ScheduleMeta
subclass before emitting the `block_open` item that references it.
For the eager-pinning (roundtrip) scheduler, the populated subclasses
are `Chalk::Scheduler::Roundtrip::Loop`, `Roundtrip::If`,
`Roundtrip::TryCatch`, and `Roundtrip::Phi`. For the Phase 8
destination scheduler, the populated subclasses are
`Chalk::Scheduler::GCM::*` (or whatever the destination algorithm's
namespace is).

The Schedule items themselves carry `{ kind, node }` and structural
markers only. To recover scheduler interpretations during codegen,
the codegen reads `$item->{node}->schedule_data` and gates the
returned object's type. Section 10 specifies the gate contract;
each Section 3 pattern below shows the concrete population.

`schedule_data` starts life as `undef` on every newly-constructed
IR node; the scheduler sets it during scheduling, and the node
moves from incomplete to complete. This is lazy initialization,
not mutation: `schedule_data` participates in no `content_hash`
computation, the same pattern already used for `compat_class`,
`control_in`, `If->region`, and `Loop->region`.

### Two-phase scheduling

Phase 1 — **chain walk**. Starting from the unique `Return` (or
`Unwind`) node in the method's graph, walk backward via
`inputs[0]` collecting side-effect nodes into a list. Reverse the
list to get source order. This produces the **top-level statement
sequence** for the method body.

Phase 2 — **structured expansion**. For each statement in the
top-level sequence, dispatch on type. Each control-node case
populates the node's `schedule_data` with the appropriate
ScheduleMeta subclass *before* emitting its `block_open`:

- Plain side-effect node (`Call`, `Assign`, `VarDecl`, `Return`,
  ...) → emit one `{ kind => 'stmt', node => $n }` item. (Plain
  side-effect nodes typically have no ScheduleMeta; the exception
  is VarDecls that are Phi emit-slots, where the Phi — not the
  VarDecl — carries the ScheduleMeta.)
- `If` node → populate `$if->schedule_data` with
  `Roundtrip::If`, then emit
  `{ kind => 'block_open', form => 'if', node => $if }`, recurse
  into the true branch (chain walk + structured expansion
  starting from the node whose `control_in` is the `TrueProj`,
  stopping at the `Region` join), emit any `{ kind => 'else' }`
  or `{ kind => 'elsif', node => $inner_if }` items, recurse into
  the false branch, emit `{ kind => 'block_close', form => 'if' }`.
- `Loop` node → populate `$loop->schedule_data` with
  `Roundtrip::Loop` (filled with iterator/list/for-style fields
  per the parse-time hints lifted in Phase 1), then emit
  `{ kind => 'block_open', form => 'while'|'foreach'|'for', node => $loop }`,
  recurse into the body (chain walk starting from the node whose
  `control_in` is the loop's `body_proj`, stopping at the
  `Loop`'s backedge), emit
  `{ kind => 'block_close', form => $form }`.
- `TryCatch` node → populate `$try->schedule_data` with
  `Roundtrip::TryCatch`, then emit
  `{ kind => 'block_open', form => 'try', node => $try }`,
  recurse into the try body, emit
  `{ kind => 'catch', node => $try }`, recurse into the catch
  body, emit `{ kind => 'block_close', form => 'try' }`.
- `Phi` nodes are not in the chain (they are merge values, not
  statements) — they are visited during structured expansion when
  the Phi-slot resolution pass walks the consumers of merge
  values. That pass populates `$phi->schedule_data` with
  `Roundtrip::Phi`. See Section 4.

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

The scheduler emits `{ kind => 'block_open', form => $form, node => $control_node }`
and populates `$control_node->schedule_data` with the appropriate
ScheduleMeta subclass before emitting; codegen reads `$form` to
choose the surface syntax and `$control_node->schedule_data` for
the form-specific details. The patterns below specify what each
`(if|while|for|foreach|try)` block in the schedule corresponds to
in IR-graph shape, so the implementation can verify it.

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
# Before scheduling: $if->schedule_data == undef
# During scheduling, scheduler populates:
$if->set_schedule_data(
    Chalk::Scheduler::Roundtrip::If->new(
        # is_loop_jump defaults false; PostfixModifier action sets true
        # when the If is the loop-jump shortcut form
    )
);

# Schedule items emitted:
{ kind => 'block_open', form => 'if', node => $if }
  ... true-branch items ...
{ kind => 'else' }                                                   # only if false-branch nonempty
  ... false-branch items ...
{ kind => 'block_close', form => 'if' }
```

Codegen reads `$if->schedule_data->is_loop_jump` (see loop-jump
shortcut below) to decide whether to collapse the block.

#### `elsif` recognition

If the false branch chain is exactly *one* `If` node and that
`If`'s `Region` matches the outer `If`'s `Region` (the two
joins are the same merge point), emit
`{ kind => 'elsif', node => $inner_if }` in place of
`{ kind => 'else' }` followed by `{ kind => 'block_open' }`. The
inner `If` still gets its own `schedule_data` populated.

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
sequence; codegen reads `$if->schedule_data->is_loop_jump` and
collapses the block to a one-liner when set. **The `loop_jump`
flag lives on `Chalk::Scheduler::Roundtrip::If`**, not on the
parsing Context, and is populated by the scheduler (using
information the `PostfixModifier` action stored on the IR during
Phase 1) so neither scheduler nor codegen depends on Context after
the cutover.

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
# During scheduling, scheduler populates:
$loop->set_schedule_data(
    Chalk::Scheduler::Roundtrip::Loop->new(
        # is_for_style false, iterator/list/for_init/for_step absent
    )
);

# Schedule items emitted:
{ kind => 'block_open', form => 'while', node => $loop }
  ... body items, found by chain walk from $body_proj's first consumer
      with stop predicate "== $loop" ...
{ kind => 'block_close', form => 'while' }
```

The body chain walk stops at the `Loop` node itself because the
last body statement's `control_in` is wired back to `Loop` via
`set_backedge_ctrl`. Codegen reads `$loop->schedule_data` to confirm
it is a `Roundtrip::Loop` with no iterator/list (a plain while).

### Pattern: Loop + iterator/list metadata → `foreach`

Same IR shape as `while`. The difference is on the Loop's
`schedule_data`: a `Roundtrip::Loop` with `iterator` (a Constant
node holding the variable name like `$n`) and `list` (the list
expression IR node or arrayref of element nodes) populated.

Today these annotations live on the parsing Context
(`update_annotations`); the codegen reads them via
`_build_cfg_lookup` and `cfg_state`. For the scheduler we need
them on the Loop's ScheduleMeta. Phase 1 of implementation moves
them — destination is `Chalk::Scheduler::Roundtrip::Loop`'s
`iterator` and `list` fields, populated by `ForeachStatement`
action storing the values on the Loop node where the scheduler
can later wrap them into the ScheduleMeta.

Schedule emit (foreach):

```
# Before scheduling: $loop->schedule_data == undef

# During scheduling, scheduler populates:
$loop->set_schedule_data(
    Chalk::Scheduler::Roundtrip::Loop->new(
        iterator => $iter,
        list     => $list,
    )
);

# Schedule items emitted:
{ kind => 'block_open', form => 'foreach', node => $loop }
  ... body items ...
{ kind => 'block_close', form => 'foreach' }
```

Codegen reads `$loop->schedule_data->iterator` and `->list` to
generate the surface `foreach my $n (@list) { ... }`.

### Pattern: VarDecl(s) + Loop → C-style `for`

Source: `for (my $i = 0; $i < 10; $i++) { ... }`.

IR shape (today, after Phase 3e): the for-init VarDecl lands in
the *enclosing* block's chain, immediately before the `Loop`. The
`Loop`'s condition tests `$i`. The "step" expression appears as
the last statement in the body (the parser wires it there).

Recognizing this as a `for` instead of `{ VarDecl; while }`
requires a node-level flag on the Loop: `is_for_style => true`,
set by `ForStatement` action on the IR node so the scheduler can
read it and lift it (along with the init/step nodes) onto the
Loop's `Roundtrip::Loop` ScheduleMeta.

Schedule emit:

```
# During scheduling, scheduler populates:
$loop->set_schedule_data(
    Chalk::Scheduler::Roundtrip::Loop->new(
        is_for_style => true,
        for_init     => $init_vardecl,
        for_step     => $step_node,
    )
);

# Schedule items emitted:
{ kind => 'block_open', form => 'for', node => $loop }
  ... body items, excluding $step ...
{ kind => 'block_close', form => 'for' }
```

The init VarDecl is still in the enclosing chain at chain-walk
time; the scheduler **must** remove it from the enclosing chain
and lift it onto the Loop's ScheduleMeta when it recognizes the
for-style pattern. The step node is the last body-chain item;
same treatment.

**This is the one place where the scheduler does graph rewriting
during walk**, and it's the price we pay for source-form
preservation. The rewriting is local (one chain entry moved onto
the Loop's ScheduleMeta) and reversible (codegen could emit the
desugared form by ignoring `is_for_style`).

If the for-init/step recognition fails (e.g. the init isn't a
single VarDecl), the scheduler populates `Roundtrip::Loop` with
`is_for_style => false` and emits the desugared `{ VarDecl; while; }`
form. Correct, not pretty.

### Pattern: TryCatch + chain → `try` / `catch`

IR shape (current): `TryCatch` node with `inputs[0] = control_in`,
plus side-channel annotations `try_stmts`, `catch_var`,
`catch_stmts` on the Context.

Same migration as foreach iterator/list: move the annotations off
Context onto the `TryCatch` node so the scheduler can read them
and lift `catch_var` onto the `TryCatch`'s ScheduleMeta. The
`try_stmts` and `catch_stmts` become chain segments rooted in
nodes whose `control_in` is the TryCatch's two output projections
(or whatever the IR shape is post-migration; today these aren't
proper Projs, and that's a bug-class hazard we should fix as part
of Phase 1).

Schedule emit:

```
# During scheduling, scheduler populates:
$try->set_schedule_data(
    Chalk::Scheduler::Roundtrip::TryCatch->new(
        catch_var => $catch_var,
    )
);

# Schedule items emitted:
{ kind => 'block_open', form => 'try', node => $try }
  ... try-body items ...
{ kind => 'catch', node => $try }
  ... catch-body items ...
{ kind => 'block_close', form => 'try' }
```

Codegen reads `$try->schedule_data->catch_var` when emitting the
`catch ($var) { ... }` header.

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
synthetic identifiers. That's both bad for the byte-compat
migration gate (the goldens were captured from source that doesn't
have `$_phi_*`) and bad on the merits — synthetic identifiers in
emitted output make the result harder to read and harder to round-
trip through the parser. The Phi-slot strategy below addresses
both concerns simultaneously.

### Target strategy: Phi → declared-variable slot

Most Phi nodes in real code come from `my $x = ...; if (...) { $x = ...; }`.
The pre-existing VarDecl already declares `$x`. The Phi's emit
slot should reuse `$x`, not synthesize `$_phi_42`.

The scheduler resolves Phi → emit-slot mapping by walking the
Phi's `inputs` for the most-recent VarDecl that names the same
variable. That VarDecl is the slot. The scheduler populates the
Phi's `schedule_data` with that slot:

```
$phi->set_schedule_data(
    Chalk::Scheduler::Roundtrip::Phi->new(
        emit_slot => $vardecl,
    )
);
```

Codegen, when emitting any statement whose IR consumes the Phi
(typically a `Return`, but also any later `Assign`/`Call` that
reads the merged value), reads `$phi->schedule_data->emit_slot` to
recover the surface identifier and emits the slot's variable name
rather than a synthetic `$_phi_<id>`. Inside the if-branches, the
assignments stay as plain `Assign` nodes; the Phi itself isn't
emitted as a separate statement. The VarDecl's chain item remains
a plain `{ kind => 'stmt', node => $vardecl }`; it carries no
phi-specific role on the Schedule item — the Phi's ScheduleMeta is
where that wiring lives.

### Loop-Phi → loop-carried variable

For a `Phi(loop, entry, backedge)` where `entry` is a value from
before the loop and `backedge` is the body's assigned value, the
emit slot is again the pre-loop VarDecl. The body's assignment to
that variable is what produces the backedge value. No separate
emission of the Phi is needed.

### When no VarDecl exists for the Phi

Possible only for synthetic Phis introduced by future optimization
passes. The scheduler populates `Roundtrip::Phi` with
`emit_slot => undef` and a `synthetic_name` field carrying
`$_phi_<id>`; codegen falls back to the synthetic name when
`emit_slot` is undef. We never hit this in the parser-produced IR
(Phi-slot recovery is the common case); the fallback exists so the
Phase 8 destination scheduler — which may introduce synthetic Phis
via hoisting or similar — has a well-defined behavior. (Phase 8's
own ScheduleMeta subclass for Phi may extend this with hoisting
provenance.)

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

Schedule and ScheduleMeta population:

```
# Scheduler populates:
$if->set_schedule_data(Chalk::Scheduler::Roundtrip::If->new());
$phi->set_schedule_data(
    Chalk::Scheduler::Roundtrip::Phi->new(emit_slot => $vardecl_x),
);

# Schedule items:
{ kind => 'stmt', node => VarDecl($x=0) }                  # codegen: my $x = 0;
{ kind => 'block_open', form => 'if', node => $if }
  { kind => 'stmt', node => Assign($x, 1) }                # codegen: $x = 1;
{ kind => 'else' }
  { kind => 'stmt', node => Assign($x, 2) }                # codegen: $x = 2;
{ kind => 'block_close', form => 'if' }
{ kind => 'stmt', node => Return(Phi) }                    # codegen: return $x;
                                                            # — Phi resolves to $x via
                                                            # $phi->schedule_data->emit_slot
```

The Phi is **not** emitted as a statement; it's a *value* that the
return reads. The Phi's ScheduleMeta ensures `$x` is the surface
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

Phases 1-7 produce commits independently testable against the
existing byte-compat golden corpus
(`t/bootstrap/mop/codegen-byte-compat.t`); none of those phases
regresses the goldens. Phase 8 is the destination-scheduler swap,
which legitimately changes output; its gate is semantic
equivalence, not byte-compat (Decision F). The "rough effort"
estimates are for one focused session at the bench; treat as
ranges.

### Phase 1 — Annotation cleanup (preparation, no scheduler yet)

**Goal:** Move per-control-node annotations from Context onto
**ScheduleMeta objects on IR nodes**, so the scheduler reads from
IR alone and codegen reads from a typed location.

**Concrete moves:**

First, define the ScheduleMeta class tree (see Section 10 for the
full sketch):

- `lib/Chalk/Scheduler/ScheduleMeta.pm` — abstract base.
- `lib/Chalk/Scheduler/Roundtrip/Loop.pm` — fields:
  `$is_for_style`, `$iterator`, `$list`, `$for_init`, `$for_step`.
- `lib/Chalk/Scheduler/Roundtrip/If.pm` — field: `$is_loop_jump`.
- `lib/Chalk/Scheduler/Roundtrip/Phi.pm` — fields: `$emit_slot`,
  `$synthetic_name`.
- `lib/Chalk/Scheduler/Roundtrip/TryCatch.pm` — field: `$catch_var`.

Then add `schedule_data` to `Chalk::IR::Node` (or whichever level
of the IR class hierarchy is appropriate — the field is excluded
from `content_hash` regardless of where it lives) as
`field $schedule_data :reader = undef;` with a
`set_schedule_data($meta)` mutator.

Then move the parse-time annotations off Context onto the IR
nodes whose ScheduleMeta will later carry them:

1. `iterator`, `list` from Context annotations onto `Loop` node
   fields. Set in `ForeachStatement` action. The scheduler reads
   these in Phase 4 and wraps them into `Roundtrip::Loop` on the
   Loop's `schedule_data`.
2. `loop_jump` flag from Context annotations onto `If` node as
   `field $loop_jump_hint :reader = false;`. Set in
   `PostfixModifier` action when the loop-jump form is detected.
   Scheduler later lifts it onto `Roundtrip::If`'s `is_loop_jump`.
3. `for_style` flag on `Loop` node as
   `field $for_style_hint :reader = false;`. Set in `ForStatement`
   action. Scheduler later lifts it onto `Roundtrip::Loop`'s
   `is_for_style`.
4. `try_stmts` / `catch_stmts` / `catch_var` from Context
   annotations onto `TryCatch` node. (Today `TryCatch` is almost
   empty — just an `operation` method. It needs real fields and a
   proper structure: control inputs for try-region and
   catch-region, a `var` for the caught exception name. This is a
   small but real IR change.) Scheduler later lifts `catch_var`
   onto `Roundtrip::TryCatch`.

The two-level hop (parse-time hint field on the IR node, then
scheduler lifts it into ScheduleMeta) is the price of keeping
parse-time annotation work parser-local while ensuring the
ScheduleMeta is the *single* location codegen reads. An
alternative is to have the parser construct ScheduleMeta directly
on the node, but that bakes scheduler-dialect knowledge into the
parser — better to let the scheduler own the ScheduleMeta class
tree completely.

**Test gate:** byte-compat goldens pass. The codegen's existing
`cfg_state` reader is *still* in use during Phase 1 — we move the
data into the IR alongside the side-channel population, not in
place of it. This is the safe order: add a new source-of-truth,
keep the old one wired, then in Phase 2 the scheduler reads the
new source.

**Effort:** 1-1.5 sessions (the extra half-session is the
ScheduleMeta class definitions and the IR field plumbing).

**Risk:** Low. The IR fields are additive; the Context
annotations stay too; the ScheduleMeta classes are new code with
no production consumers yet. Failures look like missing-field
accessors or set-to-undef being treated as set.

### Phase 2 — Schedule data type + Phase 1 verification

**Goal:** Define `Chalk::IR::Schedule` and `Chalk::IR::Schedule::Item`
as data types. No producer yet; just the shape and trivial
constructors. Write a few hand-built `Schedule` fixtures and
unit-test their structure (e.g., open/close balance).

**Concrete files:**
- `lib/Chalk/IR/Schedule.pm` — class with `field @items :reader`
  and `method push_item($item)`.
- `lib/Chalk/IR/Schedule/Item.pm` — class with `field $kind :param :reader;
  field $form :param :reader = undef; field $node :param :reader = undef;`.
  **No `meta` field.** All scheduler interpretations live on
  `$item->node->schedule_data`. Item is intentionally minimal.

**Test gate:** new `t/bootstrap/scheduler/schedule-shape.t` —
hand-built schedules round-trip through items, and an item with
a `node` carrying ScheduleMeta exposes the meta through the
`node->schedule_data` indirection (not through any Item field).

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
same comparison via the schedule path. Byte-compat here is the
*migration safety mechanism* — it lets us swap one implementation
for another without arguing about whether output differences are
intentional. It is not the destination contract (see Decision F
and Phase 8).

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

### Phase 8 — Transition to destination scheduler

**Goal:** Replace the eager-pinning implementation of
`Chalk::IR::Scheduler` with the destination algorithm chosen by the
literature survey. This is the phase where Chalk starts being a
real optimizing compiler — the eager-pinning era is a transitional
plateau, not a stopping point.

**Prerequisite:** `docs/research/2026-05-24-scheduler-literature-survey.md`
has landed and named a destination algorithm (GCM is the current
frontrunner; the survey may surface better candidates). Without
the survey's conclusion this phase has no concrete algorithm to
implement.

**Concrete moves:**
1. Replace the body of `Chalk::IR::Scheduler->schedule($method)`
   with the destination algorithm. The class's public interface
   does not change.
2. If the destination needs auxiliary data structures (dominator
   tree, loop nesting tree, etc.), build them inside the
   scheduler — they are private to the implementation.
3. Update or delete the `inputs[0]` "control predecessor" wiring
   from Phase 3d. Eager pinning made `inputs[0]` load-bearing as
   emit-order; the destination algorithm decides emit-order from
   the graph and does not need it. The Phase 3d data may still
   be useful as *hints* (initial placement candidates) but must
   not be a correctness dependency.

**Test gate:** *semantic equivalence*, not byte-compat. The
generated output is expected to differ from the eager-pinning
version (different variable ordering, fewer redundant temporaries,
hoisted invariants — whatever the destination algorithm produces
that the eager version did not). The test corpus checks one of:

- **Round-trip IR equivalence.** Parse source S to IR_1. Emit IR_1
  to source S'. Parse S' to IR_2. IR_1 and IR_2 are isomorphic
  modulo node IDs and ordering of commutative inputs.
- **Behavioral equivalence.** Run source S and emitted S' against
  a corpus of inputs; observable outputs match.

The byte-compat golden tests from Phases 5-6 are *retired* in this
phase: the goldens are recaptured against the destination
scheduler's output and become the new baseline for regression, but
they no longer prove anything about the cutover — that proof is
the responsibility of the semantic-equivalence tests added here.

**Effort:** unknown until the survey lands. Order-of-magnitude
guess: 3-5 sessions for the algorithm implementation plus 2-3 for
the test infrastructure (round-trip equivalence checker is the new
piece of code). The phase is *provisional* on the survey.

**Risk:** This is where the real correctness work happens. R6 and
R7 (Section 9) cover the specific failure modes — load-bearing
`inputs[0]` reads outside the scheduler, and the survey naming
a different destination than GCM.

## 8. Test strategy

The test strategy has two regimes. Phases 1-6 use byte-compat
goldens as the migration safety mechanism — we are swapping one
implementation for another, and byte-identical output is the
sharpest way to detect that the swap is behavior-preserving.
Phase 8 (the destination-scheduler swap) abandons byte-compat in
favor of semantic equivalence, because the whole point of Phase
8 is that the output *will* legitimately change. The two regimes
correspond to Decision F: byte-compat is the migration gate;
semantic equivalence is the durable contract.

### Primary regression gate during migration: byte-compat golden corpus

`t/bootstrap/mop/codegen-byte-compat.t` already exists and runs
`generate($mop)` against ~N captured `*.pl.golden` files in
`t/fixtures/codegen-goldens/`. Through Phase 6, the schedule-driven
path **must not change golden output**. Any byte-level difference
is either a scheduler bug or an intentional change (in which case
the golden gets updated explicitly). This is migration safety,
not a long-term contract on emit shape — see Phase 8 for what
replaces it.

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
in the schedule (modulo for-init/for-step which get lifted onto
the Loop's ScheduleMeta). No side-effect node is missing; no node
is emitted twice. This catches the bugs that the Phase 3d audit
found.

### Property: ScheduleMeta population completeness

A third property test: every IR node the scheduler emits in the
Schedule that codegen will need to interpret carries the right
ScheduleMeta. Concretely:

- Every Loop referenced by `block_open form=>'while'|'foreach'|'for'`
  has `schedule_data` set to a `Chalk::Scheduler::Roundtrip::Loop`.
- Every If referenced by `block_open form=>'if'`, by an `elsif`,
  or as the recursive-else target has `schedule_data` set to a
  `Chalk::Scheduler::Roundtrip::If`.
- Every TryCatch referenced by `block_open form=>'try'` has
  `schedule_data` set to a `Chalk::Scheduler::Roundtrip::TryCatch`.
- Every Phi node whose value is read anywhere in the Schedule has
  `schedule_data` set to a `Chalk::Scheduler::Roundtrip::Phi`.

No node missing its ScheduleMeta; no ScheduleMeta on the wrong
node class (e.g., a `Roundtrip::Loop` accidentally attached to an
`If`). This catches scheduler bugs where a code path skips
population, and catches incomplete migrations during Phase 1 where
the scheduler reads an old Context annotation instead of building
the ScheduleMeta.

### Performance check

The scheduler is O(n). A regression test that schedules the largest
method in the golden corpus and asserts a wall-clock budget (say,
< 5ms) prevents accidental quadratic behavior creeping in. Not a
sharp bound — just a sanity check.

### Anti-test: don't test what we'll change

We will NOT lock in the specific Phi-slot naming convention or
the for-style recognition as exhaustive tests. Those are
implementation details that future work may revise. We test
*outputs* (byte-compat goldens during migration; semantic
equivalence after Phase 8) and *structural invariants*
(open/close balance, chain coverage, ScheduleMeta population
completeness), not internal hooks. The first two structural
invariants survive the Phase 8 algorithm swap unchanged — a
correctly-emitted schedule has balanced open/close brackets and
covers every side-effect node regardless of which algorithm
produced it. ScheduleMeta population completeness survives in
*shape* but with the expected class tree updated: Phase 8 swaps
the assertion from "every control node has a
`Roundtrip::*` ScheduleMeta" to "every control node has a
`GCM::*` ScheduleMeta" (or whatever the destination scheduler
defines). The contract — populate, don't skip — is durable.

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

**Mitigation:** The relevant `Roundtrip::*` ScheduleMeta class is
the extension point. Any context-derived data codegen needs gets
added as a field on the appropriate ScheduleMeta subclass and
populated by the scheduler when it builds the node's ScheduleMeta.
If a mismatch surfaces during Phase 5, add the field to the
ScheduleMeta class (a small, visible code change) rather than
falling back to Context reads. Because the ScheduleMeta classes
are typed and gated at codegen, any addition is discoverable and
auditable.

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

#### R6 — Eager-pinning becomes load-bearing

The Phase 3d wiring writes a control predecessor into `inputs[0]`.
The eager-pinning scheduler reads it as emit order. If other code
(codegen helpers, future optimization passes, IR walkers) starts
reading `inputs[0]` as if it conveyed *dominance* information
rather than emit order, the Phase 8 algorithm swap becomes
proportionally harder: every external reader must be audited and
either retired or re-pointed at a real dominator-tree query.

**Mitigation:** discipline, *strengthened by the ScheduleMeta
indirection*. Codegen reads `$node->schedule_data`, not raw
`inputs[0]`. Any non-scheduler consumer that wants emit-related
information is now expected to look at `schedule_data` (the typed,
gated path) rather than at the chain (the implementation detail).
The interface contract is that `inputs[0]` on a side-effect node
carries the chain predecessor the parser put there; it is consumed
by the scheduler to determine emit order; nothing else reads it.
New code that wants dominance information must compute it from the
graph, not read it from `inputs[0]`. Reviewers of code touching
`inputs[0]` outside `lib/Chalk/IR/Scheduler.pm` should check this
on intake. If discipline fails, Phase 8 grows a cleanup sub-phase
to undo the violations.

#### R7 — Survey may invalidate GCM as destination

The pending literature survey
(`docs/research/2026-05-24-scheduler-literature-survey.md`) may
name a destination algorithm other than GCM, or it may surface
implementation cautions about GCM (e.g., Click's own follow-on
papers, or modern work on global code motion that supersedes the
1995 formulation). The eager-pinning interface is algorithm-
agnostic, so this does not block Phases 1-7; it does mean Phase
8's concrete plan is *provisional* until the survey lands.

**Mitigation:** Decision E (the `Schedule` interface as swap
point) is the structural mitigation — Phase 8's algorithm choice
is a private implementation detail behind a stable interface.
Phase 8's effort and test strategy are written generically over
"the destination algorithm" rather than over GCM specifically,
so the survey's conclusion plugs in without rewriting Phase 8's
scope.

#### R8 — ScheduleMeta schema drift

Different scheduler implementations own different ScheduleMeta
class trees (`Roundtrip::*` for the eager-pinning scheduler;
`GCM::*` for the eventual destination). If those trees diverge in
field names or shapes — e.g., `Roundtrip::Loop->iterator` vs
`GCM::Loop->loop_var` for the same underlying concept — then
codegen-per-mode has to track all the variants and the architectural
discipline of "one typed location" buys less than promised.

**Mitigation:** each scheduler owns its own class tree
exclusively; the abstract base `Chalk::Scheduler::ScheduleMeta`
carries no fields (or only `$node`, the back-reference to the IR
node it annotates); codegen gates ScheduleMeta access at the
boundary (isa/role/can/version checks) so a wrong-shape
ScheduleMeta fails loud rather than silently miscoding. The class
definitions are the canonical schema — there is no parallel doc
or table to maintain, no JSON schema, no IDL. If two schedulers
need to share a concept (e.g., both have a notion of "this Loop's
iterator variable"), the right move is to factor a shared mixin
or role, not to silently union the field sets.

### Rollback path

If the schedule path produces wrong output for a non-golden
fixture discovered late, the rollback during Phase 5 is:
toggle the test/build flag back to `_generate_from_mop`.
After Phase 6 deletion, the rollback is the prior commit on
the branch. Phase 6 should be a *single* commit so revert is
clean. The Phase 8 rollback is symmetric — the destination
scheduler lives behind the same `Schedule` interface as the
eager-pinning version, so reverting Phase 8 is reverting one
file (`lib/Chalk/IR/Scheduler.pm`) plus its test-corpus updates.

## 10. ScheduleMeta class tree

This section specifies the class tree introduced by Decision G and
referenced throughout Sections 3, 4, and 7. The tree is more
boilerplate than putting fields directly on the IR nodes; the win
is that there is exactly one typed location per (scheduler, IR
node class) pair, and that codegen reads through a gated boundary
rather than peeking at scattered fields.

### Abstract base

```perl
# lib/Chalk/Scheduler/ScheduleMeta.pm
package Chalk::Scheduler::ScheduleMeta {
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use feature 'class';

    class Chalk::Scheduler::ScheduleMeta {
        # back-reference to the IR node this ScheduleMeta annotates.
        # Useful for diagnostics ("which Loop did this come from?")
        # and for codegen that wants to recover the node from the
        # ScheduleMeta. Not load-bearing for codegen dispatch.
        field $node :param :reader;
    }
}
```

The base carries no form-specific fields. Subclasses add them.

### Roundtrip subtree (eager-pinning scheduler)

```
Chalk::Scheduler::ScheduleMeta              # abstract base
├── Chalk::Scheduler::Roundtrip::Loop
│     field $is_for_style :param :reader = false;
│     field $iterator     :param :reader = undef;  # foreach
│     field $list         :param :reader = undef;  # foreach
│     field $for_init     :param :reader = undef;  # C-style for
│     field $for_step     :param :reader = undef;  # C-style for
│
├── Chalk::Scheduler::Roundtrip::If
│     field $is_loop_jump :param :reader = false;
│
├── Chalk::Scheduler::Roundtrip::Phi
│     field $emit_slot      :param :reader = undef;  # VarDecl ref
│     field $synthetic_name :param :reader = undef;  # fallback
│
└── Chalk::Scheduler::Roundtrip::TryCatch
      field $catch_var :param :reader;
```

### GCM / destination subtree

Defined in Phase 8 when the destination scheduler is built.
Likely shape (illustrative, not committed):

```
Chalk::Scheduler::ScheduleMeta
└── Chalk::Scheduler::GCM::*
      # whatever fields GCM-style placement needs: dominator depth,
      # loop nesting, hoisted-invariant lists, branch probabilities,
      # etc. The Phase 8 author specifies these against the
      # destination algorithm.
```

The Roundtrip subtree is not deleted when the GCM subtree lands;
both coexist for as long as both schedulers do (which may be only
the Phase 8 cutover window, or longer if there's reason to keep
the eager-pinning scheduler around for debugging or regression
diff). After Phase 8 ships and stabilizes, Roundtrip subtree
deletion is a follow-up.

### Population contract

The scheduler that produces a `Chalk::IR::Schedule` MUST also
populate `schedule_data` on every IR node that codegen will read
it from. Concretely:

- Every `Loop` referenced by a `block_open` with form `while`,
  `foreach`, or `for` must have `schedule_data` set to a
  `Chalk::Scheduler::Roundtrip::Loop` (or, post-Phase-8, the
  destination scheduler's equivalent).
- Every `If` referenced by a `block_open` with form `if`, an
  `elsif`, or an `else`-followed-`block_open` must have
  `schedule_data` set.
- Every `TryCatch` referenced by a `block_open` with form `try`
  must have `schedule_data` set.
- Every `Phi` whose value is read by any node in the schedule
  must have `schedule_data` set.

Calling codegen on a Schedule whose nodes lack the appropriate
ScheduleMeta is a fatal error: the codegen gate fires at the
boundary. There is no silent default, no fallback to "empty
ScheduleMeta," no inference of the missing data from the chain.
This is intentional: missing ScheduleMeta is a scheduler bug,
and failing loud is how we find scheduler bugs in tests rather
than in production.

### Gate contract (codegen boundary)

Codegen MUST gate ScheduleMeta access at the boundary using a
typed check. The contract is the gating discipline. The gate
style is implementation detail:

```perl
# Illustrative; the actual codegen can use isa, role check,
# can() probe, or version field — whichever fits the site.
my $sd = $loop_node->schedule_data;
die "Codegen-for-Roundtrip requires Roundtrip::Loop, got "
    . (defined $sd ? ref($sd) : '<undef>')
    unless defined $sd
        && $sd isa Chalk::Scheduler::Roundtrip::Loop;

if ($sd->is_for_style) {
    my $init = $sd->for_init;
    my $step = $sd->for_step;
    ...
}
```

Different gate styles suit different situations:

- **isa check** when codegen knows exactly which scheduler
  produced the input (the common case during Phases 5-7, where
  the codegen is paired one-to-one with the eager-pinning
  scheduler).
- **role / capability check** when codegen accepts multiple
  ScheduleMeta variants that all expose the same method (e.g., a
  shared `is_for_style` role across Roundtrip and GCM Loops).
- **`can()` probe** when the codegen wants to feature-test for
  an optional ScheduleMeta capability.
- **schema-version field** when the project gains enough
  scheduler variants that a numeric version is cheaper than an
  isa tree walk. (Not needed today; mentioned for completeness.)

The gating discipline ensures that running a Roundtrip-specific
codegen path against a GCM ScheduleMeta (or vice versa) dies at
the boundary with a useful message, not at a deep call site with
"undefined method" or an off-by-one in an emitted string.

## Cross-references

- Prep doc: `docs/plans/2026-05-23-son-scheduler-prep.md`
- Pending literature survey (destination algorithm input for
  Phase 8): `docs/research/2026-05-24-scheduler-literature-survey.md`
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
level needed for the *initial* eager-pinning scheduler. The unread
sources remain relevant — most of them are direct inputs to the
Phase 8 destination-scheduler decision, and the pending literature
survey (`docs/research/2026-05-24-scheduler-literature-survey.md`)
is where they get properly digested:

- **Click 1995 paper** — primary reference for GCM, which is the
  current frontrunner for the Phase 8 destination algorithm. Will
  be consumed by the literature survey, not this design doc.
- **Simple SoN repo, Chapters 5 and 7** — concrete code patterns
  for if/else and loop scheduling; worth a skim before writing
  Phase 4 of the eager-pinning scheduler.
- **Turboshaft / V8 paper** — confirms the eager-pinning approach
  in a production compiler; useful as a citation for the
  transitional design, and as a data point in the survey on
  whether eager-pinning-as-permanent is defensible.
- **Demange & Retana** — theoretical foundation for structured
  control flow in SoN; consult if a specific question arises about
  the semantics of `Region` or `Phi`. Relevant to Phase 8's
  semantic-equivalence checker design.
