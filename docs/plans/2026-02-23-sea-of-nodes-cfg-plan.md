# Sea of Nodes CFG Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace tree-shaped IfStmt/ForeachLoop/PostfixLoop Constructors with proper If/Region/Phi/Loop/Proj CFG nodes, with scope-in-focus threading and scan-time Phi sentinels for loops.

**Architecture:** Enrich SemanticAction focus values to carry control token + lexical scope alongside IR nodes. Construct CFG nodes during semantic actions. Use scan-time loop keyword detection to create eager Phi sentinels. See `docs/plans/2026-02-23-sea-of-nodes-cfg-design.md` for full design rationale.

**Tech Stack:** Perl 5.42.0, `feature class`, Earley parser with FilterComposite semiring, comonad Context threading.

**Worktree:** `/home/perigrin/dev/chalk/.worktrees/sea-of-nodes-cfg` (branch: `sea-of-nodes-cfg`)

**Perl:** `$HOME/.local/share/pvm/versions/5.42.0/bin/perl`

**Test command:** `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/<file>.t`

**Skills required:** `writing-perl-5.42.0`, `test-driven-development`

---

## Task 1: Implement If Node Type

**Files:**
- Create: `lib/Chalk/Bootstrap/IR/Node/If.pm`
- Create: `t/bootstrap/ir-cfg-nodes.t`

**Step 1: Write failing test**

Create `t/bootstrap/ir-cfg-nodes.t` with tests for If node construction:

```perl
use 5.42.0;
use utf8;
use Test::More;

use Chalk::Bootstrap::IR::NodeFactory;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Create prerequisite nodes
my $start = $factory->make('Start');
my $cond  = $factory->make('Constant', type => 'integer', value => 1);

# Test If node creation
my $if_node = $factory->make('If', control => $start, condition => $cond);
ok(defined $if_node, 'If node created');
is($if_node->operation(), 'If', 'operation() returns If');
is($if_node->inputs()->[0], $start, 'first input is control');
is($if_node->inputs()->[1], $cond, 'second input is condition');

# Test hash consing — identical inputs produce same node
my $if_node2 = $factory->make('If', control => $start, condition => $cond);
is($if_node, $if_node2, 'hash consing: identical If nodes share reference');

# Test use-def chains
my @start_consumers = $start->consumers()->@*;
ok(scalar(grep { $_ == $if_node } @start_consumers), 'start has if_node as consumer');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/ir-cfg-nodes.t`
Expected: FAIL — "Unknown operation: If" from NodeFactory

**Step 3: Write If node class**

Create `lib/Chalk/Bootstrap/IR/Node/If.pm`:

```perl
# ABOUTME: Conditional branch node in the Sea of Nodes IR.
# ABOUTME: Takes control token and condition, produces tuple (true_ctrl, false_ctrl).
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::If :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'If';
    }
}
```

Add to `lib/Chalk/Bootstrap/IR/NodeFactory.pm`:
- Add `use Chalk::Bootstrap::IR::Node::If;` to the static imports (after line 13)
- Add `If => ['control', 'condition'],` to `%INPUT_SPECS` (after line 26)

**Step 4: Run test to verify it passes**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/ir-cfg-nodes.t`
Expected: PASS

**Step 5: Run existing tests to verify no regression**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/ir-hash-consing.t`
Expected: PASS (unchanged)

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/IR/Node/If.pm lib/Chalk/Bootstrap/IR/NodeFactory.pm t/bootstrap/ir-cfg-nodes.t
git commit -m "feat(ir): add If node type for conditional branching"
```

---

## Task 2: Implement Region, Phi, Loop, Proj Node Types

**Files:**
- Create: `lib/Chalk/Bootstrap/IR/Node/Region.pm`
- Create: `lib/Chalk/Bootstrap/IR/Node/Phi.pm`
- Create: `lib/Chalk/Bootstrap/IR/Node/Loop.pm`
- Create: `lib/Chalk/Bootstrap/IR/Node/Proj.pm`
- Modify: `lib/Chalk/Bootstrap/IR/NodeFactory.pm`
- Modify: `t/bootstrap/ir-cfg-nodes.t`

**Step 1: Add tests for all four node types to `t/bootstrap/ir-cfg-nodes.t`**

Append tests for:
- `Proj` node: inputs `[source]`, attribute `index`. Two Proj nodes from same If with index 0 and 1.
- `Region` node: inputs `[ctrl_1, ctrl_2]`. Merges two Proj outputs.
- `Phi` node: inputs `[region, value_1, value_2]`. Selects value at merge point.
- `Loop` node: inputs `[entry_ctrl, undef]` (backedge null initially). Special Region for loops.
- Hash consing for each type.
- Use-def chain verification for each.

```perl
# --- Proj node ---
my $true_proj = $factory->make('Proj', source => $if_node, index => 0);
ok(defined $true_proj, 'Proj node created (true branch)');
is($true_proj->operation(), 'Proj', 'operation() returns Proj');
is($true_proj->inputs()->[0], $if_node, 'Proj input is If node');

my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
ok(defined $false_proj, 'Proj node created (false branch)');
isnt($true_proj, $false_proj, 'different indices produce different nodes');

# --- Region node ---
my $region = $factory->make('Region', controls => [$true_proj, $false_proj]);
ok(defined $region, 'Region node created');
is($region->operation(), 'Region', 'operation() returns Region');

# --- Phi node ---
my $val_a = $factory->make('Constant', type => 'integer', value => 2);
my $val_b = $factory->make('Constant', type => 'integer', value => 3);
my $phi = $factory->make('Phi', region => $region, values => [$val_a, $val_b]);
ok(defined $phi, 'Phi node created');
is($phi->operation(), 'Phi', 'operation() returns Phi');
is($phi->inputs()->[0], $region, 'Phi first input is region');

# --- Loop node ---
my $loop = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
ok(defined $loop, 'Loop node created');
is($loop->operation(), 'Loop', 'operation() returns Loop');
```

**Step 2: Run test to verify new tests fail**

Expected: FAIL — "Unknown operation: Proj" etc.

**Step 3: Implement all four node classes**

Create each as a minimal class following the If.pm pattern. Each has `operation()` returning its name.

`Region.pm` and `Phi.pm` take array inputs (`controls`, `values`), so NodeFactory must handle these in INPUT_SPECS.

Add to NodeFactory:
- `use` statements for all four new classes
- INPUT_SPECS entries:
  - `Proj => ['source'],` (plus `index` as attribute)
  - `Region => ['controls'],`
  - `Phi => ['region', 'values'],`
  - `Loop => ['entry_ctrl', 'backedge_ctrl'],`

**Step 4: Run test to verify it passes**

Expected: All ir-cfg-nodes.t tests PASS

**Step 5: Run existing tests to verify no regression**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/ir-hash-consing.t`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/Chalk/Bootstrap/IR/Node/Region.pm lib/Chalk/Bootstrap/IR/Node/Phi.pm \
        lib/Chalk/Bootstrap/IR/Node/Loop.pm lib/Chalk/Bootstrap/IR/Node/Proj.pm \
        lib/Chalk/Bootstrap/IR/NodeFactory.pm t/bootstrap/ir-cfg-nodes.t
git commit -m "feat(ir): add Region, Phi, Loop, Proj CFG node types"
```

---

## Task 3: If/Region/Phi Subgraph Construction Test

**Files:**
- Create: `t/bootstrap/ir-cfg-patterns.t`

**Step 1: Write test that constructs a complete if/else CFG pattern**

This test verifies the node types compose into the expected graph shape for
`if ($cond) { $x = 2 } else { $x = 3 }`. No parsing — pure IR construction
via NodeFactory. Validates the pattern the parser will later produce.

```perl
use 5.42.0;
use utf8;
use Test::More;

use Chalk::Bootstrap::IR::NodeFactory;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Build: if ($cond) { $x = 2 } else { $x = 3 }
my $start   = $factory->make('Start');
my $cond    = $factory->make('Constant', type => 'integer', value => 1);
my $val_a   = $factory->make('Constant', type => 'integer', value => 2);
my $val_b   = $factory->make('Constant', type => 'integer', value => 3);

my $if_node   = $factory->make('If', control => $start, condition => $cond);
my $true_proj = $factory->make('Proj', source => $if_node, index => 0);
my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
my $region    = $factory->make('Region', controls => [$true_proj, $false_proj]);
my $phi       = $factory->make('Phi', region => $region, values => [$val_a, $val_b]);
my $return    = $factory->make('Return', value => $phi);

# Verify graph shape
is($if_node->inputs()->[0], $start, 'If controlled by Start');
is($if_node->inputs()->[1], $cond, 'If condition is cond');
is($true_proj->inputs()->[0], $if_node, 'TrueProj from If');
is($false_proj->inputs()->[0], $if_node, 'FalseProj from If');
is($phi->inputs()->[0], $region, 'Phi at Region merge');
is($return->inputs()->[0], $phi, 'Return uses Phi result');

# Verify use-def: If is consumer of Start and cond
ok(scalar(grep { $_ == $if_node } $start->consumers()->@*), 'Start -> If');
ok(scalar(grep { $_ == $if_node } $cond->consumers()->@*), 'cond -> If');

# Verify use-def: Phi is consumer of both values
ok(scalar(grep { $_ == $phi } $val_a->consumers()->@*), 'val_a -> Phi');
ok(scalar(grep { $_ == $phi } $val_b->consumers()->@*), 'val_b -> Phi');

done_testing();
```

**Step 2: Run test**

Expected: PASS (all node types exist from Tasks 1-2)

**Step 3: Add loop subgraph pattern test**

Append a test constructing the graph for `while ($x < 10) { $x = $x + 1 }`:

```perl
# Build: while ($x < 10) { $x = $x + 1 }
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
$factory = Chalk::Bootstrap::IR::NodeFactory->instance();

$start = $factory->make('Start');
my $init_x   = $factory->make('Constant', type => 'integer', value => 0);
my $limit    = $factory->make('Constant', type => 'integer', value => 10);
my $one      = $factory->make('Constant', type => 'integer', value => 1);

my $loop = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
my $phi_x = $factory->make('Phi', region => $loop, values => [$init_x, undef]);

# Condition: phi_x < 10
my $less = $factory->make('Constructor', class => 'BinaryExpr',
    op => $factory->make('Constant', type => 'string', value => '<'),
    left => $phi_x, right => $limit);

my $loop_if = $factory->make('If', control => $loop, condition => $less);
my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);

# Body: phi_x + 1
my $add = $factory->make('Constructor', class => 'BinaryExpr',
    op => $factory->make('Constant', type => 'string', value => '+'),
    left => $phi_x, right => $one);

# Verify graph shape
is($loop->inputs()->[0], $start, 'Loop entry from Start');
is($phi_x->inputs()->[0], $loop, 'Phi_x at Loop header');
is($phi_x->inputs()->[1]->[0], $init_x, 'Phi_x entry value is 0');
is($loop_if->inputs()->[0], $loop, 'If controlled by Loop');

my $exit_region = $factory->make('Region', controls => [$exit_proj]);
$return = $factory->make('Return', value => $phi_x);

ok(defined $exit_region, 'exit Region created');
ok(defined $return, 'Return uses phi_x');
```

**Step 4: Run test**

Expected: PASS

**Step 5: Commit**

```bash
git add t/bootstrap/ir-cfg-patterns.t
git commit -m "test: verify If/Region/Phi/Loop subgraph patterns"
```

---

## Task 4: Scope Data Structure

**Files:**
- Create: `lib/Chalk/Bootstrap/Scope.pm`
- Create: `t/bootstrap/scope.t`

**Step 1: Write failing test for Scope class**

The Scope tracks variable-name → IR-node bindings. It supports lookup, define
(adding a binding), and snapshot (for scope forking at if/else and loops).

```perl
use 5.42.0;
use utf8;
use Test::More;

use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::IR::NodeFactory;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

my $const_0 = $factory->make('Constant', type => 'integer', value => 0);
my $const_1 = $factory->make('Constant', type => 'integer', value => 1);

# Empty scope
my $scope = Chalk::Bootstrap::Scope->new();
is($scope->lookup('$x'), undef, 'lookup on empty scope returns undef');

# Define and lookup
my $scope2 = $scope->define('$x', $const_0);
is($scope2->lookup('$x'), $const_0, 'define then lookup returns node');
is($scope->lookup('$x'), undef, 'original scope unchanged (immutable)');

# Overwrite
my $scope3 = $scope2->define('$x', $const_1);
is($scope3->lookup('$x'), $const_1, 'overwrite returns new node');
is($scope2->lookup('$x'), $const_0, 'previous scope unchanged');

# Snapshot and diff
my $snap = $scope2->snapshot();
my $scope4 = $scope2->define('$x', $const_1)->define('$y', $const_0);
my %diff = $scope4->diff($snap);
ok(exists $diff{'$x'}, 'diff detects modified $x');
ok(exists $diff{'$y'}, 'diff detects new $y');
is(scalar keys %diff, 2, 'diff returns only changed variables');

# Variable names
my @vars = sort $scope4->variable_names();
is_deeply(\@vars, ['$x', '$y'], 'variable_names returns all bindings');

done_testing();
```

**Step 2: Run test to verify it fails**

Expected: FAIL — can't locate Chalk/Bootstrap/Scope.pm

**Step 3: Implement Scope**

Create `lib/Chalk/Bootstrap/Scope.pm`. Immutable — each mutation returns a new
Scope. Uses a hashref internally; `define()` clones and adds; `snapshot()`
returns the hashref (shallow copy); `diff($snapshot)` compares current vs
snapshot.

```perl
# ABOUTME: Immutable lexical scope mapping variable names to IR nodes.
# ABOUTME: Supports define, lookup, snapshot, and diff for scope forking.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Scope {
    field $bindings :param = {};

    method lookup($name) {
        return $bindings->{$name};
    }

    method define($name, $node) {
        my %new = $bindings->%*;
        $new{$name} = $node;
        return Chalk::Bootstrap::Scope->new(bindings => \%new);
    }

    method snapshot() {
        return { $bindings->%* };
    }

    method diff($snap) {
        my %changed;
        for my $name (keys $bindings->%*) {
            if (!exists $snap->{$name}) {
                $changed{$name} = $bindings->{$name};
            } elsif (!defined $snap->{$name} || !defined $bindings->{$name}) {
                $changed{$name} = $bindings->{$name}
                    if ($snap->{$name} // '') ne ($bindings->{$name} // '');
            } elsif (refaddr($snap->{$name}) != refaddr($bindings->{$name})) {
                $changed{$name} = $bindings->{$name};
            }
        }
        return %changed;
    }

    method variable_names() {
        return keys $bindings->%*;
    }
}
```

Note: `diff` uses `refaddr` for identity comparison — add `use Scalar::Util 'refaddr';` at the top of the file.

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Scope.pm t/bootstrap/scope.t
git commit -m "feat: add immutable Scope class for variable bindings"
```

---

## Task 5: Enrich SemanticAction Focus with Control and Scope

**Files:**
- Create: `t/bootstrap/semantic-action-scope.t`
- Modify: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`

This is the foundational change. The SemanticAction's `one()` method returns
a Context whose focus is `{ value => undef, control => Start, scope => Scope->new() }`.
The `on_scan` and `on_complete` methods must handle this richer focus.

**Step 1: Write failing test**

Test that SemanticAction's `one()` returns a Context with the enriched focus:

```perl
use 5.42.0;
use utf8;
use Test::More;

use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Scope;

my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
my $one = $sa->one();
ok(defined $one, 'one() returns a Context');

my $focus = $one->extract();
is(ref($focus), 'HASH', 'focus is a hashref');
ok(exists $focus->{value}, 'focus has value key');
ok(exists $focus->{control}, 'focus has control key');
ok(exists $focus->{scope}, 'focus has scope key');
is($focus->{value}, undef, 'initial value is undef');
ok($focus->{control}->operation() eq 'Start', 'initial control is Start');
ok($focus->{scope} isa Chalk::Bootstrap::Scope, 'initial scope is a Scope');

done_testing();
```

**Step 2: Run test to verify it fails**

Expected: FAIL — focus is not a hashref (currently undef)

**Step 3: Modify SemanticAction**

In `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`:

- Add `use Chalk::Bootstrap::Scope;` and `use Chalk::Bootstrap::IR::NodeFactory;`
- Change `one()` to return a Context with enriched focus:

```perl
method one() {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $start = $factory->make('Start');
    return Chalk::Bootstrap::Context->new(
        focus    => { value => undef, control => $start, scope => Chalk::Bootstrap::Scope->new() },
        children => [],
        position => 0,
        rule     => undef,
    );
}
```

**CRITICAL:** This will break existing code that expects `$focus` to be an IR
node or undef. The `on_scan`, `on_complete`, `multiply`, `add`, and `is_zero`
methods must be updated to handle the enriched focus. The Actions.pm methods
that call `$ctx->extract()` and expect an IR node must extract `$focus->{value}`
instead.

This is the highest-risk change. It touches the central data path. The
approach: update SemanticAction's methods first, then create a compatibility
shim so existing Actions.pm code works without modification during the
migration period.

**Compatibility approach:** In `on_complete`, after the action method runs
via `extend`, check if the result focus is a bare IR node (not a hashref).
If so, wrap it: `{ value => $result, control => $parent_control, scope => $parent_scope }`.
This lets existing action methods return bare IR nodes while new action methods
return the full triple.

**Step 4: Run test to verify it passes, then run full suite**

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/semantic-action-scope.t`
Expected: PASS

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/semiring-semantic-action.t`
Expected: PASS (compatibility shim catches bare-node returns)

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/concise-actions.t`
Expected: PASS (full pipeline with compatibility)

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Semiring/SemanticAction.pm t/bootstrap/semantic-action-scope.t
git commit -m "feat: enrich SemanticAction focus with control token and scope"
```

---

## Task 6: Scope Population — VarDecl and Variable References

**Files:**
- Create: `t/bootstrap/scope-threading.t`
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (VarDecl and ScalarVariable methods)

**Step 1: Write failing test**

Parse a simple snippet `my $x = 0; $x` and verify the scope carries `$x`
binding through. Test uses a small grammar that exercises VarDecl + variable
reference, inspecting the scope in the final parse result.

The test parses real Perl source via the full pipeline and inspects the
SemanticAction result's scope to verify `$x` is bound to a Constant(0) node.

**Step 2: Run test to verify it fails**

Expected: FAIL — scope is empty because Actions.pm doesn't populate it

**Step 3: Modify Actions.pm**

In the VarDecl action method:
- Extract the variable name and initializer from children
- Call `$scope->define($var_name, $init_node)` to add the binding
- Return focus with `{ value => $var_decl_constructor, control => ..., scope => $updated_scope }`

During migration, VarDecl still produces a VarDecl Constructor (for backward
compatibility with the XS target). The scope population is additive.

For ScalarVariable: look up the variable name in the scope. If found, the
lookup result is available for future use (but don't change the output yet —
still return the variable name as a Constant for backward compatibility).

**Step 4: Run tests**

Run scope-threading.t → PASS
Run concise-actions.t → PASS (no regression)

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/scope-threading.t
git commit -m "feat: populate scope from VarDecl, lookup in ScalarVariable"
```

---

## Task 7: If/Else CFG Construction in Actions.pm

**Files:**
- Create: `t/bootstrap/cfg-if-else.t`
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (IfStatement method)

**Step 1: Write failing test**

Parse `if ($x) { $y = 1 } else { $y = 2 }` with scope containing `$x`.
Verify the result contains If, Proj, Region, and Phi nodes instead of an
IfStmt Constructor. The test inspects the IR graph structure:
- If node with condition input
- Two Proj nodes
- Region merging both paths
- Phi for `$y` with values from both branches

**Step 2: Run test to verify it fails**

Expected: FAIL — IfStatement still produces IfStmt Constructor

**Step 3: Modify IfStatement action in Actions.pm**

Replace the IfStmt Constructor creation with If/Proj/Region/Phi construction:
1. Extract condition from children
2. Create If(control, condition)
3. Create TrueProj(If, 0) and FalseProj(If, 1)
4. Get then-scope and else-scope from children's focuses
5. Diff scopes against pre-if scope
6. Create Phi for each divergent variable
7. Create Region merging both exit controls
8. Return focus with merged scope containing Phi nodes

**CRITICAL:** During migration, also keep the IfStmt Constructor path behind
a flag or conditional, so existing tests that expect IfStmt still work until
the XS target is updated (Task 10). The recommended approach: produce the new
CFG nodes AND store them in the focus, but also produce the IfStmt Constructor
as the `value` field for backward compatibility.

**Step 4: Run tests**

Run cfg-if-else.t → PASS
Run concise-actions.t → PASS (backward compat via value field)

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/cfg-if-else.t
git commit -m "feat: IfStatement produces If/Region/Phi CFG nodes"
```

---

## Task 8: Scan-time Loop Sentinel Creation

**Files:**
- Create: `t/bootstrap/cfg-loop-sentinels.t`
- Modify: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` (on_scan method)

**Step 1: Write failing test**

Test that when `while` is scanned, the SemanticAction's output scope contains
Phi sentinels for all variables in scope. Use a controlled setup: create a
SemanticAction with a scope containing `$x → Constant(0)`, simulate scanning
`while`, verify the output scope has `$x → Phi(Loop, Constant(0), undef)`.

**Step 2: Run test to verify it fails**

Expected: FAIL — on_scan doesn't create sentinels

**Step 3: Modify SemanticAction.on_scan**

Detect loop keywords (`while`, `for`, `foreach`) in the matched text. When
detected:
1. Extract current scope from the item's value
2. Create a Loop node with entry_ctrl from current control, backedge undef
3. For each variable in scope, create Phi(Loop, current_value, undef)
4. Build new scope with variables pointing to Phi sentinels
5. Return Context with enriched focus including new scope and Loop as control

Store the pre-loop scope snapshot and sentinel mapping in the focus (e.g., as
`{ ..., loop_snapshot => $snap, loop_sentinels => \%sentinels }`) so
WhileStatement's on_complete can wire up backedges.

**Step 4: Run tests**

Run cfg-loop-sentinels.t → PASS
Run concise-actions.t → PASS (no regression — while parsing still works,
sentinels flow through but value field still returns old Constructors)

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Semiring/SemanticAction.pm t/bootstrap/cfg-loop-sentinels.t
git commit -m "feat: scan-time Phi sentinel creation for loop keywords"
```

---

## Task 9: Loop CFG Construction in Actions.pm

**Files:**
- Create: `t/bootstrap/cfg-loop.t`
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (WhileStatement, ForeachStatement methods)

**Step 1: Write failing test**

Parse `my $x = 0; while ($x < 10) { $x = $x + 1 }` via the full pipeline.
Verify the result contains:
- Loop node with entry and backedge controls
- Phi node for `$x` with entry value Constant(0) and backedge value = Add result
- If node with Less condition
- Proj nodes for body and exit
- Region for loop exit

**Step 2: Run test to verify it fails**

Expected: FAIL — WhileStatement still produces ForeachLoop/PostfixLoop Constructor

**Step 3: Modify WhileStatement action in Actions.pm**

1. Extract the Loop node and Phi sentinels from scan-time data in focus
2. Extract condition and body results from children
3. Create If(Loop_control, condition) → TrueProj, FalseProj
4. Diff body's output scope against pre-loop snapshot
5. For each modified variable, fill Phi sentinel's backedge input
6. Wire body exit control as Loop backedge
7. Create Region(FalseProj) as exit
8. Return focus with exit Region as control, cleaned scope

Apply same pattern for ForeachStatement (iterator is a new variable in scope,
list becomes loop bound).

**Step 4: Run tests**

Run cfg-loop.t → PASS
Run concise-actions.t → PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm t/bootstrap/cfg-loop.t
git commit -m "feat: WhileStatement/ForeachStatement produce Loop/Phi CFG nodes"
```

---

## Task 10: XS Target — Graph Scheduler for If/Else

**Files:**
- Create: `t/bootstrap/xs-cfg-if.t`
- Modify: `lib/Chalk/Bootstrap/Perl/Target/XS.pm`

**Step 1: Write failing test**

Test that the XS target emits correct C code for an If/Region/Phi subgraph.
Construct the IR manually (like Task 3) and feed to the XS target. Verify the
output contains `if (SvTRUE(...)) {` and variable declarations for Phi nodes.

**Step 2: Run test to verify it fails**

Expected: FAIL — XS target doesn't recognize If/Region/Phi nodes

**Step 3: Add If/Region/Phi handling to XS target**

Add a pattern matcher that recognizes If → Proj → Region → Phi subgraphs and
emits structured `if/else` C code. Phi nodes become C variable declarations
before the if, with assignments in each branch.

This replaces `_emit_xs_if_stmt` for the new node types. Keep the old method
for backward compatibility until all callers are migrated.

**Step 4: Run tests**

Run xs-cfg-if.t → PASS
Run full XS target tests → PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/XS.pm t/bootstrap/xs-cfg-if.t
git commit -m "feat(xs): emit structured if/else from If/Region/Phi subgraph"
```

---

## Task 11: XS Target — Graph Scheduler for Loops

**Files:**
- Create: `t/bootstrap/xs-cfg-loop.t`
- Modify: `lib/Chalk/Bootstrap/Perl/Target/XS.pm`

**Step 1: Write failing test**

Construct a Loop/Phi/If subgraph manually, feed to XS target, verify the output
contains a `while`/`for` loop in C with Phi variables as loop variables.

**Step 2: Implement Loop pattern matching in XS target**

Recognize Loop → Phi → If → Proj subgraphs. Emit as `while` or `for` loop.
Phi nodes at loop header become loop variable declarations.

**Step 3: Run tests**

Run xs-cfg-loop.t → PASS
Run full test suite → PASS

**Step 4: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/XS.pm t/bootstrap/xs-cfg-loop.t
git commit -m "feat(xs): emit structured loops from Loop/Phi/If subgraph"
```

---

## Task 12: Perl Target — If/Else and Loop CFG Support

**Files:**
- Create: `t/bootstrap/perl-target-cfg.t`
- Modify: `lib/Chalk/Bootstrap/Perl/Target/Perl.pm`

Same pattern as Tasks 10-11 but for the Perl target. Perl has native `if/else`
and `while` so the reconstruction is simpler — emit Perl control structures
directly from the CFG pattern.

**Step 1-4: Follow same TDD pattern as Tasks 10-11**

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/Perl.pm t/bootstrap/perl-target-cfg.t
git commit -m "feat(perl-target): emit if/else and loops from CFG nodes"
```

---

## Task 13: Full Pipeline Integration — Remove Backward Compatibility

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (remove IfStmt/ForeachLoop Constructor creation)
- Modify: `lib/Chalk/Bootstrap/Perl/Target/XS.pm` (remove old tree-walk methods)
- Modify: `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` (remove old tree-walk methods)
- Modify: `lib/Chalk/Bootstrap/IR/NodeFactory.pm` (remove dead INPUT_SPECS entries)

**Step 1: Remove IfStmt/ForeachLoop/PostfixLoop Constructor creation from Actions.pm**

Actions.pm should now produce only CFG nodes for control flow. Remove the
backward-compatibility dual-output from Tasks 7 and 9.

**Step 2: Remove tree-walk methods from XS target**

Delete: `_emit_xs_if_stmt`, `_emit_xs_foreach_loop`, `_emit_xs_postfix_loop`,
`_collect_var_decls`, `_has_early_return`, `_body_contains_return`.

**Step 3: Remove dead NodeFactory entries**

Remove INPUT_SPECS for: `Constructor:IfStmt`, `Constructor:ForeachLoop`,
`Constructor:PostfixLoop`, `Constructor:VarDecl`, `Constructor:ReturnStmt`,
`Constructor:NextUnless`.

**Step 4: Run full test suite**

Every test file in `t/bootstrap/` must pass. This is the critical validation
that the migration is complete.

Run: `$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/*.t`

**Step 5: Commit**

```bash
git add lib/Chalk/Bootstrap/Perl/Actions.pm lib/Chalk/Bootstrap/Perl/Target/XS.pm \
        lib/Chalk/Bootstrap/Perl/Target/Perl.pm lib/Chalk/Bootstrap/IR/NodeFactory.pm
git commit -m "refactor: remove tree-shaped IfStmt/ForeachLoop/PostfixLoop, complete CFG migration"
```

---

## Task 14: Peephole Optimizations — Redundant Phi Elimination

**Files:**
- Create: `t/bootstrap/optimizer-cfg-peephole.t`
- Create or Modify: `lib/Chalk/Bootstrap/IR/Optimizer.pm` (or new file)

**Step 1: Write failing test**

Create Phi(Region, X, X) — both inputs are the same node. Verify the optimizer
collapses it to X. Create If(Constant(true)) — verify the optimizer eliminates
the dead false branch. Create Region with single live input — verify collapse.

**Step 2: Implement peephole rules**

- `Phi(R, X, X) → X` when all value inputs are the same node (by refaddr)
- `If(Constant(truthy)) → collapse` to TrueProj only; FalseProj becomes dead
- `Region([single_ctrl]) → single_ctrl` (bypass Region)

**Step 3: Run tests**

Run optimizer-cfg-peephole.t → PASS
Run concise-per-file.t → check if oracle mismatches improve

**Step 4: Commit**

```bash
git add lib/Chalk/Bootstrap/IR/Optimizer.pm t/bootstrap/optimizer-cfg-peephole.t
git commit -m "feat: peephole optimizations for Phi/If/Region CFG nodes"
```

---

## Summary

| Task | Description | Risk | Dependencies |
|------|-------------|------|-------------|
| 1 | If node type | Low | None |
| 2 | Region/Phi/Loop/Proj types | Low | Task 1 |
| 3 | CFG subgraph pattern tests | Low | Tasks 1-2 |
| 4 | Scope data structure | Low | None |
| 5 | Enrich SemanticAction focus | **High** | Tasks 1-2, 4 |
| 6 | VarDecl/variable scope population | Medium | Task 5 |
| 7 | If/else CFG in Actions.pm | **High** | Tasks 5-6 |
| 8 | Scan-time loop sentinels | Medium | Task 5 |
| 9 | Loop CFG in Actions.pm | **High** | Tasks 7-8 |
| 10 | XS target if/else | Medium | Task 7 |
| 11 | XS target loops | Medium | Task 9 |
| 12 | Perl target CFG | Medium | Tasks 7, 9 |
| 13 | Remove backward compat | **High** | Tasks 10-12 |
| 14 | Peephole optimizations | Low | Tasks 7, 9 |

Tasks 1-4 can run in parallel (no dependencies). Task 5 is the critical
pivot point. Tasks 10-12 can run in parallel after Task 9.
