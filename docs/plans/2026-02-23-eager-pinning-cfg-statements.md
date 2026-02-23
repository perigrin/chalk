# Eager Pinning: CFG Statement Collection for Code Generation

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bridge the gap between CFG nodes (If/Region/Phi/Loop/Proj) and code generation by collecting body statements per control region at parse time, enabling targets to emit structured control flow without a graph scheduler.

**Architecture:** Extend cfg_state with a `statements` field that maps Proj/Region nodes to their body IR nodes. Actions.pm populates these during on_complete. A lightweight pattern matcher in each target walks the cfg_state to extract statement lists and dispatch to existing `emit_cfg_*` methods.

**Tech Stack:** Perl 5.42.0, `feature class`, Earley parser with FilterComposite semiring, comonad Context threading.

**Worktree:** `/home/perigrin/dev/chalk/.worktrees/sea-of-nodes-cfg` (branch: `sea-of-nodes-cfg`)

**Perl:** `$HOME/.local/share/pvm/versions/5.42.0/bin/perl`

**Test command:** `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/<file>.t`

**Skills required:** `writing-perl-5.42.0`, `test-driven-development`

**Prerequisite commits already on branch:**
- `d51c82e` — build_cfg/build_scope removed from SemanticAction
- `8c0677f` — parse-time CFG construction in ForeachStatement/PostfixModifier
- `753e31e` — scope merging in multiply/on_merge
- `4322ac7` — cfg_state propagation through Earley chart

**GCM upgrade path:** This design keeps control region assignment in the cfg_state side-table (not baked into IR nodes), so a future GCM pass can recompute assignments without tearing out infrastructure. See research notes in previous session.

---

## Task 1: Add `statements` Field to cfg_state

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`
- Create: `t/bootstrap/cfg-statements.t`

**Step 1: Write failing test**

Create `t/bootstrap/cfg-statements.t` that verifies cfg_state can carry a `statements` field:

```perl
# ABOUTME: Tests that cfg_state carries statement lists per control region.
# ABOUTME: Verifies the eager pinning approach for Sea of Nodes code generation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::SemanticAction;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

# Verify update_cfg accepts statements field
my $ctx = $sa->one();
my $start = $factory->make('Start');
my $stmt1 = $factory->make('Constant', const_type => 'string', value => 'hello');

$sa->set_cfg_state($ctx, {
    control    => $start,
    scope      => Chalk::Bootstrap::Scope->new(),
    statements => [$stmt1],
});

my $state = $sa->cfg_state($ctx);
ok(defined $state, 'cfg_state returns state with statements');
is(ref($state->{statements}), 'ARRAY', 'statements is an arrayref');
is(scalar($state->{statements}->@*), 1, 'statements has one entry');
is($state->{statements}->[0], $stmt1, 'statement is the expected node');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/cfg-statements.t`
Expected: PASS (cfg_state is just a hashref — statements field is already storable without code changes)

Note: This test may pass immediately since cfg_state stores arbitrary hashrefs. If so, that's fine — we're establishing the contract. The real RED comes in Task 2.

**Step 3: Verify multiply propagates statements**

Add to the same test file: verify that when two contexts are multiplied, and one has statements in its cfg_state, the result's cfg_state includes those statements.

```perl
# Verify multiply propagates statements through cfg_state
$sa->reset_cache();
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
$factory = Chalk::Bootstrap::IR::NodeFactory->instance();

my $one = $sa->one();
my $scan = $sa->on_scan(
    { value => $one, rule => undef }, 0, 5, 'test'
);
ok(defined $scan, 'scan succeeded');

# Set statements on the scan result
my $start2 = $factory->make('Start');
my $stmt2 = $factory->make('Constant', const_type => 'integer', value => 42);
$sa->set_cfg_state($scan, {
    control    => $start2,
    scope      => Chalk::Bootstrap::Scope->new(),
    statements => [$stmt2],
});

# Multiply with another scan — statements should propagate
my $scan2 = $sa->on_scan(
    { value => $scan, rule => undef }, 0, 10, 'more'
);
my $mul_state = $sa->cfg_state($scan2);
ok(defined $mul_state, 'multiply result has cfg_state');
# statements may or may not propagate through multiply — this test
# establishes the current behavior for documentation
```

**Step 4: Run test**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/cfg-statements.t`
Expected: PASS

**Step 5: Commit**

```bash
git add t/bootstrap/cfg-statements.t
git commit -m "test: establish cfg_state statements field contract"
```

---

## Task 2: IfStatement Populates cfg_state with Body Statements

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (IfStatement method, ~line 1735)
- Modify: `t/bootstrap/cfg-statements.t`

**Step 1: Write failing test**

Add to `cfg-statements.t`: parse `if (1) { 42 } else { 99 }` via the full pipeline, then inspect cfg_state for the result's If node. Verify that the TrueProj and FalseProj entries in cfg_state carry the body statements.

```perl
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::Target::Perl;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CfgStmtTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::CfgStmtTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    my $sa = $semiring->semirings()->[4];

    # --- Test: IfStatement populates cfg_state with body statements ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('if (1) { 42 } else { 99 }');
        ok(defined $result, 'if/else parses');

        my $sem_ctx = $result->[4];
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state exists');

        # The control should be a Region
        my $control = $state->{control};
        is($control->operation(), 'Region', 'control is Region');

        # Check for statements on the Region or its Proj inputs
        # The then_stmts and else_stmts should be accessible
        ok(defined $state->{then_stmts}, 'then_stmts in cfg_state');
        ok(defined $state->{else_stmts}, 'else_stmts in cfg_state');
        ok(ref($state->{then_stmts}) eq 'ARRAY', 'then_stmts is array');
        ok(ref($state->{else_stmts}) eq 'ARRAY', 'else_stmts is array');
    }
}
```

**Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/cfg-statements.t`
Expected: FAIL — `then_stmts` and `else_stmts` are not present in cfg_state (IfStatement doesn't store them yet)

**Step 3: Modify IfStatement in Actions.pm**

At ~line 1804 in IfStatement, where `update_cfg` is called, add the body statements to the cfg_state:

```perl
$sa->update_cfg({
    control    => $region,
    scope      => $state->{scope},
    then_stmts => $then_body,
    else_stmts => $else_body,
    if_node    => $if_node,
    true_proj  => $true_proj,
    false_proj => $false_proj,
});
```

This stores all the information the targets need to call `emit_cfg_if`. The `if_node`, `true_proj`, `false_proj` references let the target pattern-match the CFG subgraph without walking use-def chains.

**Step 4: Run test to verify it passes**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/cfg-statements.t`
Expected: PASS

**Step 5: Run existing tests for regression**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/cfg-if-else.t`
Expected: PASS (adding fields to cfg_state doesn't break existing control/scope checks)

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/cfg-statements.t
git commit -m "feat: IfStatement stores body statements in cfg_state for eager pinning"
```

---

## Task 3: ElsifChain Populates cfg_state with Body Statements

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (ElsifChain method, ~line 1818)
- Modify: `t/bootstrap/cfg-statements.t`

**Step 1: Write failing test**

Add test: parse `if (1) { 42 } elsif (2) { 99 } else { 0 }`. Verify the outer cfg_state has then_stmts, and the else_stmts contains the elsif's cfg_state (which itself has then_stmts and else_stmts).

**Step 2: Run test — FAIL**

**Step 3: Add CFG construction and statement collection to ElsifChain**

ElsifChain currently only creates an IfStmt Constructor. Add the same pattern as IfStatement: create If/Proj/Region, store body statements in update_cfg.

**Step 4: Run test — PASS**

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/cfg-statements.t
git commit -m "feat: ElsifChain stores body statements in cfg_state"
```

---

## Task 4: ForeachStatement Populates cfg_state with Body Statements

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (ForeachStatement method, ~line 1864)
- Modify: `t/bootstrap/cfg-statements.t`

**Step 1: Write failing test**

Add test: parse `for my $x (1, 2, 3) { $x }`. Verify cfg_state has `body_stmts`, `loop` node, `loop_if`, `body_proj`, `exit_proj` (everything `emit_cfg_loop` needs).

**Step 2: Run test — FAIL**

ForeachStatement already builds Loop/If/Proj/Region (commit 8c0677f) but doesn't store body_stmts.

**Step 3: Update ForeachStatement's update_cfg call**

At ~line 1918 in ForeachStatement, expand the update_cfg call:

```perl
$sa->update_cfg({
    control    => $region,
    scope      => $state->{scope},
    body_stmts => $body,
    loop       => $loop,
    loop_if    => $if_node,
    body_proj  => $body_proj,
    exit_proj  => $exit_proj,
    iterator   => $iterator,
    list       => $list,
});
```

**Step 4: Run test — PASS**

**Step 5: Run cfg-loop.t for regression**

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/cfg-statements.t
git commit -m "feat: ForeachStatement stores body statements and loop nodes in cfg_state"
```

---

## Task 5: PostfixModifier Populates cfg_state with Body Statements

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (PostfixModifier method, ~line 1654)
- Modify: `t/bootstrap/cfg-statements.t`

PostfixModifier is trickier: the body statement comes from the *parent* rule (SimpleStatement), not from PostfixModifier's own children. PostfixModifier only sees the condition.

**Step 1: Write failing test**

Parse `push @r, $_ for 1, 2, 3;` (or similar). This is currently a TODO because the grammar doesn't trigger PostfixModifier. Mark the test as TODO and document the limitation.

For the non-TODO path: test postfix `if` — `return 1 if $x;`. Verify cfg_state has the expected fields.

**Step 2: Implement what's possible**

For postfix `if`/`unless`: the body is the statement before the modifier. PostfixModifier doesn't have access to it — the parent SimpleStatement does. The solution: SimpleStatement wraps the PostfixModifier cfg_state with the body statement when it assembles the full statement.

This may require modifying SimpleStatement to detect when a PostfixModifier is present and add the body to cfg_state. Document this dependency in the test.

**Step 3: Run tests**

**Step 4: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/cfg-statements.t
git commit -m "feat: PostfixModifier cfg_state with body statements (partial — TODO for postfix for)"
```

---

## Task 6: Add cfg_state Pattern Matcher to Perl Target

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/Perl.pm`
- Create: `t/bootstrap/perl-target-cfg-dispatch.t`

This is the critical integration task. The Perl target currently dispatches on Constructor class names (IfStmt, ForeachLoop, etc.). Add a new dispatch path that checks cfg_state first.

**Step 1: Write failing test**

Create `t/bootstrap/perl-target-cfg-dispatch.t`. Build an IR manually with cfg_state populated (simulating what Actions.pm now does). Pass it to the Perl target and verify it emits correct Perl code.

```perl
# Build If/Proj/Region IR manually
my $start   = $factory->make('Start');
my $cond    = $factory->make('Constant', const_type => 'integer', value => 1);
my $if_node = $factory->make('If', control => $start, condition => $cond);
my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
my $region  = $factory->make('Region', controls => [$true_proj, $false_proj]);

my $then_stmt = $factory->make('Constant', const_type => 'integer', value => 42);
my $else_stmt = $factory->make('Constant', const_type => 'integer', value => 99);

# Create a SemanticAction and populate cfg_state
my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
my $ctx = $sa->one();
$sa->set_cfg_state($ctx, {
    control    => $region,
    scope      => Chalk::Bootstrap::Scope->new(),
    then_stmts => [$then_stmt],
    else_stmts => [$else_stmt],
    if_node    => $if_node,
    true_proj  => $true_proj,
    false_proj => $false_proj,
});

# Generate code via Perl target using cfg_state
# (This is the part that needs a new API on the target)
my $target = Chalk::Bootstrap::Target::Perl->new();
my $code = $target->emit_from_cfg_state($sa, $ctx);
like($code, qr/if.*\{/, 'emitted code contains if');
like($code, qr/42/, 'emitted code contains then body');
like($code, qr/99/, 'emitted code contains else body');
```

**Step 2: Run test — FAIL** (emit_from_cfg_state doesn't exist)

**Step 3: Implement emit_from_cfg_state**

Add a method to `Perl.pm` that takes a SemanticAction and a Context, reads cfg_state, and dispatches to the appropriate emit_cfg_* method:

```perl
method emit_from_cfg_state($sa, $ctx) {
    my $state = $sa->cfg_state($ctx);
    return unless defined $state;

    my $control = $state->{control};
    my $op = $control->operation();

    if ($op eq 'Region') {
        # Check if this is an if/else Region
        if (defined $state->{if_node}) {
            return $self->emit_cfg_if(
                $state->{if_node},
                $state->{true_proj},
                $state->{false_proj},
                $state->{then_stmts} // [],
                $state->{else_stmts} // [],
            );
        }
        # Check if this is a loop exit Region
        if (defined $state->{loop}) {
            return $self->emit_cfg_loop(
                $state->{loop},
                $state->{loop_if},
                $state->{body_proj},
                $state->{exit_proj},
                $state->{body_stmts} // [],
            );
        }
    }
    return;
}
```

**Step 4: Run test — PASS**

**Step 5: Run existing Perl target tests for regression**

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/Perl.pm t/bootstrap/perl-target-cfg-dispatch.t
git commit -m "feat: Perl target dispatch from cfg_state via emit_from_cfg_state"
```

---

## Task 7: Add cfg_state Pattern Matcher to XS Target

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/XS.pm`
- Create: `t/bootstrap/xs-target-cfg-dispatch.t`

Same pattern as Task 6, but for XS target. The emit_cfg_* methods already accept `$declared_vars`, so `emit_from_cfg_state` needs to thread that through.

**Step 1: Write failing test** (same shape as Task 6 but verifying C output)

**Step 2: Run test — FAIL**

**Step 3: Implement `emit_from_cfg_state` on XS target**

**Step 4: Run test — PASS**

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/XS.pm t/bootstrap/xs-target-cfg-dispatch.t
git commit -m "feat: XS target dispatch from cfg_state via emit_from_cfg_state"
```

---

## Task 8: Wire _emit_node / _emit_xs_stmt to Try cfg_state First

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` (_emit_node method)
- Modify: `lib/Chalk/Bootstrap/Perl/Target/XS.pm` (_emit_xs_stmt method)
- Modify: `t/bootstrap/perl-target-cfg-dispatch.t`
- Modify: `t/bootstrap/xs-target-cfg-dispatch.t`

The existing dispatch in `_emit_node` (Perl.pm ~line 88) and `_emit_xs_stmt` (XS.pm ~line 668) checks Constructor class names. Add a check: if the node has an associated cfg_state with an `if_node` or `loop` field, use `emit_from_cfg_state` instead.

This requires the target to have access to the SemanticAction instance. Options:
- Pass it as a field on the target (set during `generate()`)
- Pass it as a parameter to `_emit_node`

**Step 1: Write failing test**

Test full pipeline: parse `if (1) { 42 } else { 99 }`, generate Perl code, verify it contains `if` structure (not IfStmt Constructor dump).

**Step 2: Implement the dual dispatch**

In `_emit_node`, before checking `$class`:
```perl
if (defined $semantic_action) {
    # Check if this Constructor has cfg_state with control flow
    # (lookup by the Constructor node in a cfg_state registry)
    ...
}
```

The challenge: _emit_node receives an IR node (Constructor), but cfg_state is keyed by Context refaddr. We need a mapping from IR node → cfg_state. Options:

(a) **Store cfg_state reference on the Constructor node itself** — breaks immutability
(b) **Build an IR-node → cfg_state lookup during generate()** — walk the final Context tree, collect cfg_state entries keyed by IR node refaddr
(c) **Replace Constructor creation entirely** — Actions.pm stops making IfStmt/ForeachLoop, returns the cfg_state's control node instead

Option (c) is the cleanest and aligns with the original Task 13 plan. But it requires updating all tests that expect IfStmt/ForeachLoop Constructors.

Option (b) is the migration-friendly approach: existing tests keep working, new dispatch is additive.

**Decision point for perigrin:** Which approach? The plan proceeds with (b) as the conservative choice, noting that (c) is the end goal.

**Step 3: Implement option (b)**

Add a method `_build_cfg_lookup($sa, $root_ctx)` that walks the Context tree and builds a hash mapping IR node refaddr → cfg_state entry. Call it at the start of `generate()`.

**Step 4: Run tests — PASS**

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/Perl.pm lib/Chalk/Bootstrap/Perl/Target/XS.pm \
        t/bootstrap/perl-target-cfg-dispatch.t t/bootstrap/xs-target-cfg-dispatch.t
git commit -m "feat: wire _emit_node to try cfg_state dispatch before Constructor class"
```

---

## Task 9: Full Pipeline Integration Test

**Files:**
- Modify: `t/bootstrap/cfg-statements.t`

**Step 1: Write full round-trip test**

Parse real Perl code containing if/else and foreach loops. Generate Perl code via the target. Verify the generated code is valid Perl (eval it) and produces correct results.

```perl
my $code = 'if (1) { 42 } else { 99 }';
# parse → IR with cfg_state → target generates Perl → eval generated code
```

**Step 2: Run test**

**Step 3: Commit**

```bash
git add t/bootstrap/cfg-statements.t
git commit -m "test: full pipeline round-trip for cfg_state eager pinning"
```

---

## Task 10: Stop Creating IfStmt Constructor (After Pipeline Verified)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm`
- Modify: `t/bootstrap/perl-ir-tier-c.t`
- Modify: `t/bootstrap/perl-actions-tier-c.t`

**Step 1: Remove IfStmt Constructor creation from IfStatement**

IfStatement currently creates both an IfStmt Constructor AND CFG nodes. Remove the IfStmt creation. Return the Region node (or undef — the IR value is now secondary to cfg_state).

**Step 2: Update tests that expect IfStmt**

`perl-ir-tier-c.t` has tests expecting IfStmt Constructors at specific lines. Replace with tests that verify cfg_state contains the expected If/Region structure.

**Step 3: Run full test suite**

**Step 4: Commit**

---

## Task 11: Stop Creating ForeachLoop/PostfixLoop Constructors

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm`
- Modify: `t/bootstrap/perl-ir-tier-c.t`

Same pattern as Task 10 for ForeachStatement and PostfixModifier.

---

## Task 12: Remove Legacy Dispatch from Targets

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/Perl.pm`
- Modify: `lib/Chalk/Bootstrap/Perl/Target/XS.pm`

Remove `_emit_if_stmt`, `_emit_foreach_loop`, `_emit_postfix_loop`, `_emit_next_unless` methods. Remove the Constructor class dispatch for these types. All control flow now goes through `emit_from_cfg_state`.

Keep data-flow Constructor dispatch (BinaryExpr, MethodCallExpr, etc.) unchanged.

---

## Task 13: Final Verification

**Step 1: Run all bootstrap tests**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/*.t
```

**Step 2: Verify no references to removed types**

```bash
grep -r 'IfStmt\|ForeachLoop\|PostfixLoop\|NextUnless' lib/Chalk/Bootstrap/Perl/Actions.pm
# Should return no hits

grep -r 'build_cfg\|build_scope' lib/ t/
# Should return no hits
```

**Step 3: Commit final cleanup**

---

## Summary

| Task | Description | Risk | Dependencies |
|------|-------------|------|-------------|
| 1 | Add statements field contract to cfg_state | Low | None |
| 2 | IfStatement populates cfg_state with body stmts | Low | Task 1 |
| 3 | ElsifChain populates cfg_state | Low | Task 2 |
| 4 | ForeachStatement populates cfg_state | Low | Task 1 |
| 5 | PostfixModifier populates cfg_state (partial) | Medium | Task 1 |
| 6 | Perl target emit_from_cfg_state | Medium | Tasks 2, 4 |
| 7 | XS target emit_from_cfg_state | Medium | Tasks 2, 4 |
| 8 | Wire _emit_node to try cfg_state first | **High** | Tasks 6, 7 |
| 9 | Full pipeline integration test | Medium | Task 8 |
| 10 | Remove IfStmt Constructor creation | **High** | Task 9 |
| 11 | Remove ForeachLoop/PostfixLoop Constructors | **High** | Task 9 |
| 12 | Remove legacy target dispatch | Medium | Tasks 10, 11 |
| 13 | Final verification | Low | All above |

Tasks 1-5 can run sequentially (each builds on the previous). Tasks 6-7 can run in parallel. Task 8 is the critical integration point. Tasks 10-12 are the cleanup phase.

## GCM Upgrade Path

When the time comes to add loop-invariant code motion or global value numbering:

1. Add `_idepth` / `idom()` cache to CFG nodes (~50 lines, from Simple Chapter 11)
2. Add a scheduling pass between optimization and codegen (~100 lines)
3. The scheduler recomputes statement assignments from graph edges, ignoring cfg_state
4. `emit_from_cfg_state` is replaced by `emit_from_schedule` — same signatures, different data source
5. No existing infrastructure needs removal
