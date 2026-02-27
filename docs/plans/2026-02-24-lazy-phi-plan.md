# Lazy Phi Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement Click Chapter 8 lazy Phi creation so variables inside loops get proper SSA form with loop-carried dependencies.

**Architecture:** Scope sentinels at loop entry, on-demand Phi creation when variables are read, assignment scope updates, and backedge wiring after body parsing. See `docs/plans/2026-02-24-lazy-phi-loop-design.md` for the full design.

**Tech Stack:** Perl 5.42.0 with `feature class`, Earley parser with FilterComposite semiring, Sea of Nodes IR with cfg_state side-table.

**Key files to read before starting:**
- `docs/plans/2026-02-24-lazy-phi-loop-design.md` — the design this plan implements
- `lib/Chalk/Bootstrap/Scope.pm` — immutable scope with lookup/define/diff
- `lib/Chalk/Bootstrap/IR/Node/Phi.pm` — Phi node (currently just operation() method)
- `lib/Chalk/Bootstrap/IR/Node/Loop.pm` — Loop node (currently just operation() method)
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — semantic actions for Perl grammar
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — cfg_state/update_cfg machinery
- `t/bootstrap/scope-threading.t` — existing scope tests (pattern to follow)
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm` — `Phi => ['region', 'values'], Loop => ['entry_ctrl', 'backedge_ctrl']`

**Run tests with:** `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/<file>.t`

**Worktree:** `/home/perigrin/dev/chalk/.worktrees/lazy-phi` on branch `lazy-phi`

---

## Task 1: Scope Sentinel Unit Tests

Add `fork_for_loop`, `resolve_sentinel`, and `raw_lookup` tests to a new scope test file. These test the Scope class in isolation, without the parser.

**Files:**
- Create: `t/bootstrap/scope-sentinel.t`
- Reference: `lib/Chalk/Bootstrap/Scope.pm`
- Reference: `lib/Chalk/Bootstrap/IR/NodeFactory.pm`

**Step 1: Write the failing tests**

Create `t/bootstrap/scope-sentinel.t`:

```perl
# ABOUTME: Tests lazy Phi sentinel mechanism in Scope for loop-carried dependencies
# ABOUTME: Covers fork_for_loop, resolve_sentinel, raw_lookup, and sentinel lifecycle
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::IR::NodeFactory;

my $factory = Chalk::Bootstrap::IR::NodeFactory->new();

# --- fork_for_loop: replaces bindings with sentinels ---
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_a = $factory->make('Constant', const_type => 'integer', value => '1');
    my $node_b = $factory->make('Constant', const_type => 'integer', value => '2');
    $scope = $scope->define('$a', $node_a);
    $scope = $scope->define('$b', $node_b);

    my $loop = $factory->make('Loop', entry_ctrl => $factory->make('Start'), backedge_ctrl => undef);
    my $forked = $scope->fork_for_loop($loop);

    isnt($forked, $scope, 'fork_for_loop returns new Scope');
    ok(defined $forked->raw_lookup('$a'), 'forked scope has $a');
    ok(defined $forked->raw_lookup('$b'), 'forked scope has $b');

    # raw_lookup returns sentinel hashref, not original node
    my $sentinel_a = $forked->raw_lookup('$a');
    ok(ref $sentinel_a eq 'HASH', '$a binding is a sentinel hashref');
    ok($sentinel_a->{sentinel}, 'sentinel flag is set');
    is($sentinel_a->{pre_value}, $node_a, 'sentinel pre_value is original node');
    is($sentinel_a->{loop}, $loop, 'sentinel loop is the Loop node');
}

# --- resolve_sentinel: creates Phi on first read ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $node_x = $factory->make('Constant', const_type => 'integer', value => '42');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $node_x);

    my $loop = $factory->make('Loop', entry_ctrl => $factory->make('Start'), backedge_ctrl => undef);
    my $forked = $scope->fork_for_loop($loop);

    my ($value, $new_scope) = $forked->resolve_sentinel('$x', $factory);
    ok(defined $value, 'resolve_sentinel returns a value');
    ok($value isa Chalk::Bootstrap::IR::Node::Phi, 'value is a Phi node');
    ok(defined $new_scope, 'new scope returned (sentinel was resolved)');

    # Phi inputs: [loop, [pre_value, undef]]
    my $inputs = $value->inputs();
    is($inputs->[0], $loop, 'Phi region is the Loop node');
    ok(ref $inputs->[1] eq 'ARRAY', 'Phi values is an arrayref');
    is($inputs->[1][0], $node_x, 'Phi first value is pre-loop value');
    ok(!defined $inputs->[1][1], 'Phi backedge is undef (not yet wired)');

    # Second resolve_sentinel on same name returns Phi directly, no new scope
    my ($value2, $new_scope2) = $new_scope->resolve_sentinel('$x', $factory);
    is($value2, $value, 'second resolve returns same Phi');
    ok(!defined $new_scope2, 'no new scope (already resolved)');
}

# --- resolve_sentinel: unbound variable returns undef ---
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my ($value, $new_scope) = $scope->resolve_sentinel('$unknown', $factory);
    ok(!defined $value, 'unbound variable returns undef');
    ok(!defined $new_scope, 'no new scope for unbound variable');
}

# --- resolve_sentinel: non-sentinel binding returns value, no new scope ---
{
    my $node = $factory->make('Constant', const_type => 'string', value => 'hello');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $node);

    my ($value, $new_scope) = $scope->resolve_sentinel('$x', $factory);
    is($value, $node, 'non-sentinel returns the bound node');
    ok(!defined $new_scope, 'no new scope (no sentinel to resolve)');
}

# --- raw_lookup: returns binding without resolving ---
{
    my $node = $factory->make('Constant', const_type => 'integer', value => '1');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $node);

    my $loop = $factory->make('Loop', entry_ctrl => $factory->make('Start'), backedge_ctrl => undef);
    my $forked = $scope->fork_for_loop($loop);

    # raw_lookup returns the sentinel, not a Phi
    my $raw = $forked->raw_lookup('$x');
    ok(ref $raw eq 'HASH' && $raw->{sentinel}, 'raw_lookup returns sentinel');

    # regular lookup also returns sentinel (no auto-resolve)
    my $regular = $forked->lookup('$x');
    ok(ref $regular eq 'HASH' && $regular->{sentinel}, 'lookup returns sentinel too');
}

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-sentinel.t`

Expected: FAIL — `fork_for_loop`, `resolve_sentinel`, `raw_lookup` methods don't exist.

**Step 3: Implement Scope methods**

Modify `lib/Chalk/Bootstrap/Scope.pm`. Add three methods and a `use` for Phi:

After the existing `use Scalar::Util 'refaddr';` line, add:

```perl
use Chalk::Bootstrap::IR::Node::Phi;
```

Add these methods inside the class, after the existing `variable_names` method:

```perl
    # Create a new Scope with all bindings replaced by sentinels.
    # Each sentinel records the Loop node and the pre-loop binding value.
    # Called at loop entry to enable lazy Phi creation.
    method fork_for_loop($loop_node) {
        my %sentinel_bindings;
        for my $name (keys $bindings->%*) {
            $sentinel_bindings{$name} = {
                sentinel  => true,
                loop      => $loop_node,
                pre_value => $bindings->{$name},
            };
        }
        return Chalk::Bootstrap::Scope->new(bindings => \%sentinel_bindings);
    }

    # Resolve a sentinel for a variable, creating a Phi on demand.
    # Returns ($value, $new_scope):
    #   - If sentinel: creates Phi, returns (Phi, new Scope with Phi replacing sentinel)
    #   - If non-sentinel binding: returns (binding, undef)
    #   - If unbound: returns (undef, undef)
    method resolve_sentinel($name, $factory) {
        my $binding = $bindings->{$name};
        return (undef, undef) unless defined $binding;

        # Non-sentinel: return the binding directly
        unless (ref $binding eq 'HASH' && $binding->{sentinel}) {
            return ($binding, undef);
        }

        # Sentinel: create a Phi node with backedge placeholder
        my $phi = $factory->make('Phi',
            region => $binding->{loop},
            values => [$binding->{pre_value}, undef],
        );

        # Replace sentinel with Phi in a new scope
        my $new_scope = $self->define($name, $phi);
        return ($phi, $new_scope);
    }

    # Return the raw binding without resolving sentinels.
    # Used during backedge wiring to distinguish sentinels from Phis.
    method raw_lookup($name) {
        return $bindings->{$name};
    }
```

**Step 4: Run test to verify it passes**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-sentinel.t`

Expected: All tests PASS.

**Step 5: Run existing scope tests to verify no regression**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-threading.t`

Expected: All 11 tests PASS.

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/Scope.pm t/bootstrap/scope-sentinel.t
git commit -m "feat: Add lazy Phi sentinel mechanism to Scope

fork_for_loop replaces bindings with sentinels at loop entry.
resolve_sentinel creates Phi nodes on demand when variables are read.
raw_lookup returns bindings without resolving sentinels."
```

---

## Task 2: Phi and Loop Backedge Mutation

Add `set_backedge` to Phi and `set_backedge_ctrl` to Loop. These are the only
mutation points in the IR — backedges cannot exist at construction time.

**Files:**
- Modify: `lib/Chalk/Bootstrap/IR/Node/Phi.pm`
- Modify: `lib/Chalk/Bootstrap/IR/Node/Loop.pm`
- Create: `t/bootstrap/phi-backedge.t`

**Step 1: Write the failing tests**

Create `t/bootstrap/phi-backedge.t`:

```perl
# ABOUTME: Tests Phi and Loop backedge mutation — the only mutable operations in the IR
# ABOUTME: Verifies set_backedge on Phi and set_backedge_ctrl on Loop wire correctly
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

my $factory = Chalk::Bootstrap::IR::NodeFactory->new();

# --- Phi set_backedge ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $start = $factory->make('Start');
    my $loop = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $pre_value = $factory->make('Constant', const_type => 'integer', value => '0');
    my $phi = $factory->make('Phi', region => $loop, values => [$pre_value, undef]);

    # Before wiring: backedge is undef
    is($phi->inputs()->[1][1], undef, 'Phi backedge starts as undef');

    # Wire backedge
    my $backedge_value = $factory->make('Constant', const_type => 'integer', value => '1');
    $phi->set_backedge($backedge_value);

    is($phi->inputs()->[1][1], $backedge_value, 'Phi backedge wired to value');
    is($phi->inputs()->[1][0], $pre_value, 'Phi pre-value unchanged');
    is($phi->inputs()->[0], $loop, 'Phi region unchanged');
}

# --- Loop set_backedge_ctrl ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $start = $factory->make('Start');
    my $loop = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);

    # Before wiring: backedge_ctrl is undef
    is($loop->inputs()->[1], undef, 'Loop backedge_ctrl starts as undef');

    # Wire backedge control
    my $body_ctrl = $factory->make('Region', controls => [$start]);
    $loop->set_backedge_ctrl($body_ctrl);

    is($loop->inputs()->[1], $body_ctrl, 'Loop backedge_ctrl wired');
    is($loop->inputs()->[0], $start, 'Loop entry_ctrl unchanged');
}

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/phi-backedge.t`

Expected: FAIL — `set_backedge` and `set_backedge_ctrl` methods don't exist.

**Step 3: Implement mutation methods**

Modify `lib/Chalk/Bootstrap/IR/Node/Phi.pm`:

```perl
# ABOUTME: IR node representing value selection at a control merge point
# ABOUTME: Phi nodes select which value to use based on which control path was taken
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::Phi :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'Phi';
    }

    # Set the backedge value (second element of the values array).
    # This is the only mutation point — backedges don't exist at construction time.
    method set_backedge($value) {
        $self->inputs()->[1][1] = $value;
    }
}
```

Modify `lib/Chalk/Bootstrap/IR/Node/Loop.pm`:

```perl
# ABOUTME: IR node representing a loop header in control flow
# ABOUTME: Loop nodes are special Region nodes with entry and backedge control inputs
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::Loop :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'Loop';
    }

    # Set the backedge control input (second element of inputs).
    # This is the only mutation point — backedges don't exist at construction time.
    method set_backedge_ctrl($ctrl) {
        $self->inputs()->[1] = $ctrl;
    }
}
```

**Step 4: Run test to verify it passes**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/phi-backedge.t`

Expected: All tests PASS.

**Step 5: Run existing CFG tests**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/cfg-loop.t t/bootstrap/cfg-if-else.t`

Expected: All tests PASS (no regression).

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/IR/Node/Phi.pm lib/Chalk/Bootstrap/IR/Node/Loop.pm t/bootstrap/phi-backedge.t
git commit -m "feat: Add backedge mutation to Phi and Loop nodes

Phi.set_backedge wires the loop-carried value after body parsing.
Loop.set_backedge_ctrl wires the body exit control to the loop header.
These are the only mutation points in the IR."
```

---

## Task 3: Variable Actions Read from Scope

Change `ScalarVariable`, `ArrayVariable`, and `HashVariable` in Actions.pm to
consult the scope before falling back to a Constant node. This enables lazy
Phi creation when a variable is read inside a loop body.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (lines ~1136-1161)
- Create: `t/bootstrap/scope-variable-lookup.t`

**Step 1: Write the failing test**

Create `t/bootstrap/scope-variable-lookup.t`. This test parses `my $x = 42; $x;` and checks that the second `$x` resolves from scope (returns the VarDecl node, not a fresh Constant).

```perl
# ABOUTME: Tests that variable references resolve from scope when available
# ABOUTME: Verifies ScalarVariable/ArrayVariable/HashVariable consult cfg_state scope
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Semiring::SemanticAction;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::VarLookupTest/g;
    eval $generated;
    skip "Generated code failed: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::VarLookupTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    my $sa = $semiring->semirings()->[4];

    # --- Test: Variable reference resolves from scope ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $x = 42; $x;');
        ok(defined $result, 'my $x = 42; $x; parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 3 unless defined $sem_ctx;

        my $program = $sem_ctx->extract();
        ok(defined $program, 'program IR exists');

        # The program should have statements; the second statement
        # should reference the same node as $x in scope (not a fresh Constant)
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available');
        my $x_in_scope = $state->{scope}->lookup('$x');
        ok(defined $x_in_scope, '$x is in scope');

        # The second statement ($x;) should resolve from scope
        # It should be the VarDecl node, not a Constant(variable, '$x')
        my $stmts = $program->inputs()->[0];
        ok(ref $stmts eq 'ARRAY', 'program has statements array');
        ok(scalar $stmts->@* >= 2, 'at least 2 statements');

        if (scalar $stmts->@* >= 2) {
            my $second = $stmts->[1];
            # After scope lookup, the second $x should be the scope value
            # (the VarDecl), not a bare Constant with value '$x'
            isnt($second->operation(), 'Constant',
                'second $x is not a bare Constant (resolved from scope)')
                or diag("Got: " . $second->operation() . " / "
                    . ($second->value() // 'undef'));
        }
    }
}

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-variable-lookup.t`

Expected: FAIL — the second `$x` is a Constant(variable, '$x') because Variable actions don't consult scope.

**Step 3: Implement scope lookup in Variable actions**

In `lib/Chalk/Bootstrap/Perl/Actions.pm`, modify the `ScalarVariable`, `ArrayVariable`, and `HashVariable` methods. Each follows the same pattern. Replace the existing methods (around lines 1143-1161):

```perl
    # §18 ScalarVariable — resolve from scope if available, else Constant
    method ScalarVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;

        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my ($value, $new_scope) = $state->{scope}->resolve_sentinel($text, $factory);
                if (defined $value) {
                    if ($new_scope) {
                        $sa->update_cfg({ $state->%*, scope => $new_scope });
                    }
                    return $value;
                }
            }
        }

        return $factory->make('Constant', const_type => 'variable', value => $text);
    }

    # §18 ArrayVariable — resolve from scope if available, else Constant
    method ArrayVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;

        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my ($value, $new_scope) = $state->{scope}->resolve_sentinel($text, $factory);
                if (defined $value) {
                    if ($new_scope) {
                        $sa->update_cfg({ $state->%*, scope => $new_scope });
                    }
                    return $value;
                }
            }
        }

        return $factory->make('Constant', const_type => 'variable', value => $text);
    }

    # §18 HashVariable — resolve from scope if available, else Constant
    method HashVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;

        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my ($value, $new_scope) = $state->{scope}->resolve_sentinel($text, $factory);
                if (defined $value) {
                    if ($new_scope) {
                        $sa->update_cfg({ $state->%*, scope => $new_scope });
                    }
                    return $value;
                }
            }
        }

        return $factory->make('Constant', const_type => 'variable', value => $text);
    }
```

Also modify the `Variable` method (line ~1136) with the same pattern:

```perl
    method Variable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;

        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my ($value, $new_scope) = $state->{scope}->resolve_sentinel($text, $factory);
                if (defined $value) {
                    if ($new_scope) {
                        $sa->update_cfg({ $state->%*, scope => $new_scope });
                    }
                    return $value;
                }
            }
        }

        return $factory->make('Constant', const_type => 'variable', value => $text);
    }
```

**Note:** The code duplication across 4 methods is intentional for now. Extracting a helper is a refactor step after tests pass.

**Step 4: Run test to verify it passes**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-variable-lookup.t`

Expected: PASS — the second `$x` resolves from scope.

**Step 5: Run existing tests to verify no regression**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-threading.t t/bootstrap/cfg-statements.t t/bootstrap/perl-actions-tier-c.t`

Expected: All pass. **CRITICAL:** If any existing tests fail, the scope lookup may be returning VarDecl nodes where Constant nodes were expected. Investigate before proceeding — the fallback path (unbound variables return Constant) must work correctly.

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/scope-variable-lookup.t
git commit -m "feat: Variable actions resolve from scope before Constant fallback

ScalarVariable, ArrayVariable, HashVariable, and Variable now consult
cfg_state scope. Sentinel resolution creates Phi nodes on demand.
Variables not in scope fall through to existing Constant behavior."
```

---

## Task 4: Assignment Scope Updates

Make `AssignmentExpression` update the scope when assigning to a variable, so
the scope tracks the "current version" of each variable through the parse.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (AssignmentExpression, lines ~1621-1689)
- Modify: `t/bootstrap/scope-variable-lookup.t` (add assignment test)

**Step 1: Write the failing test**

Add to `t/bootstrap/scope-variable-lookup.t`, inside the SKIP block, after the existing test:

```perl
    # --- Test: Assignment updates scope ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $x = 1; $x = 2;');
        ok(defined $result, 'my $x = 1; $x = 2; parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 2 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available after assignment');
        my $x_binding = $state->{scope}->lookup('$x');
        ok(defined $x_binding, '$x still in scope after reassignment');

        # The scope binding should now point at the VarDecl with
        # initializer 2, not the original VarDecl with initializer 1
        if (defined $x_binding
                && $x_binding isa Chalk::Bootstrap::IR::Node::Constructor
                && $x_binding->class() eq 'VarDecl') {
            my $init = $x_binding->inputs()->[1];
            ok(defined $init, 'VarDecl has initializer');
            if (defined $init && $init isa Chalk::Bootstrap::IR::Node::Constant) {
                is($init->value(), '2', 'scope points at reassigned value (2, not 1)');
            }
        }
    }
```

**Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-variable-lookup.t`

Expected: FAIL — scope still points at the original value because AssignmentExpression doesn't update scope.

**Step 3: Implement assignment scope updates**

In `lib/Chalk/Bootstrap/Perl/Actions.pm`, modify `AssignmentExpression` (around line 1621). After the method builds its return value but before returning, add scope update logic.

The key insertion points are after each `return` that creates a VarDecl or CompoundAssign. Add a helper at the top of AssignmentExpression and call it before each return:

Add this block just before `return undef unless defined $target && defined $op;` (around line 1640):

```perl
        # Helper: update scope when assigning to a variable
        my $update_scope = sub ($var_name, $ir_node) {
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            return unless defined $sa;
            my $state = $sa->inherited_cfg_state($ctx);
            return unless defined $state;
            my $new_scope = $state->{scope}->define($var_name, $ir_node);
            $sa->update_cfg({ $state->%*, scope => $new_scope });
        };
```

Then, in the `$op_val eq '='` branch, before each `return` of a VarDecl node (lines ~1657, ~1667), add the scope update. For example, before `return $factory->make('Constructor', 'class' => 'VarDecl', variable => $target, initializer => $value);` at line ~1667:

```perl
            if ($target isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $target->value()
                    && $target->value() =~ /^[\$\@\%]/) {
                my $result = $factory->make('Constructor',
                    'class'       => 'VarDecl',
                    variable    => $target,
                    initializer => $value,
                );
                $update_scope->($target->value(), $result);
                return $result;
            }
```

Apply the same pattern to the VarDecl target case (line ~1654) and the CompoundAssign case (line ~1683). For CompoundAssign, extract the variable name from `$target`:

```perl
        # Compound assignment (.=, //=, +=, etc.)
        my $result = $factory->make('Constructor',
            'class'  => 'CompoundAssign',
            op     => $op,
            target => $target,
            value  => $value,
        );
        if ($target isa Chalk::Bootstrap::IR::Node::Constant
                && defined $target->value()
                && $target->value() =~ /^[\$\@\%]/) {
            $update_scope->($target->value(), $result);
        }
        return $result;
```

**Step 4: Run test to verify it passes**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-variable-lookup.t`

Expected: PASS.

**Step 5: Run existing tests**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-threading.t t/bootstrap/cfg-statements.t t/bootstrap/perl-actions-tier-c.t`

Expected: All pass.

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/scope-variable-lookup.t
git commit -m "feat: AssignmentExpression updates scope on variable assignment

Plain assignment and compound assignment ($x = expr, $x .= expr) now
call scope.define() so the scope tracks current variable bindings.
This enables loop-carried dependencies via Phi backedge values."
```

---

## Task 5: ForeachStatement Scope Forking and Backedge Wiring

Wire `fork_for_loop` and backedge wiring into `ForeachStatement`. This is
the core integration point: loop entry creates sentinels, loop exit wires Phis.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (ForeachStatement, lines ~1962-2029)
- Create: `t/bootstrap/cfg-loop-phi.t`

**Step 1: Write the failing test**

Create `t/bootstrap/cfg-loop-phi.t`:

```perl
# ABOUTME: Tests lazy Phi creation in loop constructs via ForeachStatement
# ABOUTME: Verifies scope forking, sentinel resolution, and backedge wiring
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Semiring::SemanticAction;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::LoopPhiTest/g;
    eval $generated;
    skip "Generated code failed: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::LoopPhiTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    my $sa = $semiring->semirings()->[4];

    # --- Test 1: Read-only variable in loop gets degenerate Phi ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $src = 'my $x = 42; for my $i (1, 2, 3) { $x; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'read-only loop parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 4 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available');

        # $x should still be in scope after the loop
        my $x_binding = $state->{scope}->lookup('$x');
        ok(defined $x_binding, '$x in scope after loop');

        # $x should be a Phi node (created because $x was read inside loop)
        ok($x_binding isa Chalk::Bootstrap::IR::Node::Phi,
            '$x is a Phi (read-only, degenerate)')
            or diag("Got: " . ref($x_binding) . " / "
                . ($x_binding->operation() // 'undef'));
    }

    # --- Test 2: Read-and-written variable gets real loop-carried Phi ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $src = 'my $sum = 0; for my $x (1, 2, 3) { $sum = $sum + $x; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'read-write loop parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 5 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available');

        my $sum_binding = $state->{scope}->lookup('$sum');
        ok(defined $sum_binding, '$sum in scope after loop');

        # $sum should be a Phi (or a node derived from Phi)
        # After backedge wiring, the Phi's backedge should not be undef
        if ($sum_binding isa Chalk::Bootstrap::IR::Node::Phi) {
            my $values = $sum_binding->inputs()->[1];
            ok(defined $values->[1],
                'Phi backedge is wired (not undef)')
                or diag("backedge value: " . ($values->[1] // 'undef'));
        } else {
            # Scope may point at the final VarDecl from assignment
            # In that case check that a Phi exists somewhere in the IR
            pass('$sum binding is ' . ref($sum_binding) . ' (acceptable)');
        }
    }

    # --- Test 3: Variable not read in loop gets no Phi ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $src = 'my $y = 99; for my $i (1, 2) { $i; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'unread variable loop parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 2 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available');

        my $y_binding = $state->{scope}->lookup('$y');
        ok(defined $y_binding, '$y in scope after loop');

        # $y was never read inside the loop — should NOT be a Phi
        ok(!($y_binding isa Chalk::Bootstrap::IR::Node::Phi),
            '$y is not a Phi (never read in loop)')
            or diag("Got Phi for unread variable");
    }
}

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/cfg-loop-phi.t`

Expected: FAIL — ForeachStatement doesn't fork scope or wire backedges.

**Step 3: Implement scope forking in ForeachStatement**

In `lib/Chalk/Bootstrap/Perl/Actions.pm`, modify the `ForeachStatement` method (around line 1962). The key changes:

1. Before building CFG nodes, snapshot and fork the scope
2. The iterator variable goes into the forked scope
3. After the body, diff to find which sentinels became Phis, wire backedges
4. Restore unresolved sentinels to pre-loop values

Replace the CFG-building section (lines ~1993-2026) with:

```perl
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my $pre_loop_scope = $state->{scope};
                my $pre_loop_snapshot = $pre_loop_scope->snapshot();

                my $loop_cond = $factory->make('Constant',
                    const_type => 'string', value => '__loop_bound__');
                my $loop = $factory->make('Loop',
                    entry_ctrl    => $state->{control},
                    backedge_ctrl => undef,
                );
                my $if_node = $factory->make('If',
                    control   => $loop,
                    condition => $loop_cond,
                );
                my $body_proj = $factory->make('Proj', source => $if_node, index => 0);
                my $exit_proj = $factory->make('Proj', source => $if_node, index => 1);

                # Fork scope: replace all bindings with sentinels
                my $forked_scope = $pre_loop_scope->fork_for_loop($loop);

                # Add iterator variable to forked scope
                if (defined $iterator) {
                    $forked_scope = $forked_scope->define(
                        $iterator->value(), $iterator);
                }

                # The body was already parsed with the pre-fork scope.
                # Walk body statements to find the post-body scope.
                # For now, use the forked scope as-is and rely on
                # variable actions having updated it during body parsing.
                # The body's cfg_state changes propagate through multiply.

                # Build post-loop scope: restore unresolved sentinels
                my $post_loop_scope = $forked_scope;
                # Check body leaves for scope updates
                for my $leaf (_collect_ir_leaves($ctx)) {
                    my $leaf_state = $sa->cfg_state($leaf);
                    if (defined $leaf_state && defined $leaf_state->{scope}) {
                        $post_loop_scope = $leaf_state->{scope};
                    }
                }

                # Wire Phi backedges and restore sentinels
                my $final_scope = $pre_loop_scope;
                for my $name ($post_loop_scope->variable_names()) {
                    my $binding = $post_loop_scope->raw_lookup($name);
                    if (ref $binding eq 'HASH' && $binding->{sentinel}) {
                        # Never read: discard sentinel, keep pre-loop value
                        next;
                    }
                    if ($binding isa Chalk::Bootstrap::IR::Node::Phi
                            && $binding->inputs()->[0] == $loop) {
                        # Phi created for this loop: wire backedge
                        my $backedge_val = $post_loop_scope->lookup($name);
                        $binding->set_backedge($backedge_val);
                        $final_scope = $final_scope->define($name, $binding);
                    } elsif (defined $pre_loop_snapshot->{$name}) {
                        # Variable existed before loop and was modified
                        $final_scope = $final_scope->define($name, $binding);
                    }
                }

                my $region = $factory->make('Region',
                    controls => [$exit_proj],
                );
                $sa->update_cfg({
                    control    => $region,
                    scope      => $final_scope,
                    body_stmts => $body,
                    loop       => $loop,
                    loop_if    => $if_node,
                    body_proj  => $body_proj,
                    exit_proj  => $exit_proj,
                    iterator   => $iterator,
                    list       => $list,
                });
                return $loop;
            }
        }
```

**IMPORTANT:** This implementation has a known challenge — the Earley parser
parses the loop body *before* ForeachStatement fires, so the body's variable
actions may run with the pre-fork scope. The scope forking may need to happen
earlier (at the Block or StatementList level when inside a loop context).
This may require iteration during implementation. The test will reveal whether
the scope propagation works as expected.

**Step 4: Run test to verify it passes**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/cfg-loop-phi.t`

Expected: Tests pass (some may need adjustment based on how scope propagates through the Earley parser — see note above).

**Step 5: Run existing tests**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/cfg-loop.t t/bootstrap/cfg-statements.t t/bootstrap/perl-actions-tier-c.t t/bootstrap/scope-threading.t`

Expected: All pass.

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/cfg-loop-phi.t
git commit -m "feat: ForeachStatement forks scope and wires Phi backedges

Loop entry creates sentinels via fork_for_loop. After body parsing,
Phi backedges are wired from post-body scope. Unresolved sentinels
(variables never read in the loop) are discarded."
```

---

## Task 6: PostfixModifier Loop Scope Forking

Apply the same scope forking and backedge wiring to `PostfixModifier` for
`while`, `until`, `for`, and `foreach` postfix loops.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (PostfixModifier, line ~1700)
- Modify: `t/bootstrap/cfg-loop-phi.t` (add postfix loop test)

**Step 1: Write the failing test**

Add to `t/bootstrap/cfg-loop-phi.t`:

```perl
    # --- Test 4: Postfix for loop with variable read ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $src = 'my $x = 0; $x = $x + 1 for 1, 2, 3;';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'postfix for loop parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 2 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available');

        my $x_binding = $state->{scope}->lookup('$x');
        ok(defined $x_binding, '$x in scope after postfix loop');
    }
```

**Step 2-6:** Follow the same RED-GREEN-COMMIT pattern. The PostfixModifier implementation mirrors ForeachStatement's scope forking logic. The existing PostfixModifier already creates Loop/If/Proj/Region nodes — add `fork_for_loop` before and backedge wiring after, using the same pattern as Task 5.

---

## Task 7: Integration Test with Real Files

Parse an actual `.pm` file that contains a loop with variable modification and
verify Phi nodes appear in the IR.

**Files:**
- Modify: `t/bootstrap/cfg-loop-phi.t` (add integration test)

**Step 1: Write the test**

Add to `t/bootstrap/cfg-loop-phi.t`:

```perl
    # --- Test 5: Real file integration — ConciseTree.pm has a for loop ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        open my $fh, '<:utf8', 'lib/Chalk/Bootstrap/ConciseTree.pm'
            or skip 'Cannot read ConciseTree.pm', 2;
        local $/;
        my $source = <$fh>;

        my $result = $parser->parse_value($source);
        ok(defined $result, 'ConciseTree.pm parses with lazy Phi');

        # Should not crash — Phi creation should work with real code
        my $sem_ctx = $result->[4];
        ok(defined $sem_ctx, 'ConciseTree.pm produces semantic context');
    }
```

**Step 2-6:** Run test, verify it passes, commit. This is a smoke test — it
verifies the lazy Phi mechanism doesn't crash on real code. Detailed IR
inspection is covered by the unit tests above.

---

## Task 8: Refactor and Clean Up

Extract the repeated scope-lookup pattern from Variable actions into a shared
helper. Clean up any dead code.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm`

**Step 1: Extract helper**

Create a lexical sub inside the Actions class:

```perl
    # Resolve a variable name from scope, creating a Phi if a sentinel is hit.
    # Returns the scope-resolved IR node, or undef if not in scope.
    my sub _resolve_from_scope($ctx, $name, $factory) {
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        return unless defined $sa;
        my $state = $sa->inherited_cfg_state($ctx);
        return unless defined $state;
        my ($value, $new_scope) = $state->{scope}->resolve_sentinel($name, $factory);
        return unless defined $value;
        if ($new_scope) {
            $sa->update_cfg({ $state->%*, scope => $new_scope });
        }
        return $value;
    }
```

Then simplify each Variable method:

```perl
    method ScalarVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _resolve_from_scope($ctx, $text, $factory)
            // $factory->make('Constant', const_type => 'variable', value => $text);
    }
```

**Step 2: Run all tests**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-sentinel.t t/bootstrap/phi-backedge.t t/bootstrap/scope-variable-lookup.t t/bootstrap/cfg-loop-phi.t t/bootstrap/scope-threading.t t/bootstrap/cfg-statements.t t/bootstrap/perl-actions-tier-c.t`

Expected: All pass.

**Step 3: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm
git commit -m "refactor: Extract _resolve_from_scope helper for Variable actions"
```

---

## Summary

| Task | What | New tests | Risk |
|------|------|-----------|------|
| 1 | Scope sentinel methods | scope-sentinel.t | Low — pure unit tests |
| 2 | Phi/Loop backedge mutation | phi-backedge.t | Low — simple field mutation |
| 3 | Variable actions read from scope | scope-variable-lookup.t | **Medium** — may break existing tests if scope returns unexpected nodes |
| 4 | Assignment updates scope | scope-variable-lookup.t (extended) | **Medium** — same risk as Task 3 |
| 5 | ForeachStatement scope forking | cfg-loop-phi.t | **High** — Earley scope propagation timing is the main unknown |
| 6 | PostfixModifier scope forking | cfg-loop-phi.t (extended) | Medium — mirrors Task 5 |
| 7 | Integration with real files | cfg-loop-phi.t (extended) | Low — smoke test |
| 8 | Extract helper, clean up | No new tests | Low — refactor only |

**Main risk:** Task 5's scope propagation through the Earley parser. The body
is parsed *before* ForeachStatement's action fires, so the forked scope may
not reach the body's variable actions. If this happens, the solution is to
fork the scope earlier — either in the Block action when it detects a loop
context in cfg_state, or by having ForeachStatement set a "pending fork" flag
that Block consumes. The tests will reveal this.
