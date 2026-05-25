# SoN IR Phase 4a: SSA Scope

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the scope track all variable assignments (not just declarations), add eager Phi creation at if/else merge points, and remove the post-hoc Phi insertion from Program().

**Architecture:** Hybrid Phi strategy — eager Phis at if/else (Click-style, using branch scope diffs at IfStatement completion) and lazy Phis at loops (existing sentinel mechanism). Trivial Phi removal inline.

**Tech Stack:** Perl 5.42.0, `feature class`.

**Design doc:** `docs/plans/2026-04-04-phase4-structural-split.md` (Phase 4a section)

**Skills required:** `writing-perl-5.42.0`, `test-driven-development`

**Prerequisite:** Phase 1-3 complete (typed nodes, shim active)

---

## File Map

### Modified files
- `lib/Chalk/Bootstrap/Scope.pm` — add `merge_with_phis()`, `remove_trivial_phi()`
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — reassignment scope tracking, IfStatement scope merging, delete Program() Phi pass

### New files
- `t/bootstrap/scope-ssa.t` — tests for reassignment tracking and if/else Phis
- `t/bootstrap/scope-trivial-phi.t` — tests for trivial Phi removal

### Modified tests
- `t/bootstrap/scope.t` — may need updates for changed Scope API

---

## Task 1: Reassignment Scope Tracking

Add scope updates for plain variable assignments (`$x = expr`).

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm`
- Create: `t/bootstrap/scope-ssa.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/scope-ssa.t`:

```perl
# ABOUTME: Tests for SSA-style scope tracking of variable reassignments.
# ABOUTME: Verifies that plain assignments ($x = expr) update the scope.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Perl::Actions;
use Chalk::Bootstrap::Semiring::SemanticAction;

Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();

my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Helper to make Context leaves (same pattern as assignment-scope.t)
# This test exercises the AssignmentExpression action directly.
# The key behavior: after `$x = 42`, scope should map $x to the Assign node.

# Setup: simulate scope with $x already declared (from earlier my $x = 0)
my $var_node = $factory->make('Constant', const_type => 'variable', value => '$x');
my $init_node = $factory->make('Constant', const_type => 'integer', value => '0');
my $vardecl = $factory->make('Constructor',
    'class'       => 'VarDecl',
    variable    => $var_node,
    initializer => $init_node,
);

my $scope = Chalk::Bootstrap::Scope->new();
$scope = $scope->define('$x', $vardecl);

# Verify initial state
is($scope->lookup('$x'), $vardecl, 'initial: $x bound to VarDecl');

# After reassignment ($x = 42), scope should map $x to the Assign node
# We test this by checking that the AssignmentExpression action updates scope
# for plain assignments, not just VarDecl.

# For now, test the Scope API itself:
my $new_value = $factory->make('Constant', const_type => 'integer', value => '42');
my $reassigned_scope = $scope->define('$x', $new_value);
isnt($reassigned_scope->lookup('$x'), $vardecl,
    'reassigned: $x is no longer the VarDecl');
is($reassigned_scope->lookup('$x'), $new_value,
    'reassigned: $x is the new value');

# Original scope unchanged (immutable)
is($scope->lookup('$x'), $vardecl, 'original scope unchanged');

done_testing();
```

- [ ] **Step 2: Run test to verify it passes (Scope API already supports this)**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-ssa.t`
Expected: PASS — `Scope->define()` already overwrites bindings.

- [ ] **Step 3: Modify AssignmentExpression to update scope for plain assignments**

In `lib/Chalk/Bootstrap/Perl/Actions.pm`, at the plain assignment branch
(around line 2428-2435), add scope tracking:

```perl
# Plain variable assignment ($var = expr)
my $assign_result = $factory->make('Constructor',
    'class' => 'BinaryExpr',
    op    => $op,
    left  => $target,
    right => $value,
);
# Track reassignment in scope (SSA: new value per assignment)
if ($target isa Chalk::Bootstrap::IR::Node::Constant
        && defined $target->value()
        && $target->value() =~ /^[\$\@\%]/) {
    $update_scope->($target->value(), $assign_result);
}
return $assign_result;
```

- [ ] **Step 4: Add integration test for reassignment scope tracking**

Add to `t/bootstrap/scope-ssa.t` a test that exercises the full
AssignmentExpression action with a plain assignment and verifies
the scope is updated. Follow the pattern from `assignment-scope.t`:

```perl
# Integration test: exercise AssignmentExpression with plain $x = 42
# after $x was previously declared. Verify scope maps $x to Assign node.
```

Use the same `make_parent_ctx` / `make_leaf_ctx` helpers as
`assignment-scope.t`. Import them or duplicate the pattern.

- [ ] **Step 5: Run all tests to verify no regressions**

Run: `SHELL=/bin/bash /bin/bash -c '$HOME/.local/share/pvm/versions/5.42.0/bin/perl -MTAP::Harness -e "TAP::Harness->new({verbosity => 0, lib => [qw(lib)]})->runtests(glob q{t/bootstrap/ir-*.t}, glob q{t/bootstrap/scope*.t}, q{t/bootstrap/assignment-scope.t})"'`

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: plain assignments update scope (SSA reassignment tracking)"
```

---

## Task 2: Scope merge_with_phis() Method

Add a method to Scope that merges two branch scopes, creating Phis for
variables that differ.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Scope.pm`
- Create: `t/bootstrap/scope-phi-merge.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/scope-phi-merge.t`:

```perl
# ABOUTME: Tests for Scope::merge_with_phis() — creates Phis at merge points.
# ABOUTME: Verifies eager Phi creation for if/else branches with differing variables.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Scope;

Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Setup: pre-if scope has $x = Const(1)
my $const1 = $factory->make('Constant', const_type => 'integer', value => '1');
my $const2 = $factory->make('Constant', const_type => 'integer', value => '2');
my $const3 = $factory->make('Constant', const_type => 'integer', value => '3');

my $pre_scope = Chalk::Bootstrap::Scope->new();
$pre_scope = $pre_scope->define('$x', $const1);
$pre_scope = $pre_scope->define('$y', $const3);

# Then-branch: $x = 2 (changed), $y unchanged
my $then_scope = $pre_scope->define('$x', $const2);

# Else-branch: $x unchanged, $y unchanged
my $else_scope = $pre_scope;

# Merge: $x differs (Const(1) vs Const(2)), $y is same
my $region = $factory->make('Region', controls => []);
my $merged = $pre_scope->merge_with_phis(
    $then_scope, $else_scope, $region, $factory,
);

# $x should be a Phi node
my $x_val = $merged->lookup('$x');
ok(defined $x_val, '$x is defined after merge');
ok($x_val isa Chalk::Bootstrap::IR::Node::Phi, '$x is a Phi node');

# Phi operands: then-value and else-value
is($x_val->inputs()->[0], $const2, 'Phi operand 0 is then-value');
is($x_val->inputs()->[1], $const1, 'Phi operand 1 is else-value');

# $y should NOT be a Phi (same value in both branches)
my $y_val = $merged->lookup('$y');
is($y_val, $const3, '$y is unchanged (no Phi)');

# New variable declared only in then-branch
my $const4 = $factory->make('Constant', const_type => 'string', value => 'new');
my $then_scope2 = $then_scope->define('$z', $const4);
my $merged2 = $pre_scope->merge_with_phis(
    $then_scope2, $else_scope, $region, $factory,
);

# $z was only in then-branch — Phi with undef else-value
my $z_val = $merged2->lookup('$z');
ok(defined $z_val, '$z is defined after merge');
ok($z_val isa Chalk::Bootstrap::IR::Node::Phi, '$z is a Phi');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-phi-merge.t`
Expected: FAIL — `Can't locate object method "merge_with_phis"`

- [ ] **Step 3: Implement merge_with_phis()**

Add to `lib/Chalk/Bootstrap/Scope.pm`:

```perl
# Merge two branch scopes at a Region, creating Phis for differing variables.
# $self is the pre-branch scope.
# $then_scope and $else_scope are the post-branch scopes.
# $region is the merge-point Region node.
# $factory is the NodeFactory for creating Phi nodes.
# Returns a new Scope with Phi nodes for differing variables.
method merge_with_phis($then_scope, $else_scope, $region, $factory) {
    my %merged;

    # Collect all variable names from both branches
    my %all_names;
    $all_names{$_} = 1 for $then_scope->variable_names();
    $all_names{$_} = 1 for $else_scope->variable_names();

    for my $name (sort keys %all_names) {
        my $then_val = $then_scope->lookup($name);
        my $else_val = $else_scope->lookup($name);

        # Same value (or both undef) — no Phi needed
        if (defined $then_val && defined $else_val
                && refaddr($then_val) == refaddr($else_val)) {
            $merged{$name} = $then_val;
            next;
        }

        # Values differ — create Phi
        my @phi_inputs;
        push @phi_inputs, $then_val;  # may be undef
        push @phi_inputs, $else_val;  # may be undef

        my $phi = $factory->make('Phi',
            region => $region,
            values => \@phi_inputs,
        );

        # Try trivial removal
        $phi = _remove_trivial_phi($phi);

        $merged{$name} = $phi;
    }

    return Chalk::Bootstrap::Scope->new(bindings => \%merged);
}
```

Note: `_remove_trivial_phi` is added in Task 3. For now, just create the
Phi without trivial removal (the test doesn't require it yet).

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Run all scope tests**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: Scope::merge_with_phis() creates Phis at if/else merge points"
```

---

## Task 3: Trivial Phi Removal

Add `_remove_trivial_phi()` to Scope.pm. A Phi is trivial if all its
operands (ignoring self-references and undef) are the same value.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Scope.pm`
- Create: `t/bootstrap/scope-trivial-phi.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/scope-trivial-phi.t`:

```perl
# ABOUTME: Tests for trivial Phi removal in Scope.
# ABOUTME: Verifies that Phis with identical operands are replaced by the single value.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Scope;

Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

my $const1 = $factory->make('Constant', const_type => 'integer', value => '1');
my $const2 = $factory->make('Constant', const_type => 'integer', value => '2');
my $region = $factory->make('Region', controls => []);

# Trivial Phi: both operands are the same
my $pre = Chalk::Bootstrap::Scope->new()->define('$x', $const1);
my $then_s = $pre;  # unchanged
my $else_s = $pre;  # unchanged
my $merged = $pre->merge_with_phis($then_s, $else_s, $region, $factory);

my $x = $merged->lookup('$x');
is($x, $const1, 'trivial Phi removed: $x is Const(1), not a Phi');
ok(!($x isa Chalk::Bootstrap::IR::Node::Phi), '$x is not a Phi node');

# Non-trivial Phi: operands differ
my $then_diff = $pre->define('$x', $const2);
my $merged2 = $pre->merge_with_phis($then_diff, $pre, $region, $factory);

my $x2 = $merged2->lookup('$x');
ok($x2 isa Chalk::Bootstrap::IR::Node::Phi, 'non-trivial: $x is a Phi');
is($x2->inputs()->[0], $const2, 'Phi then-operand is Const(2)');
is($x2->inputs()->[1], $const1, 'Phi else-operand is Const(1)');

# Trivial Phi with undef: one branch has variable, other doesn't,
# but pre-scope had it with same value
# (This tests that Phi(same, undef) is NOT trivially removed
# because undef represents a genuinely missing value)
my $then_only = $pre->define('$z', $const1);
my $else_none = Chalk::Bootstrap::Scope->new();
my $merged3 = Chalk::Bootstrap::Scope->new()->merge_with_phis(
    $then_only, $else_none, $region, $factory,
);
my $z = $merged3->lookup('$z');
ok($z isa Chalk::Bootstrap::IR::Node::Phi,
    'Phi(Const(1), undef) is NOT trivially removed');

done_testing();
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Implement _remove_trivial_phi()**

Add to `lib/Chalk/Bootstrap/Scope.pm` as a package-level function:

```perl
# Remove a trivial Phi (all operands identical, ignoring self-references).
# Returns the single common value if trivial, or the Phi if non-trivial.
sub _remove_trivial_phi($phi) {
    my $same;
    for my $operand ($phi->inputs()->@*) {
        # Skip self-references (loop backedges)
        next if defined $operand
            && ref($operand)
            && refaddr($operand) == refaddr($phi);
        # Skip undef (unfilled backedge) — but DON'T treat as trivial
        # undef means "value doesn't exist on this path"
        if (!defined $operand) {
            # If we have a value from another path and this path has undef,
            # that's non-trivial (variable exists on one path but not other)
            return $phi if defined $same;
            next;
        }
        if (!defined $same) {
            $same = $operand;
        } elsif (refaddr($same) != refaddr($operand)) {
            return $phi;  # non-trivial: two different values
        }
    }

    # All operands are the same (or Phi has no real operands)
    return $same // $phi;
}
```

Wire it into `merge_with_phis()` after Phi creation.

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Run all scope tests**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: trivial Phi removal in Scope::merge_with_phis()"
```

---

## Task 4: IfStatement Scope Merging

Wire `merge_with_phis()` into the IfStatement semantic action.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (IfStatement method)
- Create: `t/bootstrap/scope-if-merge.t`

- [ ] **Step 1: Write the failing test**

Create `t/bootstrap/scope-if-merge.t` — an integration test that
exercises the IfStatement action with branches that assign different
values to the same variable, then verifies the post-if scope has a Phi.

This is a higher-level test than the Scope unit tests. It needs to
set up a parse context with an IfStatement that has both branches.
Follow the patterns from `cfg-statements.t` or `assignment-scope.t`
for setting up semantic action contexts.

The test should verify:
1. Variable assigned in then-branch only → Phi at merge
2. Variable unchanged → no Phi
3. Variable assigned in both branches to same value → no Phi (trivial)
4. Variable assigned in both branches to different values → Phi

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Modify IfStatement action**

In `IfStatement` (around line 2640), after creating the Region, add
scope merging:

```perl
# Merge per-branch scopes with Phi creation
my $pre_scope = $state->{scope};
# Get then-branch final scope from cfg_state of then-body context
my $then_final_scope = ... ; # extract from child Context
# Get else-branch final scope (or pre_scope if no else)
my $else_final_scope = ... ; # extract or default to pre_scope
my $merged_scope = $pre_scope->merge_with_phis(
    $then_final_scope, $else_final_scope, $region, $factory,
);
```

The challenge is extracting per-branch final scopes. The then-body
and else-body are already parsed — their scope effects are in the
child Contexts that IfStatement received. Use `inherited_cfg_state`
on the relevant child contexts to get their final scopes.

This requires understanding how IfStatement's `$ctx` relates to the
branch bodies. Read the code carefully to determine which child
context carries which branch's scope.

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Run all tests including 16 green eval files**

This is a behavioral change — if/else branches now produce Phis.
Verify that codegen handles the Phis correctly (it should, since
codegen already handles Phis from loops).

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: IfStatement merges branch scopes with eager Phis"
```

---

## Task 5: Remove Post-Hoc Phi Pass from Program()

With if/else Phis handled by IfStatement and loop Phis handled by
sentinels, the post-hoc Phi insertion in Program() is dead code.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm`

- [ ] **Step 1: Identify the code to remove**

In `Program()` (around line 936-999), the Phi insertion block:
- Walks statements looking for Loop nodes
- Checks `$_loop_body_var_refs` for each loop
- Creates Phi nodes and wires backedges
- Updates scope

Also the `$_loop_body_var_refs` field declaration and all sites that
populate it (ForeachStatement, WhileLoop, PostfixModifier).

- [ ] **Step 2: Verify sentinel mechanism handles loop Phis**

Before removing, verify that the sentinel-based loop Phi creation
(via `fork_for_loop` / `resolve_sentinel`) is actually wired into the
loop actions. If it's only in tests (as we discovered earlier), the
loop actions need to be updated to use sentinels BEFORE removing
Program()'s Phi pass.

**If sentinels are not yet wired into production loop actions:**
This task becomes "wire sentinels into ForeachStatement/WhileLoop,
verify loop Phis work via sentinels, THEN remove Program() Phi pass."

- [ ] **Step 3: Remove the Phi pass (or wire sentinels first)**

- [ ] **Step 4: Run all tests**

Critical: the 16 green eval files must still produce correct output.
Loop-carrying variables must still get Phis (via sentinels now, not
via Program's post-hoc pass).

- [ ] **Step 5: Delete `$_loop_body_var_refs` and all population sites**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: remove Program() Phi pass — Phis now created during parsing"
```

---

## Task 6: Regression Check

- [ ] **Step 1: Run all IR tests**

- [ ] **Step 2: Run all scope tests**

- [ ] **Step 3: Run full bootstrap test suite**

Verify same failure counts as before Phase 4a.

- [ ] **Step 4: Commit any fixes needed**
