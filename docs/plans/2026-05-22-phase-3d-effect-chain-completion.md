# Phase 3d — IR Effect Chain Completion

**Date:** 2026-05-22
**Status:** Design.
**Depends on:** IR completeness audit
(`docs/plans/2026-05-22-ir-completeness-audit.md`).
**Blocks:** SoN scheduler design / Phase 4 finish-up.

## Goal

Close the gaps the IR completeness audit found. After this phase,
every Perl construct in Chalk's subset produces an IR node that is
both (a) present in `MOP::Method->graph`, and (b) reachable from a
terminator (`Return`/`Unwind`) by walking `inputs()` backward
through the control chain.

This unblocks SoN scheduler design: a scheduler can only schedule
what's in the graph and reachable from terminators.

## Non-goals

- Designing the scheduler itself. That comes after.
- Adding new node types. The fix is in the *wiring* of existing
  node types, not the type system.
- Changing the `inputs[0] = control` convention. That convention
  already works for VarDecl/Return/Unwind; we extend it.
- Optimization. No DCE, no GVN, no hoisting. Just correctness of
  the effect chain.
- Removing `MOP::Method->body`. The audit doesn't require its
  removal; that's a separate cleanup downstream.

## What the audit revealed

Phase 3a-migration's `Block` action contains a **control-chain
post-processing pass** at `lib/Chalk/Bootstrap/Perl/Actions.pm:1494-1545`.
This pass iterates the block's statement list and rebuilds nodes so
each one's `inputs[0]` points at the previous statement's node (or
`Start` for the first). It handles three node types:

- `VarDecl` — rebuilds with current control as inputs[0]
- `Return` — rebuilds (via `make_cfg`) with current control
- `Unwind` — same as Return

**All other statement-position node types are silently skipped.**
That includes:

- `Call` (statement-position) — 7 audit cases ([miss])
- `Assign` (`BinaryExpr`-shaped, statement-position) — 4 cases ([miss])
- `CompoundAssign` — 4 cases ([miss])
- `RegexSubst` — 1 case ([miss])
- `If` — 5 cases ([unreach])
- `Loop` — 4 cases ([unreach])
- `TryCatch` — 1 case ([unreach])

For [miss] cases the node isn't in the graph at all because the
action constructs it without calling `$graph->merge(...)`. For
[unreach] cases the node IS in the graph but the post-processing
pass doesn't recognize it as a statement that should advance the
control chain.

The fix is straightforward: extend the post-processing pass.

## Design

### Pass shape

The existing pass at `Block` (Actions.pm:1502+) walks `@stmts` in
source order, maintaining `$current_control` (initially `Start`).
For each statement:
- If the statement is a recognized side-effect type, rebuild it
  with `inputs[0] = $current_control`, replace it in `@stmts` and in
  `$graph`, and advance `$current_control` to the rebuilt node.
- If it's `Return`/`Unwind`, rebuild but **don't** advance — those
  are terminators.

### Extended pass

The same shape, with more arms:

```
for my $i (0..$#stmts) {
    my $s = $stmts[$i];
    next unless blessed($s);

    # [Existing] VarDecl
    if ($s isa Chalk::IR::Node::VarDecl) { ... }

    # [Existing] Return / Unwind (terminators; don't advance control)
    elsif ($s isa Chalk::IR::Node::Return
            || $s isa Chalk::IR::Node::Unwind) { ... }

    # [New] Statement-position side-effect data nodes
    elsif ($s isa Chalk::IR::Node::Call
            || $s isa Chalk::IR::Node::Assign            # BinaryExpr role
            || $s isa Chalk::IR::Node::CompoundAssign
            || $s isa Chalk::IR::Node::RegexSubst) {
        # Today: not in graph at all. Need to MERGE before chaining.
        # Tomorrow: rebuild with control input, merge replacement.
        ...
        $current_control = $rebuilt;
    }

    # [New] CFG control-flow statements (If/Loop/TryCatch).
    # These already have control input AS their first input
    # (via $factory->make('If', control => $ctrl) at construction
    # time), but the construction-time control was the pre-If
    # scope.control, not the chained predecessor at Block-fixup time.
    # Additionally, control after the CFG node should advance past
    # its Region (for If) or post-loop exit (for Loop).
    elsif ($s isa Chalk::IR::Node::If) {
        # If's inputs[0] is its control input. Rebuild only if it
        # disagrees with $current_control.
        # Advance $current_control to the post-If Region (already
        # constructed; lives in annotations->{if_node}'s region or
        # similar — need to look up the Region for this If).
        ...
    }

    elsif ($s isa Chalk::IR::Node::Loop) {
        # Same shape: rebuild Loop's entry_ctrl if it disagrees;
        # advance $current_control to post-loop exit projection.
        ...
    }

    elsif ($s isa Chalk::IR::Node::TryCatch) {
        # Same.
        ...
    }
}
```

### Two sub-problems

**Sub-problem A: shape change for statement-position data nodes.**

Today `Call->inputs = [name_node, args_arrayref]`. There's no
control input slot. To put a Call on the control chain we have to
either:

1. **Prepend a control slot to `inputs`** — `[control, name_node,
   args_arrayref]`. Affects `content_hash` and every codegen
   reader that indexes `inputs[0]`/`inputs[1]`. ~10+ codegen
   sites to update.
2. **Add a `control_in` field on the affected node classes**
   alongside `inputs` — keep data inputs as-is, control input is
   separate. Affects only the IR class definition and the Block
   pass; codegen readers unchanged.

(2) is the lower blast radius and matches the existing pattern of
class-specific accessors (e.g., `Call->name`, `Call->dispatch_kind`
are separate from `inputs`). The same field shape can be applied
uniformly to `Call`, `Assign` (`BinaryExpr` when at statement
position), `CompoundAssign`, `RegexSubst`.

The Block pass becomes:

```
if ($s isa Chalk::IR::Node::Call
        || $s isa Chalk::IR::Node::Assign
        ...) {
    # Was this node merged? If not, merge it now.
    unless ($graph->contains($s)) {
        $graph->merge($s);
    }
    # Set the control input. Today the node has none.
    $s->set_control_in($current_control);
    $current_control = $s;
}
```

`set_control_in` is the only mutator we add. It's the same shape
as `Loop::set_backedge_ctrl` and `Phi::set_backedge` — late-binding
control wiring after construction. This keeps the hash-cons
invariant intact (content_hash doesn't include control_in; two Call
nodes with the same name and args still hash-cons together even
if they're at different control points — which is arguably wrong,
but it preserves today's behavior until we have a reason to
change it).

**Sub-problem B: control advancement past CFG nodes.**

`If` is built with `inputs[0] = $control` (the pre-If control). The
post-If control point is the `Region` node that merges the two
projections. The IfStatement action constructs the Region and even
calls `$sa->update_scope($merged_scope->with_control($region))` —
but that update doesn't reach IfStatement's siblings in time (the
audit established this: sibling actions see only their own subtree,
not their siblings' completed state).

The Block fixup pass *does* see the completed IfStatement node and
can chase from there. The pass needs to:

1. Confirm the If's `inputs[0]` matches `$current_control` (rebuild
   if not — but If is `make_cfg`, not hash-consed, so rebuilding
   means allocating a new CFG node and rewiring projections; this
   is more involved than for data nodes).
2. Find the post-If Region. It's attached via the Phi nodes'
   `region` field or via annotations on the IfStatement's context.
3. Set `$current_control = $region`.

The Region itself is already in the graph (the IfStatement action
calls `$graph->merge($region)`). It just needs to be findable from
the If node. The cleanest way: add a `region` accessor on the If
node that returns the Region the IfStatement constructed for it.
Set at IfStatement-action time via a late-binding setter.

Similar pattern for Loop (post-loop exit Proj) and TryCatch (post-catch
Region).

### Rebuilding CFG nodes when control disagrees

For data nodes the rebuild is cheap (hash-consed; might dedupe). For
CFG nodes (If, Loop, TryCatch, Region, Proj) it's more expensive
because they're `make_cfg`'d and each rebuild allocates a new node
with a new sequential ID. Multiple downstream nodes (Projs, Phis,
Region) already reference the original If.

The pragmatic answer: **don't rebuild CFG nodes; mutate their
control input.** Same precedent as `Loop::set_backedge_ctrl`. Add
`If::set_control_in`, `Loop::set_control_in`, `TryCatch::set_control_in`.

Late-binding mutation of control inputs is already legal in the IR
(Phi::set_backedge, Loop::set_backedge_ctrl). Adding it for the
forward control input is a small, principled extension.

### What the pass looks like end-to-end

Pseudocode:

```
my $current_control = Start;
for my $i (0..$#stmts) {
    my $s = $stmts[$i];
    next unless blessed($s);

    if ($s isa VarDecl) {
        # Existing logic: rebuild via $factory->make('VarDecl', ...)
        # (hash-consed; cheap)
        $s = rebuild_vardecl($s, $current_control);
        $stmts[$i] = $s;
        $current_control = $s;
    }
    elsif ($s isa Return || $s isa Unwind) {
        # Existing logic: rebuild via $factory->make_cfg
        $s = rebuild_terminator($s, $current_control);
        $stmts[$i] = $s;
        # Don't advance: terminator.
    }
    elsif ($s isa Call || $s isa Assign || $s isa CompoundAssign || $s isa RegexSubst) {
        # NEW: ensure in graph; mutate control_in
        $graph->merge($s) unless $graph->contains($s);
        $s->set_control_in($current_control);
        $current_control = $s;
    }
    elsif ($s isa If) {
        # NEW: mutate control input; advance to Region
        $s->set_control_in($current_control);
        my $region = $s->region;  # late-binding accessor set at construction
        $current_control = $region // $s;
    }
    elsif ($s isa Loop) {
        $s->set_entry_ctrl($current_control);
        my $exit = $s->exit_proj;  # late-binding accessor
        $current_control = $exit // $s;
    }
    elsif ($s isa TryCatch) {
        $s->set_control_in($current_control);
        my $region = $s->merge_region;
        $current_control = $region // $s;
    }
}
```

## Implementation plan

In order, with TDD at each step. Each step ends with a green test
and the IR audit producing fewer failures.

### Step 1: codify the audit as a test

- Convert `t/fixtures/ir-audit-corpus.pl` into
  `t/bootstrap/mop/ir-completeness.t`.
- For each snippet, assert: every body item is in graph AND
  reachable from a terminator.
- All 26 cases fail today. TDD red.
- One commit.

### Step 2: handle bare statement-position Calls

- Add `Call->control_in` field with reader and `set_control_in`.
- Add `$graph->contains($node)` method on `Chalk::IR::Graph` (used
  to check if a node has been merged). Or use the existing cache
  membership check.
- Extend Block pass to handle Call.
- Audit cases B1, B2, B3, B5, B6, B7, B8 turn green. 7 of 26.
- TDD: write or update test that asserts B1-B8 are reachable. Run
  ir-completeness.t — 7 cases flip from fail to pass.
- One commit.

### Step 3: handle statement-position Assign/CompoundAssign/RegexSubst

- Add same `control_in` field to `BinaryExpr` (or specifically when
  used as Assign), `CompoundAssign`, `RegexSubst`.
- Decide: do we need a distinguishing `Assign` node type, or do we
  use `BinaryExpr` with op `=`? The current code uses BinaryExpr.
- Extend Block pass.
- Audit cases A4, C1-C5, J2, K1, K2 turn green. 9 of 26.
- One commit.

### Step 4: handle If

- Add `If->set_control_in` (mutator).
- Add `If->region` late-binding accessor; set in IfStatement
  action when the Region is constructed.
- Extend Block pass to handle If: mutate control_in, advance to
  Region.
- Audit cases D1, D4, D7, E2, E4 turn green. 5 more.
- One commit.

### Step 5: handle Loop

- Add `Loop->set_entry_ctrl` (if not already present — it has
  `set_backedge_ctrl`; check what's there).
- Add `Loop->exit_proj` accessor.
- Extend Block pass.
- Audit cases D2, D3, D5, E3 turn green. 4 more.
- One commit.

### Step 6: handle TryCatch

- Same shape as If/Loop.
- Audit case D8 turns green. 1 more.
- One commit.

### Step 7: handle "my sub" (the SubInfo body case)

- I3 is a different bug — `my sub` produces a `Chalk::IR::SubInfo`
  metadata struct in body, not an IR node. Probably needs its own
  separate handling. May be in scope for Phase 3d or may be a
  cleanup to defer.
- If deferable: skip and note as remaining.

### Step 8: full audit re-run

- Run `script/probe-ir.pl t/fixtures/ir-audit-corpus.pl`. Expect 0
  WARNs (or just the I3 case if deferred).
- Run the full test suite. Identify regressions.
- Run `codegen-byte-compat.t`. The goldens may fail if the IR
  changes cascade into codegen output. **Expected.** The goldens
  pin pre-Phase-3d behavior; Phase 3d adds nodes to the graph but
  shouldn't change codegen output (codegen still walks body). If
  goldens fail, investigate whether it's a real regression or a
  consequential change.

## Risks

**Risk 1: hash-cons interaction with mutation.**

Adding `set_control_in` to data nodes that are hash-consed means
two Calls with the same `(name, args)` will hash-cons together but
then have their control_in mutated independently — except they're
the same Perl object, so the second mutation overwrites the first.

In practice this is fine because at statement-position each Call is
at a distinct source position and produces its own node. But if a
statement-Call ever hash-consed with an expression-Call (same name
+ args), the expression-Call would acquire a stale control_in.

Mitigation: exclude `control_in` from `content_hash` (already the
plan) AND ensure that hash consing happens *before* `set_control_in`
is called. Add an assertion in `set_control_in` that the field is
either unset or being set to the same value — defensive but cheap.

**Risk 2: codegen reading control_in unexpectedly.**

Today's codegen doesn't read `Call->inputs[0]` as a control input;
it reads it as the name node. Adding a separate `control_in` field
that codegen ignores keeps codegen unchanged. Verify this is true
for every Call/Assign emitter.

**Risk 3: regressions in Phase 3b/3c Phi tests.**

The IfStatement / Loop actions construct Region/Phi/Proj nodes
based on the parsing-time control. If Block-pass mutation of the
If's control_in is delayed, the Region's contained Projs and the
Phi's `region` reference might end up referring to the original
not-yet-rebuilt structure.

The mitigation: don't rebuild CFG nodes, mutate their control
inputs. Region/Proj/Phi references stay valid because we're not
allocating new nodes.

Run the existing 8 Phase 3b/3c TDD tests after each Phase 3d step.
They must stay green.

**Risk 4: cross-block interaction.**

A Block inside an If branch has its own Block-pass running on its
own statement list. The outer Block-pass sees the If as one
statement and chains past it. The inner Block-pass chains the
branch's body. The branch body's chain ends with whatever the last
statement is (often a Return, or fall-through).

For Phi insertion at the Region to be correct, the branch bodies
must terminate cleanly. Today they do — IfStatement constructs the
projections and Region, the branch Phi merges values. Phase 3d
doesn't disturb this; it only fixes the *outer* chain past the If.

## Open design questions

These need answers before Step 4 starts:

**Q1: When IfStatement constructs the If/Region, does it set
`if_node->region(region_node)` so the Block pass can find it later?**
The IfStatement action currently stashes the region into
`annotations->{if_node}` and friends. The Block pass would need to
either look up via annotations or via a new accessor. Adding a
direct accessor on the If node is cleaner.

**Q2: Should we add the accessor by late-binding setter, or extend
the If node's `inputs` to include the Region as a member?**
Late-binding setter (matching Loop::set_backedge_ctrl, Phi::set_backedge)
is more consistent with existing IR patterns.

**Q3: For Loop, what's the post-loop control point?** Loop has
entry_ctrl, backedge_ctrl. The post-loop exit is a Proj on a final
test. We need to identify which existing node serves this role, or
add one.

**Q4: For TryCatch, is the merge point a Region (same as If) or
something else?** Need to look at how TryCatchStatement constructs
its CFG.

These can be answered by reading the existing IfStatement / Loop /
TryCatch construction code. Doing that as part of Step 4-6
preparation, not now.

## Open questions about node-class shape

Three small things to confirm:

- **Is `BinaryExpr` the right class for `Assign`?** The audit shows
  `Assign` as a distinct operation name. Check whether
  `Chalk::IR::Node::Assign` exists, or whether it's
  `Chalk::IR::Node::BinaryExpr` with `op='='`. Implementation
  depends.
- **Where is `CompoundAssign` defined?** Confirm it's a distinct
  class.
- **Where is `RegexSubst` defined?** Confirm.

## Exit criteria

- `t/bootstrap/mop/ir-completeness.t` is 100% green.
- All existing Phase 3a/3b/3c tests stay green.
- All Phase 4 acceptance tests stay green.
- `codegen-byte-compat.t` either stays green or, if it fails, the
  reason is understood and accepted (e.g., an extra correct
  statement now appears in generated code that the golden didn't
  expect).
- The IR audit's reproduction returns 0 WARNs (or only the I3 case
  if explicitly deferred).

## Scope note

Phase 3d is genuinely new compiler work. It is NOT plumbing. The
work is small in code change (one fixup pass, a few late-binding
setters, a handful of accessor methods) but high in design care.
Each step should be reviewed before the next is started.

Each step is one commit. Total estimated commits: 7-8 (steps 1-7
plus a possible refactor pass).
