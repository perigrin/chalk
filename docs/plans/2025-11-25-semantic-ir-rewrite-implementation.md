# Semantic/IR Rewrite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify IR construction by having Rule semantic actions create immutable IR nodes directly, eliminating the Builder intermediary.

**Architecture:** Immutable Sea of Nodes graph built during parsing. Rules construct nodes with simple constructors. Content-addressable IDs computed in field declarations. Scope tracks SSA bindings and current control.

**Tech Stack:** Perl 5.42.0 classes, Chalk parser, Earley semirings

---

## Phase 1: Simplified IR Node Classes

### Task 1.1: Create IR::Node::Base v2

**Files:**
- Create: `lib/Chalk/IR/Node/Base2.pm`
- Test: `t/ir/node-base2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for simplified IR::Node::Base2
# ABOUTME: Validates basic node structure and ID generation
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Base2');

# Test that Base2 can be subclassed
{
    package TestNode;
    use 5.42.0;
    use experimental 'class';
    class TestNode :isa(Chalk::IR::Node::Base2) {
        field $value :param :reader;
        field $id :reader = "test_${value}";
    }
}

my $node = TestNode->new(value => 42);
is($node->id, 'test_42', 'ID computed from field');
is($node->value, 42, 'Value accessible');
ok($node->inputs, 'inputs method exists');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-base2.t`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

```perl
# ABOUTME: Base class for simplified IR nodes (v2 rewrite)
# ABOUTME: Provides common infrastructure - ID, inputs, serialization
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Base2 {
    field $inputs :param :reader = [];

    method to_hash() {
        return {
            id     => $self->id,
            inputs => $inputs,
        };
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-base2.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Base2.pm t/ir/node-base2.t
git commit -m "feat: add simplified IR::Node::Base2 for rewrite"
```

---

### Task 1.2: Create IR::Node::Constant2

**Files:**
- Create: `lib/Chalk/IR/Node/Constant2.pm`
- Test: `t/ir/node-constant2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for simplified Constant node
# ABOUTME: Validates content-addressable ID generation
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Constant2');

my $c1 = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
is($c1->id, 'const_Int_42', 'Content-addressable ID');
is($c1->type, 'Int', 'Type accessible');
is($c1->value, 42, 'Value accessible');
is($c1->op, 'Constant', 'Op is Constant');

# Same inputs = same ID (content-addressable)
my $c2 = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
is($c2->id, $c1->id, 'Same inputs produce same ID');

# Different inputs = different ID
my $c3 = Chalk::IR::Node::Constant2->new(type => 'Int', value => 99);
isnt($c3->id, $c1->id, 'Different inputs produce different ID');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-constant2.t`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

```perl
# ABOUTME: Constant node for literal values (v2 rewrite)
# ABOUTME: Content-addressable ID computed from type and value
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Constant2 :isa(Chalk::IR::Node::Base2) {
    field $type :param :reader;
    field $value :param :reader;
    field $id :reader = "const_${type}_${value}";

    method op() { 'Constant' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Constant',
            inputs => [],
            attributes => {
                type  => $type,
                value => $value,
            },
        };
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-constant2.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Constant2.pm t/ir/node-constant2.t
git commit -m "feat: add simplified IR::Node::Constant2"
```

---

### Task 1.3: Create IR::Node::Start2

**Files:**
- Create: `lib/Chalk/IR/Node/Start2.pm`
- Test: `t/ir/node-start2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for simplified Start node
# ABOUTME: Entry point for control flow
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Start2');

my $start = Chalk::IR::Node::Start2->new(label => 'main');
is($start->id, 'start_main', 'Content-addressable ID');
is($start->label, 'main', 'Label accessible');
is($start->op, 'Start', 'Op is Start');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-start2.t`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

```perl
# ABOUTME: Start node - control flow entry point (v2 rewrite)
# ABOUTME: Has no control predecessor
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Start2 :isa(Chalk::IR::Node::Base2) {
    field $label :param :reader;
    field $id :reader = "start_${label}";

    method op() { 'Start' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Start',
            inputs => [],
            attributes => { label => $label },
        };
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-start2.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Start2.pm t/ir/node-start2.t
git commit -m "feat: add simplified IR::Node::Start2"
```

---

### Task 1.4: Create IR::Node::Store2

**Files:**
- Create: `lib/Chalk/IR/Node/Store2.pm`
- Test: `t/ir/node-store2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for simplified Store node
# ABOUTME: Control node for variable assignment
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Store2');
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Constant2;

my $start = Chalk::IR::Node::Start2->new(label => 'main');
my $value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);

my $store = Chalk::IR::Node::Store2->new(
    control => $start,
    var     => 'x',
    value   => $value,
);

is($store->id, 'store_x_start_main_const_Int_42', 'Content-addressable ID');
is($store->var, 'x', 'Variable name accessible');
is($store->control, $start, 'Control predecessor accessible');
is($store->value, $value, 'Value node accessible');
is($store->op, 'Store', 'Op is Store');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-store2.t`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

```perl
# ABOUTME: Store node - variable assignment (v2 rewrite)
# ABOUTME: Control node that sits in control chain, carries value reference
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Store2 :isa(Chalk::IR::Node::Base2) {
    field $control :param :reader;
    field $var :param :reader;
    field $value :param :reader;
    field $id :reader = "store_${var}_" . $control->id . "_" . $value->id;

    method op() { 'Store' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Store',
            inputs => [$control->id, $value->id],
            attributes => {
                var      => $var,
                control  => $control->id,
                value_id => $value->id,
            },
        };
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-store2.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Store2.pm t/ir/node-store2.t
git commit -m "feat: add simplified IR::Node::Store2"
```

---

### Task 1.5: Create IR::Node::Return2

**Files:**
- Create: `lib/Chalk/IR/Node/Return2.pm`
- Test: `t/ir/node-return2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for simplified Return node
# ABOUTME: Control flow exit with value
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Return2');
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Store2;
use Chalk::IR::Node::Constant2;

my $start = Chalk::IR::Node::Start2->new(label => 'main');
my $value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
my $store = Chalk::IR::Node::Store2->new(control => $start, var => 'x', value => $value);

my $return = Chalk::IR::Node::Return2->new(
    control => $store,
    value   => $value,
);

is($return->id, 'return_store_x_start_main_const_Int_42_const_Int_42', 'Content-addressable ID');
is($return->control, $store, 'Control predecessor accessible');
is($return->value, $value, 'Value node accessible');
is($return->op, 'Return', 'Op is Return');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-return2.t`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

```perl
# ABOUTME: Return node - control flow exit (v2 rewrite)
# ABOUTME: Has control predecessor and value reference
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Return2 :isa(Chalk::IR::Node::Base2) {
    field $control :param :reader;
    field $value :param :reader;
    field $id :reader = "return_" . $control->id . "_" . $value->id;

    method op() { 'Return' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Return',
            inputs => [$control->id, $value->id],
            attributes => {
                control  => $control->id,
                value_id => $value->id,
            },
        };
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-return2.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Return2.pm t/ir/node-return2.t
git commit -m "feat: add simplified IR::Node::Return2"
```

---

### Task 1.6: Create IR::Node::Add2

**Files:**
- Create: `lib/Chalk/IR/Node/Add2.pm`
- Test: `t/ir/node-add2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for simplified Add node
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Add2');
use Chalk::IR::Node::Constant2;

my $left = Chalk::IR::Node::Constant2->new(type => 'Int', value => 10);
my $right = Chalk::IR::Node::Constant2->new(type => 'Int', value => 5);

my $add = Chalk::IR::Node::Add2->new(left => $left, right => $right);

is($add->id, 'add_const_Int_10_const_Int_5', 'Content-addressable ID');
is($add->left, $left, 'Left operand accessible');
is($add->right, $right, 'Right operand accessible');
is($add->op, 'Add', 'Op is Add');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-add2.t`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

```perl
# ABOUTME: Add node - binary addition (v2 rewrite)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Add2 :isa(Chalk::IR::Node::Base2) {
    field $left :param :reader;
    field $right :param :reader;
    field $id :reader = "add_" . $left->id . "_" . $right->id;

    method op() { 'Add' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Add',
            inputs => [$left->id, $right->id],
            attributes => {
                left  => $left->id,
                right => $right->id,
            },
        };
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-add2.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Add2.pm t/ir/node-add2.t
git commit -m "feat: add simplified IR::Node::Add2"
```

---

## Phase 2: Scope and Semantic Semiring

### Task 2.1: Create IR::Node::Scope2

**Files:**
- Create: `lib/Chalk/IR/Node/Scope2.pm`
- Test: `t/ir/node-scope2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for simplified Scope node
# ABOUTME: SSA bindings and control tracking
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::IR::Node::Scope2');
use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Constant2;

my $scope = Chalk::IR::Node::Scope2->new();

# Control tracking
my $start = Chalk::IR::Node::Start2->new(label => 'main');
$scope->set_current_control($start);
is($scope->current_control, $start, 'Current control set');

# Variable binding
my $value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
$scope->define('x', $value);
is($scope->get('x'), $value, 'Variable bound');

# Snapshot/restore
my $snapshot = $scope->snapshot();
my $new_value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 99);
$scope->define('x', $new_value);
is($scope->get('x'), $new_value, 'Variable rebound');

$scope->restore($snapshot);
is($scope->get('x'), $value, 'Snapshot restored');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-scope2.t`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

```perl
# ABOUTME: Scope for SSA variable bindings (v2 rewrite)
# ABOUTME: Tracks variable->node mappings and current control
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Scope2 {
    field $bindings = {};
    field $current_control :reader;

    method set_current_control($ctrl) {
        $current_control = $ctrl;
    }

    method define($name, $node) {
        $bindings->{$name} = $node;
    }

    method get($name) {
        return $bindings->{$name};
    }

    method snapshot() {
        return {
            bindings => { %$bindings },
            control  => $current_control,
        };
    }

    method restore($snap) {
        $bindings = { $snap->{bindings}->%* };
        $current_control = $snap->{control};
    }

    method modified_vars($before_snapshot) {
        my @modified;
        for my $var (keys %$bindings) {
            my $before = $before_snapshot->{bindings}{$var};
            my $after = $bindings->{$var};
            if (!$before || $before->id ne $after->id) {
                push @modified, $var;
            }
        }
        return @modified;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/node-scope2.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Scope2.pm t/ir/node-scope2.t
git commit -m "feat: add simplified IR::Node::Scope2"
```

---

### Task 2.2: Create Semiring::Semantic2

**Files:**
- Create: `lib/Chalk/Semiring/Semantic2.pm`
- Test: `t/semiring/semantic2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for simplified Semantic semiring
# ABOUTME: Validates scope in env and rule dispatch
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::Semiring::Semantic2');
use Chalk::IR::Node::Scope2;

# Test construction with default scope
my $sem = Chalk::Semiring::Semantic2->new();
ok($sem->env->{scope}, 'Default scope created');
isa_ok($sem->env->{scope}, 'Chalk::IR::Node::Scope2');

# Test construction with provided scope
my $scope = Chalk::IR::Node::Scope2->new();
my $sem2 = Chalk::Semiring::Semantic2->new(env => { scope => $scope });
is($sem2->env->{scope}, $scope, 'Provided scope used');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/semiring/semantic2.t`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

```perl
# ABOUTME: Simplified Semantic semiring (v2 rewrite)
# ABOUTME: Provides scope to Rules, dispatches evaluation
use 5.42.0;
use experimental qw(class);

class Chalk::Semiring::Semantic2 {
    use Chalk::IR::Node::Scope2;

    field $env :param :reader = {};

    ADJUST {
        $env->{scope} //= Chalk::IR::Node::Scope2->new();
    }

    method one() {
        return 1;  # Identity
    }

    method zero() {
        return 0;  # Failure
    }

    method evaluate($rule_name, $context) {
        # Inject env into context
        $context->set_env($env) if $context->can('set_env');

        # Look up Rule class
        my $rule_class = "Chalk::Grammar::Chalk::Rule::${rule_name}";
        if ($rule_class->can('evaluate')) {
            my $rule = $rule_class->new();
            return $rule->evaluate($context);
        }

        # Pass through first child if no semantic action
        return $context->child(0) if $context->can('child');
        return undef;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/semiring/semantic2.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Semiring/Semantic2.pm t/semiring/semantic2.t
git commit -m "feat: add simplified Chalk::Semiring::Semantic2"
```

---

## Phase 3: End-to-End Test with Simple Case

### Task 3.1: Create integration test for `my $x = 42;`

**Files:**
- Create: `t/ir/simple-assignment-v2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Integration test for simple assignment IR generation
# ABOUTME: Tests my $x = 42; produces correct Sea of Nodes structure
use 5.42.0;
use Test::More;
use lib 'lib';

use Chalk::IR::Node::Start2;
use Chalk::IR::Node::Store2;
use Chalk::IR::Node::Return2;
use Chalk::IR::Node::Constant2;

# Manually construct expected IR for: my $x = 42;
my $start = Chalk::IR::Node::Start2->new(label => 'main');
my $value = Chalk::IR::Node::Constant2->new(type => 'Int', value => 42);
my $store = Chalk::IR::Node::Store2->new(
    control => $start,
    var     => 'x',
    value   => $value,
);
my $return = Chalk::IR::Node::Return2->new(
    control => $store,
    value   => $value,
);

# Verify structure
is($return->op, 'Return', 'Root is Return');
is($return->control->op, 'Store', 'Return control is Store');
is($return->control->control->op, 'Start', 'Store control is Start');
is($return->value->op, 'Constant', 'Return value is Constant');
is($return->value->value, 42, 'Constant value is 42');

# Verify control chain: Start -> Store -> Return
is($return->control->id, 'store_x_start_main_const_Int_42', 'Store ID correct');
is($return->id, 'return_store_x_start_main_const_Int_42_const_Int_42', 'Return ID correct');

# Verify data flow: Return.value -> Constant
is($return->value->id, 'const_Int_42', 'Value ID correct');

done_testing();
```

**Step 2: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/ir/simple-assignment-v2.t`
Expected: PASS (uses previously created nodes)

**Step 3: Commit**

```bash
git add t/ir/simple-assignment-v2.t
git commit -m "test: add integration test for simple assignment IR structure"
```

---

## Phase 4: Rule Semantic Actions (Incremental)

### Task 4.1: Create Rule::Integer2 semantic action

**Files:**
- Create: `lib/Chalk/Grammar/Chalk/Rule/Integer2.pm`
- Test: `t/rules/integer2.t`

**Step 1: Write the failing test**

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for Integer2 rule semantic action
# ABOUTME: Validates Constant node creation from integer literal
use 5.42.0;
use Test::More;
use lib 'lib';

use_ok('Chalk::Grammar::Chalk::Rule::Integer2');
use Chalk::IR::Node::Constant2;

# Mock context that returns '42' as the matched text
{
    package MockContext;
    sub new { bless { text => $_[1] }, $_[0] }
    sub child { return $_[0]->{text} }
    sub env { return {} }
}

my $ctx = MockContext->new('42');
my $rule = Chalk::Grammar::Chalk::Rule::Integer2->new();
my $result = $rule->evaluate($ctx);

isa_ok($result, 'Chalk::IR::Node::Constant2');
is($result->type, 'Int', 'Type is Int');
is($result->value, 42, 'Value is 42');
is($result->id, 'const_Int_42', 'ID is content-addressable');

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/rules/integer2.t`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

```perl
# ABOUTME: Semantic action for Integer literal (v2 rewrite)
# ABOUTME: Creates Constant node from matched digits
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Integer2 {
    use Chalk::IR::Node::Constant2;

    method evaluate($context) {
        my $digits = $context->child(0);
        # Handle both string and token objects
        $digits = "$digits" if ref($digits);

        return Chalk::IR::Node::Constant2->new(
            type  => 'Int',
            value => $digits + 0,  # Ensure numeric
        );
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -Ilib t/rules/integer2.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/Rule/Integer2.pm t/rules/integer2.t
git commit -m "feat: add Integer2 rule semantic action"
```

---

## Phase 5: Remaining Tasks (To Be Expanded)

The following tasks follow the same pattern and should be implemented after Phase 4 validation:

### Task 5.1: Create remaining arithmetic nodes (Sub2, Mul2, Div2)
### Task 5.2: Create comparison nodes (GT2, LT2, EQ2, etc.)
### Task 5.3: Create unary nodes (Negate2, Not2)
### Task 5.4: Create control flow nodes (If2, Proj2, Region2, Phi2)
### Task 5.5: Create Assignment2 rule semantic action
### Task 5.6: Create Program2 rule semantic action
### Task 5.7: Full parser integration test
### Task 5.8: Compare against corpus
### Task 5.9: Rename v2 classes to replace originals
### Task 5.10: Delete IR::Builder and related code

---

## Validation Checkpoints

After each phase:
1. All new tests pass
2. Existing tests still pass (until Phase 5.9)
3. Manual inspection of IR structure for `my $x = 42;`

Final validation:
- Compare generated IR against corpus
- Compare against Sea of Nodes tutorial structures
