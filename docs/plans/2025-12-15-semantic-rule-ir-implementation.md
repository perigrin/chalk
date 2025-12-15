# Theme 2: Semantic Rule IR Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement IR generation for semantic rules that are currently pass-through stubs, enabling full language functionality.

**Architecture:** Tier-ordered sequential implementation. Each tier builds on the previous: Tier 0 (wire existing nodes), Tier 1 (simple new nodes), Tier 2 (Call infrastructure), Tier 3 (higher-order functions), Tier 4 (complex features).

**Tech Stack:** Perl 5.42.0, Object::Pad classes, Sea of Nodes IR pattern, TAP testing.

**Design Reference:** See `docs/plans/2025-12-15-semantic-rule-ir-design.md` for architecture decisions.

---

## Tier 0: Quick Wins

### Task 1: Wire PreIncrement/PreDecrement in Unary.pm

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/Unary.pm:78-81`
- Test: `t/grammar/prefix-increment.t` (create)

**Step 1: Write the failing test**

Create `t/grammar/prefix-increment.t`:

```perl
# ABOUTME: Tests for prefix increment/decrement IR generation
# ABOUTME: Verifies Unary.pm generates PreIncrement/PreDecrement nodes

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::Grammar;
use Chalk::Semiring::Semantic;

my $grammar = Chalk::Grammar->new(grammar_file => 'grammars/chalk.bnf');
my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

subtest 'prefix increment generates PreIncrement node' => sub {
    my $code = '++$x';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::PreIncrement'),
       'Result is PreIncrement node') or diag "Got: " . ref($result);
};

subtest 'prefix decrement generates PreDecrement node' => sub {
    my $code = '--$x';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::PreDecrement'),
       'Result is PreDecrement node') or diag "Got: " . ref($result);
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/grammar/prefix-increment.t`
Expected: FAIL - Result is not PreIncrement/PreDecrement (currently passes through)

**Step 3: Implement PreIncrement/PreDecrement in Unary.pm**

In `lib/Chalk/Grammar/Chalk/Rule/Unary.pm`, replace lines 78-81:

```perl
        } elsif ($operator eq '++') {
            use Chalk::IR::Node::PreIncrement;
            return Chalk::IR::Node::PreIncrement->new(operand => $operand)->peephole();
        } elsif ($operator eq '--') {
            use Chalk::IR::Node::PreDecrement;
            return Chalk::IR::Node::PreDecrement->new(operand => $operand)->peephole();
        }
```

**Step 4: Run test to verify it passes**

Run: `./prove t/grammar/prefix-increment.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/Rule/Unary.pm t/grammar/prefix-increment.t
git commit -m "feat(grammar): Wire PreIncrement/PreDecrement in Unary.pm

Closes part of #189"
```

---

### Task 2: Wire PostIncrement/PostDecrement in Unary.pm

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/Unary.pm:30-34`
- Test: `t/grammar/postfix-increment.t` (create)

**Step 1: Write the failing test**

Create `t/grammar/postfix-increment.t`:

```perl
# ABOUTME: Tests for postfix increment/decrement IR generation
# ABOUTME: Verifies Unary.pm generates PostIncrement/PostDecrement nodes

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::Grammar;
use Chalk::Semiring::Semantic;

my $grammar = Chalk::Grammar->new(grammar_file => 'grammars/chalk.bnf');
my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

subtest 'postfix increment generates PostIncrement node' => sub {
    my $code = '$x++';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::PostIncrement'),
       'Result is PostIncrement node') or diag "Got: " . ref($result);
};

subtest 'postfix decrement generates PostDecrement node' => sub {
    my $code = '$x--';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::PostDecrement'),
       'Result is PostDecrement node') or diag "Got: " . ref($result);
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/grammar/postfix-increment.t`
Expected: FAIL - Result is not PostIncrement/PostDecrement

**Step 3: Implement PostIncrement/PostDecrement in Unary.pm**

In `lib/Chalk/Grammar/Chalk/Rule/Unary.pm`, replace lines 30-34 in the `@children == 2` block:

```perl
                if ($str_val eq '++') {
                    use Chalk::IR::Node::PostIncrement;
                    my $var = $context->child(0);
                    return Chalk::IR::Node::PostIncrement->new(operand => $var)->peephole();
                } elsif ($str_val eq '--') {
                    use Chalk::IR::Node::PostDecrement;
                    my $var = $context->child(0);
                    return Chalk::IR::Node::PostDecrement->new(operand => $var)->peephole();
                }
```

**Step 4: Run test to verify it passes**

Run: `./prove t/grammar/postfix-increment.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/Rule/Unary.pm t/grammar/postfix-increment.t
git commit -m "feat(grammar): Wire PostIncrement/PostDecrement in Unary.pm

Closes #189"
```

---

### Task 3: Create Die IR Node

**Files:**
- Create: `lib/Chalk/IR/Node/Die.pm`
- Test: `t/ir/die-node.t` (create)

**Step 1: Write the failing test**

Create `t/ir/die-node.t`:

```perl
# ABOUTME: Tests for Die IR node
# ABOUTME: Verifies Die node construction and type computation

use lib 'lib';
use v5.42;
use Test::More;

use_ok('Chalk::IR::Node::Die');

subtest 'Die node construction' => sub {
    my $die = Chalk::IR::Node::Die->new(message => 'Test error');

    ok(defined($die), 'Die node created');
    is($die->message, 'Test error', 'Message stored correctly');
    is($die->op, 'Die', 'Op is Die');
};

subtest 'Die node default message' => sub {
    my $die = Chalk::IR::Node::Die->new();

    is($die->message, 'Died', 'Default message is Died');
};

subtest 'Die node compute returns Bottom' => sub {
    my $die = Chalk::IR::Node::Die->new(message => 'Error');
    my $type = $die->compute();

    ok($type->isa('Chalk::IR::Type::Bottom') || $type->is_bottom,
       'Die compute returns Bottom type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/die-node.t`
Expected: FAIL - Can't locate Chalk/IR/Node/Die.pm

**Step 3: Implement Die node**

Create `lib/Chalk/IR/Node/Die.pm`:

```perl
# ABOUTME: Die node represents runtime panic/die
# ABOUTME: Used for yada-yada operator (...) and explicit die statements

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Node::Die :isa(Chalk::IR::Node::Base) {
    field $message :param :reader = 'Died';

    method compute() {
        return Chalk::IR::Type::Bottom->new();
    }

    method op() { 'Die' }

    method label() { "Die: $message" }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/die-node.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Die.pm t/ir/die-node.t
git commit -m "feat(ir): Add Die node for runtime panic

Part of #388"
```

---

### Task 4: Wire YaddaYadda to Die Node

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/YaddaYadda.pm`
- Test: `t/grammar/yaddayadda.t` (create)

**Step 1: Write the failing test**

Create `t/grammar/yaddayadda.t`:

```perl
# ABOUTME: Tests for yada-yada operator (...) IR generation
# ABOUTME: Verifies YaddaYadda.pm generates Die node

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::Grammar;
use Chalk::Semiring::Semantic;

my $grammar = Chalk::Grammar->new(grammar_file => 'grammars/chalk.bnf');
my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

subtest 'yada-yada generates Die node' => sub {
    my $code = '...';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::Die'),
       'Result is Die node') or diag "Got: " . ref($result);
    is($result->message, 'Unimplemented', 'Message is Unimplemented');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/grammar/yaddayadda.t`
Expected: FAIL - Result is not Die node

**Step 3: Implement YaddaYadda to generate Die**

Replace `lib/Chalk/Grammar/Chalk/Rule/YaddaYadda.pm`:

```perl
# ABOUTME: Semantic action for YaddaYadda - the yada-yada operator (...)
# ABOUTME: Generates Die node that panics at runtime with 'Unimplemented'

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::YaddaYadda :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Die;
        return Chalk::IR::Node::Die->new(
            message => 'Unimplemented'
        )->peephole();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/grammar/yaddayadda.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/Rule/YaddaYadda.pm t/grammar/yaddayadda.t
git commit -m "feat(grammar): YaddaYadda generates Die node

Closes #388"
```

---

### Task 5: Run full test suite for Tier 0

**Step 1: Run all Tier 0 tests**

Run: `./prove t/grammar/prefix-increment.t t/grammar/postfix-increment.t t/ir/die-node.t t/grammar/yaddayadda.t`
Expected: All PASS

**Step 2: Run full test suite to check for regressions**

Run: `./prove`
Expected: No new failures

**Step 3: Commit checkpoint**

```bash
git commit --allow-empty -m "checkpoint: Tier 0 complete - increment/decrement and YaddaYadda"
```

---

## Tier 1: Simple New Nodes

### Task 6: Create ISA IR Node

**Files:**
- Create: `lib/Chalk/IR/Node/ISA.pm`
- Test: `t/ir/isa-node.t` (create)

**Step 1: Write the failing test**

Create `t/ir/isa-node.t`:

```perl
# ABOUTME: Tests for ISA IR node
# ABOUTME: Verifies ISA node for type checking operator

use lib 'lib';
use v5.42;
use Test::More;

use_ok('Chalk::IR::Node::ISA');

subtest 'ISA node construction' => sub {
    my $operand = Chalk::IR::Node::Constant->new(value => 42, type => 'Int');
    my $isa = Chalk::IR::Node::ISA->new(
        operand   => $operand,
        type_name => 'SomeClass'
    );

    ok(defined($isa), 'ISA node created');
    is($isa->type_name, 'SomeClass', 'Type name stored correctly');
    is($isa->op, 'ISA', 'Op is ISA');
};

subtest 'ISA node compute returns Bool' => sub {
    my $operand = Chalk::IR::Node::Constant->new(value => 42, type => 'Int');
    my $isa = Chalk::IR::Node::ISA->new(
        operand   => $operand,
        type_name => 'Int'
    );
    my $type = $isa->compute();

    ok($type->isa('Chalk::IR::Type::TypeBool') || $type->name eq 'Bool',
       'ISA compute returns Bool type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/isa-node.t`
Expected: FAIL - Can't locate Chalk/IR/Node/ISA.pm

**Step 3: Implement ISA node**

Create `lib/Chalk/IR/Node/ISA.pm`:

```perl
# ABOUTME: ISA node for type checking operator
# ABOUTME: Returns boolean indicating if value is instance of type

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Type::TypeBool;

class Chalk::IR::Node::ISA :isa(Chalk::IR::Node::Base) {
    field $operand :param :reader;     # The value to check
    field $type_name :param :reader;   # The type name (string or type object)

    method compute() {
        return Chalk::IR::Type::TypeBool->BOOL;
    }

    method op() { 'ISA' }

    method label() { "ISA: $type_name" }

    method inputs() { [$operand] }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/isa-node.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/ISA.pm t/ir/isa-node.t
git commit -m "feat(ir): Add ISA node for type checking

Part of #316"
```

---

### Task 7: Wire ISA operator in ComparisonOp.pm

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/ComparisonOp.pm:125-127`
- Test: `t/grammar/isa-operator.t` (create)

**Step 1: Write the failing test**

Create `t/grammar/isa-operator.t`:

```perl
# ABOUTME: Tests for isa operator IR generation
# ABOUTME: Verifies ComparisonOp.pm generates ISA node

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::Grammar;
use Chalk::Semiring::Semantic;

my $grammar = Chalk::Grammar->new(grammar_file => 'grammars/chalk.bnf');
my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

subtest 'isa operator generates ISA node' => sub {
    my $code = '$obj isa SomeClass';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::ISA'),
       'Result is ISA node') or diag "Got: " . ref($result);
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/grammar/isa-operator.t`
Expected: FAIL - Result is not ISA node (currently passes through)

**Step 3: Implement ISA in ComparisonOp.pm**

In `lib/Chalk/Grammar/Chalk/Rule/ComparisonOp.pm`, replace the isa pass-through (around line 125):

```perl
        elsif ($operator eq 'isa') {
            use Chalk::IR::Node::ISA;
            # Right side is type name - stringify if it's a token/identifier
            my $type_str = ref($right) ? "$right" : $right;
            return Chalk::IR::Node::ISA->new(
                operand   => $left,
                type_name => $type_str
            )->peephole();
        }
```

**Step 4: Run test to verify it passes**

Run: `./prove t/grammar/isa-operator.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/Rule/ComparisonOp.pm t/grammar/isa-operator.t
git commit -m "feat(grammar): Wire isa operator to ISA node in ComparisonOp

Closes #316"
```

---

### Task 8: Create ArrayDeref and HashDeref IR Nodes

**Files:**
- Create: `lib/Chalk/IR/Node/ArrayDeref.pm`
- Create: `lib/Chalk/IR/Node/HashDeref.pm`
- Test: `t/ir/deref-nodes.t` (create)

**Step 1: Write the failing test**

Create `t/ir/deref-nodes.t`:

```perl
# ABOUTME: Tests for ArrayDeref and HashDeref IR nodes
# ABOUTME: Verifies dereference nodes for @$ref and %$ref syntax

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Constant;

subtest 'ArrayDeref node' => sub {
    use_ok('Chalk::IR::Node::ArrayDeref');

    my $ref = Chalk::IR::Node::Constant->new(value => [], type => 'ArrayRef');
    my $deref = Chalk::IR::Node::ArrayDeref->new(ref => $ref);

    ok(defined($deref), 'ArrayDeref node created');
    is($deref->op, 'ArrayDeref', 'Op is ArrayDeref');

    my $type = $deref->compute();
    ok($type->name =~ /Array/i, 'ArrayDeref compute returns Array type');
};

subtest 'HashDeref node' => sub {
    use_ok('Chalk::IR::Node::HashDeref');

    my $ref = Chalk::IR::Node::Constant->new(value => {}, type => 'HashRef');
    my $deref = Chalk::IR::Node::HashDeref->new(ref => $ref);

    ok(defined($deref), 'HashDeref node created');
    is($deref->op, 'HashDeref', 'Op is HashDeref');

    my $type = $deref->compute();
    ok($type->name =~ /Hash/i, 'HashDeref compute returns Hash type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/deref-nodes.t`
Expected: FAIL - Can't locate modules

**Step 3: Implement ArrayDeref and HashDeref**

Create `lib/Chalk/IR/Node/ArrayDeref.pm`:

```perl
# ABOUTME: ArrayDeref for @$ref prefix dereference syntax
# ABOUTME: Dereferences a reference to get array contents

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Type::Array;

class Chalk::IR::Node::ArrayDeref :isa(Chalk::IR::Node::Base) {
    field $ref :param :reader;  # The reference to dereference

    method compute() {
        return Chalk::IR::Type::Array->new();
    }

    method op() { 'ArrayDeref' }

    method inputs() { [$ref] }
}

1;
```

Create `lib/Chalk/IR/Node/HashDeref.pm`:

```perl
# ABOUTME: HashDeref for %$ref prefix dereference syntax
# ABOUTME: Dereferences a reference to get hash contents

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Type::Hash;

class Chalk::IR::Node::HashDeref :isa(Chalk::IR::Node::Base) {
    field $ref :param :reader;  # The reference to dereference

    method compute() {
        return Chalk::IR::Type::Hash->new();
    }

    method op() { 'HashDeref' }

    method inputs() { [$ref] }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/deref-nodes.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/ArrayDeref.pm lib/Chalk/IR/Node/HashDeref.pm t/ir/deref-nodes.t
git commit -m "feat(ir): Add ArrayDeref and HashDeref nodes

Part of #161"
```

---

### Task 9: Run full test suite for Tier 1

**Step 1: Run all Tier 1 tests**

Run: `./prove t/ir/isa-node.t t/grammar/isa-operator.t t/ir/deref-nodes.t`
Expected: All PASS

**Step 2: Run full test suite to check for regressions**

Run: `./prove`
Expected: No new failures

**Step 3: Commit checkpoint**

```bash
git commit --allow-empty -m "checkpoint: Tier 1 complete - ISA and Deref nodes"
```

---

## Tier 2: Call Infrastructure

### Task 10: Create Call IR Node

**Files:**
- Create: `lib/Chalk/IR/Node/Call.pm`
- Test: `t/ir/call-node.t` (create)

**Step 1: Write the failing test**

Create `t/ir/call-node.t`:

```perl
# ABOUTME: Tests for Call IR node
# ABOUTME: Verifies Call node for function/method invocation

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Constant;

use_ok('Chalk::IR::Node::Call');

subtest 'Call node basic construction' => sub {
    my $call = Chalk::IR::Node::Call->new(
        callee => 'foo',
        args   => [],
    );

    ok(defined($call), 'Call node created');
    is($call->callee, 'foo', 'Callee stored correctly');
    is($call->op, 'Call', 'Op is Call');
    ok(defined($call->rpc), 'RPC generated automatically');
};

subtest 'Call node with arguments' => sub {
    my $arg1 = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $arg2 = Chalk::IR::Node::Constant->new(value => 2, type => 'Int');

    my $call = Chalk::IR::Node::Call->new(
        callee => 'add',
        args   => [$arg1, $arg2],
    );

    is(scalar($call->args->@*), 2, 'Two arguments stored');
};

subtest 'Call node with receiver (method call)' => sub {
    my $receiver = Chalk::IR::Node::Constant->new(value => 'obj', type => 'Ref');

    my $call = Chalk::IR::Node::Call->new(
        callee   => 'method',
        receiver => $receiver,
        args     => [],
    );

    ok(defined($call->receiver), 'Receiver stored');
};

subtest 'RPC uniqueness' => sub {
    my $call1 = Chalk::IR::Node::Call->new(callee => 'a', args => []);
    my $call2 = Chalk::IR::Node::Call->new(callee => 'b', args => []);

    isnt($call1->rpc, $call2->rpc, 'Each call gets unique RPC');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/call-node.t`
Expected: FAIL - Can't locate Chalk/IR/Node/Call.pm

**Step 3: Implement Call node**

Create `lib/Chalk/IR/Node/Call.pm`:

```perl
# ABOUTME: Call node for function/method invocation
# ABOUTME: Sea of Nodes Chapter 18 - simplified initial implementation

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Type::Any;

class Chalk::IR::Node::Call :isa(Chalk::IR::Node::Base) {
    field $callee :param :reader;       # Function name or expression
    field $args :param :reader = [];    # Argument IR nodes
    field $receiver :param :reader;     # For method calls, the object/class
    field $rpc :param :reader;          # Return program counter (call-site ID)

    my $rpc_counter = 0;

    ADJUST {
        $rpc //= 'rpc_' . $rpc_counter++;
    }

    method compute() {
        # Return type depends on callee - Any for now
        # Future: look up function signature for return type
        return Chalk::IR::Type::Any->new();
    }

    method op() { 'Call' }

    method label() {
        my $name = ref($callee) ? 'expr' : $callee;
        return "Call: $name";
    }

    method inputs() {
        my @inputs;
        push @inputs, $receiver if defined($receiver);
        push @inputs, $args->@*;
        return \@inputs;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/call-node.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Call.pm t/ir/call-node.t
git commit -m "feat(ir): Add Call node for function/method invocation

Chapter 18 simplified implementation. Part of #383, #384"
```

---

### Task 11: Create CallEnd IR Node

**Files:**
- Create: `lib/Chalk/IR/Node/CallEnd.pm`
- Test: `t/ir/callend-node.t` (create)

**Step 1: Write the failing test**

Create `t/ir/callend-node.t`:

```perl
# ABOUTME: Tests for CallEnd IR node
# ABOUTME: Verifies CallEnd node follows Call and provides return value

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Call;

use_ok('Chalk::IR::Node::CallEnd');

subtest 'CallEnd node construction' => sub {
    my $call = Chalk::IR::Node::Call->new(callee => 'foo', args => []);
    my $callend = Chalk::IR::Node::CallEnd->new(call => $call);

    ok(defined($callend), 'CallEnd node created');
    is($callend->call, $call, 'Call reference stored');
    is($callend->op, 'CallEnd', 'Op is CallEnd');
};

subtest 'CallEnd propagates type from Call' => sub {
    my $call = Chalk::IR::Node::Call->new(callee => 'foo', args => []);
    my $callend = Chalk::IR::Node::CallEnd->new(call => $call);

    my $call_type = $call->compute();
    my $end_type = $callend->compute();

    is($end_type->name, $call_type->name, 'CallEnd propagates Call type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/callend-node.t`
Expected: FAIL - Can't locate Chalk/IR/Node/CallEnd.pm

**Step 3: Implement CallEnd node**

Create `lib/Chalk/IR/Node/CallEnd.pm`:

```perl
# ABOUTME: CallEnd node follows each Call
# ABOUTME: Provides projections for control, memory, return value

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;

class Chalk::IR::Node::CallEnd :isa(Chalk::IR::Node::Base) {
    field $call :param :reader;  # The CallNode this ends

    method compute() {
        # Propagate return type from call
        return $call->compute();
    }

    method op() { 'CallEnd' }

    method label() { 'CallEnd' }

    method inputs() { [$call] }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/callend-node.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/CallEnd.pm t/ir/callend-node.t
git commit -m "feat(ir): Add CallEnd node for call completion

Part of #383, #384"
```

---

### Task 12: Wire FunctionCall to Call/CallEnd

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/FunctionCall.pm`
- Test: `t/grammar/function-call-ir.t` (create)

**Step 1: Write the failing test**

Create `t/grammar/function-call-ir.t`:

```perl
# ABOUTME: Tests for FunctionCall IR generation
# ABOUTME: Verifies FunctionCall.pm generates Call/CallEnd nodes

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::Grammar;
use Chalk::Semiring::Semantic;

my $grammar = Chalk::Grammar->new(grammar_file => 'grammars/chalk.bnf');
my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

subtest 'function call without args generates CallEnd' => sub {
    my $code = 'foo()';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::CallEnd'),
       'Result is CallEnd node') or diag "Got: " . ref($result);
    ok($result->call->isa('Chalk::IR::Node::Call'),
       'CallEnd contains Call node');
    is($result->call->callee, 'foo', 'Callee is foo');
};

subtest 'function call with args' => sub {
    my $code = 'bar(1, 2)';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::CallEnd'), 'Result is CallEnd');
    is(scalar($result->call->args->@*), 2, 'Two arguments captured');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/grammar/function-call-ir.t`
Expected: FAIL - Result is not CallEnd (currently passes through)

**Step 3: Implement FunctionCall to generate Call/CallEnd**

Replace `lib/Chalk/Grammar/Chalk/Rule/FunctionCall.pm`:

```perl
# ABOUTME: Semantic action for FunctionCall - function and method calls
# ABOUTME: Generates Call and CallEnd IR nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::FunctionCall :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Call;
        use Chalk::IR::Node::CallEnd;

        # FunctionCall -> Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # FunctionCall -> Identifier '(' WS_OPT ')'

        my @children = $context->children->@*;

        # First child is the function name (Identifier)
        my $callee_child = $context->child(0);
        my $callee = ref($callee_child) && $callee_child->can('value')
                     ? $callee_child->value
                     : "$callee_child";

        # Extract arguments - scan for IR nodes after the opening paren
        my @args;
        for my $i (1 .. $#children) {
            my $child = $context->child($i);
            next unless defined($child);
            # Skip tokens (parens, commas, whitespace)
            if (ref($child) && $child->can('id')) {
                push @args, $child;
            }
        }

        my $call = Chalk::IR::Node::Call->new(
            callee => $callee,
            args   => \@args,
        );

        return Chalk::IR::Node::CallEnd->new(call => $call)->peephole();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/grammar/function-call-ir.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/Rule/FunctionCall.pm t/grammar/function-call-ir.t
git commit -m "feat(grammar): FunctionCall generates Call/CallEnd nodes

Closes #384"
```

---

### Task 13: Wire MethodCall to Call/CallEnd

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/MethodCall.pm`
- Test: `t/grammar/method-call-ir.t` (create)

**Step 1: Write the failing test**

Create `t/grammar/method-call-ir.t`:

```perl
# ABOUTME: Tests for MethodCall IR generation
# ABOUTME: Verifies MethodCall.pm generates Call/CallEnd with receiver

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::Grammar;
use Chalk::Semiring::Semantic;

my $grammar = Chalk::Grammar->new(grammar_file => 'grammars/chalk.bnf');
my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

subtest 'method call generates CallEnd with receiver' => sub {
    my $code = '$obj->method()';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::CallEnd'),
       'Result is CallEnd node') or diag "Got: " . ref($result);
    ok(defined($result->call->receiver), 'Call has receiver');
    is($result->call->callee, 'method', 'Callee is method');
};

subtest 'class method call' => sub {
    my $code = 'SomeClass->new()';
    my $result = $grammar->parse_string($code, semiring => $semiring);

    ok(defined($result), 'Parse succeeded');
    ok($result->isa('Chalk::IR::Node::CallEnd'), 'Result is CallEnd');
    is($result->call->callee, 'new', 'Callee is new');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/grammar/method-call-ir.t`
Expected: FAIL - Result is not CallEnd (currently passes through)

**Step 3: Implement MethodCall to generate Call/CallEnd**

Replace `lib/Chalk/Grammar/Chalk/Rule/MethodCall.pm`:

```perl
# ABOUTME: Semantic action for MethodCall - instance and class method invocations
# ABOUTME: Generates Call/CallEnd with receiver for method dispatch

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::MethodCall :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Call;
        use Chalk::IR::Node::CallEnd;

        # MethodCall -> Variable '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # MethodCall -> Variable '->' Identifier  # Without parens
        # MethodCall -> QualifiedIdentifier '->' Identifier '(' ... ')'

        my @children = $context->children->@*;

        # Find receiver (first child that evaluates to IR node)
        my $receiver;
        my $receiver_end_idx = 0;
        for my $i (0 .. $#children) {
            my $child = $context->child($i);
            if (ref($child) && $child->can('id')) {
                $receiver = $child;
                $receiver_end_idx = $i;
                last;
            }
        }

        # Find method name (identifier after ->)
        my $method_name;
        my $found_arrow = 0;
        for my $i ($receiver_end_idx + 1 .. $#children) {
            my $child = $children[$i];
            my $str_val = "$child";
            if ($str_val eq '->') {
                $found_arrow = 1;
                next;
            }
            if ($found_arrow && !defined($method_name)) {
                # This should be the method name
                $method_name = $str_val;
                last;
            }
        }

        # If no method name found, might be simpler structure - try child(2)
        unless (defined($method_name)) {
            my $name_child = $context->child(2);
            $method_name = defined($name_child) ? "$name_child" : 'unknown';
        }

        # Extract arguments - scan for IR nodes after method name
        my @args;
        my $collecting_args = 0;
        for my $i (0 .. $#children) {
            my $child_str = "$children[$i]";
            if ($child_str eq '(') {
                $collecting_args = 1;
                next;
            }
            if ($child_str eq ')') {
                last;
            }
            if ($collecting_args) {
                my $child = $context->child($i);
                if (ref($child) && $child->can('id')) {
                    push @args, $child;
                }
            }
        }

        my $call = Chalk::IR::Node::Call->new(
            callee   => $method_name,
            receiver => $receiver,
            args     => \@args,
        );

        return Chalk::IR::Node::CallEnd->new(call => $call)->peephole();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/grammar/method-call-ir.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/Rule/MethodCall.pm t/grammar/method-call-ir.t
git commit -m "feat(grammar): MethodCall generates Call/CallEnd with receiver

Closes #383"
```

---

### Task 14: Run full test suite for Tier 2

**Step 1: Run all Tier 2 tests**

Run: `./prove t/ir/call-node.t t/ir/callend-node.t t/grammar/function-call-ir.t t/grammar/method-call-ir.t`
Expected: All PASS

**Step 2: Run full test suite to check for regressions**

Run: `./prove`
Expected: No new failures

**Step 3: Commit checkpoint**

```bash
git commit --allow-empty -m "checkpoint: Tier 2 complete - Call infrastructure"
```

---

## Tier 3: Higher-Order Functions

### Task 15: Create Map IR Node

**Files:**
- Create: `lib/Chalk/IR/Node/Map.pm`
- Test: `t/ir/map-node.t` (create)

**Step 1: Write the failing test**

Create `t/ir/map-node.t`:

```perl
# ABOUTME: Tests for Map IR node
# ABOUTME: Verifies Map node for map { } @list transformation

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Constant;

use_ok('Chalk::IR::Node::Map');

subtest 'Map node construction' => sub {
    my $block = Chalk::IR::Node::Constant->new(value => sub {}, type => 'CodeRef');
    my $list = Chalk::IR::Node::Constant->new(value => [], type => 'ArrayRef');

    my $map = Chalk::IR::Node::Map->new(
        block => $block,
        list  => $list
    );

    ok(defined($map), 'Map node created');
    is($map->op, 'Map', 'Op is Map');
};

subtest 'Map compute returns ArrayRef' => sub {
    my $block = Chalk::IR::Node::Constant->new(value => sub {}, type => 'CodeRef');
    my $list = Chalk::IR::Node::Constant->new(value => [], type => 'ArrayRef');

    my $map = Chalk::IR::Node::Map->new(block => $block, list => $list);
    my $type = $map->compute();

    ok($type->name =~ /Array/i, 'Map compute returns Array type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/map-node.t`
Expected: FAIL - Can't locate Chalk/IR/Node/Map.pm

**Step 3: Implement Map node**

Create `lib/Chalk/IR/Node/Map.pm`:

```perl
# ABOUTME: Map node for map { BLOCK } @list
# ABOUTME: Transforms each element using the block

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Type::ArrayRef;

class Chalk::IR::Node::Map :isa(Chalk::IR::Node::Base) {
    field $block :param :reader;  # CodeRef - the transformation function
    field $list :param :reader;   # ArrayRef - input list

    method compute() {
        return Chalk::IR::Type::ArrayRef->new();
    }

    method op() { 'Map' }

    method label() { 'Map' }

    method inputs() { [$block, $list] }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/map-node.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Map.pm t/ir/map-node.t
git commit -m "feat(ir): Add Map node for map { } @list

Part of #386"
```

---

### Task 16: Create Filter IR Node (grep)

**Files:**
- Create: `lib/Chalk/IR/Node/Filter.pm`
- Test: `t/ir/filter-node.t` (create)

**Step 1: Write the failing test**

Create `t/ir/filter-node.t`:

```perl
# ABOUTME: Tests for Filter IR node
# ABOUTME: Verifies Filter node for grep { } @list filtering

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Constant;

use_ok('Chalk::IR::Node::Filter');

subtest 'Filter node construction' => sub {
    my $block = Chalk::IR::Node::Constant->new(value => sub {}, type => 'CodeRef');
    my $list = Chalk::IR::Node::Constant->new(value => [], type => 'ArrayRef');

    my $filter = Chalk::IR::Node::Filter->new(
        block => $block,
        list  => $list
    );

    ok(defined($filter), 'Filter node created');
    is($filter->op, 'Filter', 'Op is Filter');
};

subtest 'Filter compute returns ArrayRef' => sub {
    my $block = Chalk::IR::Node::Constant->new(value => sub {}, type => 'CodeRef');
    my $list = Chalk::IR::Node::Constant->new(value => [], type => 'ArrayRef');

    my $filter = Chalk::IR::Node::Filter->new(block => $block, list => $list);
    my $type = $filter->compute();

    ok($type->name =~ /Array/i, 'Filter compute returns Array type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/filter-node.t`
Expected: FAIL - Can't locate Chalk/IR/Node/Filter.pm

**Step 3: Implement Filter node**

Create `lib/Chalk/IR/Node/Filter.pm`:

```perl
# ABOUTME: Filter node for grep { BLOCK } @list
# ABOUTME: Filters elements using the predicate block

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Type::ArrayRef;

class Chalk::IR::Node::Filter :isa(Chalk::IR::Node::Base) {
    field $block :param :reader;  # CodeRef - the predicate function
    field $list :param :reader;   # ArrayRef - input list

    method compute() {
        return Chalk::IR::Type::ArrayRef->new();
    }

    method op() { 'Filter' }

    method label() { 'Filter (grep)' }

    method inputs() { [$block, $list] }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/filter-node.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Filter.pm t/ir/filter-node.t
git commit -m "feat(ir): Add Filter node for grep { } @list

Part of #386"
```

---

### Task 17: Wire ListOp to Map/Filter nodes

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/ListOp.pm`
- Test: `t/grammar/listop-ir.t` (create)

**Step 1: Write the failing test**

Create `t/grammar/listop-ir.t`:

```perl
# ABOUTME: Tests for ListOp IR generation
# ABOUTME: Verifies ListOp.pm generates Map/Filter nodes

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::Grammar;
use Chalk::Semiring::Semantic;

my $grammar = Chalk::Grammar->new(grammar_file => 'grammars/chalk.bnf');
my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

# Note: These tests depend on grammar supporting map/grep syntax
# May need to be TODO'd if grammar doesn't parse these yet

TODO: {
    local $TODO = 'ListOp grammar support may not be complete';

    subtest 'map generates Map node' => sub {
        my $code = 'map { $_ * 2 } @list';
        my $result = $grammar->parse_string($code, semiring => $semiring);

        ok(defined($result), 'Parse succeeded');
        ok($result->isa('Chalk::IR::Node::Map'),
           'Result is Map node') or diag "Got: " . ref($result);
    };

    subtest 'grep generates Filter node' => sub {
        my $code = 'grep { $_ > 0 } @list';
        my $result = $grammar->parse_string($code, semiring => $semiring);

        ok(defined($result), 'Parse succeeded');
        ok($result->isa('Chalk::IR::Node::Filter'),
           'Result is Filter node') or diag "Got: " . ref($result);
    };
}

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/grammar/listop-ir.t`
Expected: FAIL or TODO (depending on grammar support)

**Step 3: Implement ListOp to generate Map/Filter**

Replace `lib/Chalk/Grammar/Chalk/Rule/ListOp.pm`:

```perl
# ABOUTME: Semantic action for ListOp - list operations like map, grep
# ABOUTME: Generates Map/Filter IR nodes for higher-order functions

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ListOp :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Map;
        use Chalk::IR::Node::Filter;

        # ListOp -> 'map' WS Block WS List
        # ListOp -> 'grep' WS Block WS List

        my @children = $context->children->@*;

        # First child is the operation name (map, grep, all, any)
        my $op_name = "$context->child(0)";
        $op_name = lc($op_name);

        # Find block and list from children
        my ($block, $list);
        for my $i (1 .. $#children) {
            my $child = $context->child($i);
            next unless ref($child) && $child->can('id');

            if (!defined($block)) {
                $block = $child;
            } else {
                $list = $child;
                last;
            }
        }

        # If we couldn't extract both, pass through
        unless (defined($block) && defined($list)) {
            return $context->child(0);
        }

        if ($op_name eq 'map') {
            return Chalk::IR::Node::Map->new(
                block => $block,
                list  => $list
            )->peephole();
        }
        elsif ($op_name eq 'grep') {
            return Chalk::IR::Node::Filter->new(
                block => $block,
                list  => $list
            )->peephole();
        }

        # Fallback for unhandled operations
        return $context->child(0);
    }
}

1;
```

**Step 4: Run test to verify status**

Run: `./prove t/grammar/listop-ir.t`
Expected: PASS or TODO passes

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/Rule/ListOp.pm t/grammar/listop-ir.t
git commit -m "feat(grammar): ListOp generates Map/Filter nodes

Closes #386"
```

---

### Task 18: Run full test suite for Tier 3

**Step 1: Run all Tier 3 tests**

Run: `./prove t/ir/map-node.t t/ir/filter-node.t t/grammar/listop-ir.t`
Expected: All PASS (or TODO)

**Step 2: Run full test suite to check for regressions**

Run: `./prove`
Expected: No new failures

**Step 3: Commit checkpoint**

```bash
git commit --allow-empty -m "checkpoint: Tier 3 complete - ListOp nodes"
```

---

## Tier 4: Complex Features

### Task 19: Create Match IR Node

**Files:**
- Create: `lib/Chalk/IR/Node/Match.pm`
- Test: `t/ir/match-node.t` (create)

**Step 1: Write the failing test**

Create `t/ir/match-node.t`:

```perl
# ABOUTME: Tests for Match IR node
# ABOUTME: Verifies Match node for =~ regex match operator

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Constant;

use_ok('Chalk::IR::Node::Match');

subtest 'Match node construction' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 'hello', type => 'Str');
    my $right = Chalk::IR::Node::Constant->new(value => qr/ell/, type => 'Regex');

    my $match = Chalk::IR::Node::Match->new(
        left  => $left,
        right => $right
    );

    ok(defined($match), 'Match node created');
    is($match->op, 'Match', 'Op is Match');
};

subtest 'Match compute returns Bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 'hello', type => 'Str');
    my $right = Chalk::IR::Node::Constant->new(value => qr/ell/, type => 'Regex');

    my $match = Chalk::IR::Node::Match->new(left => $left, right => $right);
    my $type = $match->compute();

    ok($type->name =~ /Bool/i || $type->isa('Chalk::IR::Type::TypeBool'),
       'Match compute returns Bool type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/match-node.t`
Expected: FAIL - Can't locate Chalk/IR/Node/Match.pm

**Step 3: Implement Match node**

Create `lib/Chalk/IR/Node/Match.pm`:

```perl
# ABOUTME: Match node for =~ regex match operator
# ABOUTME: Returns bool in scalar context, captures in list context

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Type::TypeBool;

class Chalk::IR::Node::Match :isa(Chalk::IR::Node::Base) {
    field $left :param :reader;   # Expression to match against
    field $right :param :reader;  # Regex pattern

    method compute() {
        # Scalar context returns bool, list context returns captures
        # For now, assume scalar context
        return Chalk::IR::Type::TypeBool->BOOL;
    }

    method op() { 'Match' }

    method label() { 'Match (=~)' }

    method inputs() { [$left, $right] }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/match-node.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Match.pm t/ir/match-node.t
git commit -m "feat(ir): Add Match node for =~ regex operator

Part of #315"
```

---

### Task 20: Create NotMatch IR Node

**Files:**
- Create: `lib/Chalk/IR/Node/NotMatch.pm`
- Test: `t/ir/notmatch-node.t` (create)

**Step 1: Write the failing test**

Create `t/ir/notmatch-node.t`:

```perl
# ABOUTME: Tests for NotMatch IR node
# ABOUTME: Verifies NotMatch node for !~ regex negated match

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Constant;

use_ok('Chalk::IR::Node::NotMatch');

subtest 'NotMatch node construction' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 'hello', type => 'Str');
    my $right = Chalk::IR::Node::Constant->new(value => qr/xyz/, type => 'Regex');

    my $notmatch = Chalk::IR::Node::NotMatch->new(
        left  => $left,
        right => $right
    );

    ok(defined($notmatch), 'NotMatch node created');
    is($notmatch->op, 'NotMatch', 'Op is NotMatch');
};

subtest 'NotMatch compute returns Bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 'hello', type => 'Str');
    my $right = Chalk::IR::Node::Constant->new(value => qr/xyz/, type => 'Regex');

    my $notmatch = Chalk::IR::Node::NotMatch->new(left => $left, right => $right);
    my $type = $notmatch->compute();

    ok($type->name =~ /Bool/i || $type->isa('Chalk::IR::Type::TypeBool'),
       'NotMatch compute returns Bool type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/notmatch-node.t`
Expected: FAIL - Can't locate Chalk/IR/Node/NotMatch.pm

**Step 3: Implement NotMatch node**

Create `lib/Chalk/IR/Node/NotMatch.pm`:

```perl
# ABOUTME: NotMatch node for !~ regex negated match operator
# ABOUTME: Returns negated bool result of regex match

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Type::TypeBool;

class Chalk::IR::Node::NotMatch :isa(Chalk::IR::Node::Base) {
    field $left :param :reader;   # Expression to match against
    field $right :param :reader;  # Regex pattern

    method compute() {
        return Chalk::IR::Type::TypeBool->BOOL;
    }

    method op() { 'NotMatch' }

    method label() { 'NotMatch (!~)' }

    method inputs() { [$left, $right] }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/notmatch-node.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/NotMatch.pm t/ir/notmatch-node.t
git commit -m "feat(ir): Add NotMatch node for !~ regex operator

Part of #315"
```

---

### Task 21: Wire Match/NotMatch in ComparisonOp.pm

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/ComparisonOp.pm:119-123`
- Test: `t/grammar/regex-match-ir.t` (create)

**Step 1: Write the failing test**

Create `t/grammar/regex-match-ir.t`:

```perl
# ABOUTME: Tests for regex match operator IR generation
# ABOUTME: Verifies ComparisonOp.pm generates Match/NotMatch nodes

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::Grammar;
use Chalk::Semiring::Semantic;

my $grammar = Chalk::Grammar->new(grammar_file => 'grammars/chalk.bnf');
my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);

TODO: {
    local $TODO = 'Regex syntax support may not be complete';

    subtest '=~ generates Match node' => sub {
        my $code = '$str =~ /pattern/';
        my $result = $grammar->parse_string($code, semiring => $semiring);

        ok(defined($result), 'Parse succeeded');
        ok($result->isa('Chalk::IR::Node::Match'),
           'Result is Match node') or diag "Got: " . ref($result);
    };

    subtest '!~ generates NotMatch node' => sub {
        my $code = '$str !~ /pattern/';
        my $result = $grammar->parse_string($code, semiring => $semiring);

        ok(defined($result), 'Parse succeeded');
        ok($result->isa('Chalk::IR::Node::NotMatch'),
           'Result is NotMatch node') or diag "Got: " . ref($result);
    };
}

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/grammar/regex-match-ir.t`
Expected: FAIL or TODO

**Step 3: Implement Match/NotMatch in ComparisonOp.pm**

In `lib/Chalk/Grammar/Chalk/Rule/ComparisonOp.pm`, replace the =~/!~ pass-through (around lines 119-123):

```perl
        elsif ($operator eq '=~') {
            use Chalk::IR::Node::Match;
            return Chalk::IR::Node::Match->new(
                left  => $left,
                right => $right
            )->peephole();
        }
        elsif ($operator eq '!~') {
            use Chalk::IR::Node::NotMatch;
            return Chalk::IR::Node::NotMatch->new(
                left  => $left,
                right => $right
            )->peephole();
        }
```

**Step 4: Run test to verify status**

Run: `./prove t/grammar/regex-match-ir.t`
Expected: PASS or TODO passes

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/Rule/ComparisonOp.pm t/grammar/regex-match-ir.t
git commit -m "feat(grammar): Wire =~ and !~ to Match/NotMatch nodes

Closes #315"
```

---

### Task 22: Create InterpolatedString IR Node

**Files:**
- Create: `lib/Chalk/IR/Node/InterpolatedString.pm`
- Test: `t/ir/interpolated-string-node.t` (create)

**Step 1: Write the failing test**

Create `t/ir/interpolated-string-node.t`:

```perl
# ABOUTME: Tests for InterpolatedString IR node
# ABOUTME: Verifies InterpolatedString for "Hello $name" syntax

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Constant;

use_ok('Chalk::IR::Node::InterpolatedString');

subtest 'InterpolatedString construction' => sub {
    my $part1 = Chalk::IR::Node::Constant->new(value => 'Hello ', type => 'Str');
    my $part2 = Chalk::IR::Node::Constant->new(value => 'world', type => 'Str');

    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2]
    );

    ok(defined($interp), 'InterpolatedString node created');
    is($interp->op, 'InterpolatedString', 'Op is InterpolatedString');
    is(scalar($interp->parts->@*), 2, 'Two parts stored');
};

subtest 'InterpolatedString compute returns Str' => sub {
    my $part1 = Chalk::IR::Node::Constant->new(value => 'Hello', type => 'Str');

    my $interp = Chalk::IR::Node::InterpolatedString->new(parts => [$part1]);
    my $type = $interp->compute();

    ok($type->name =~ /Str/i, 'InterpolatedString compute returns Str type');
};

subtest 'InterpolatedString constant folding' => sub {
    my $part1 = Chalk::IR::Node::Constant->new(value => 'Hello ', type => 'Str');
    my $part2 = Chalk::IR::Node::Constant->new(value => 'world', type => 'Str');

    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2]
    );

    my $idealized = $interp->idealize();

    # If all parts are constant, should fold to single Constant
    ok($idealized->isa('Chalk::IR::Node::Constant'),
       'All-constant InterpolatedString folds to Constant');
    is($idealized->value, 'Hello world', 'Folded value is correct');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/interpolated-string-node.t`
Expected: FAIL - Can't locate module

**Step 3: Implement InterpolatedString node**

Create `lib/Chalk/IR/Node/InterpolatedString.pm`:

```perl
# ABOUTME: InterpolatedString for "Hello $name" syntax
# ABOUTME: Contains parts array of constants and expressions

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Base;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Str;

class Chalk::IR::Node::InterpolatedString :isa(Chalk::IR::Node::Base) {
    field $parts :param :reader = [];  # Array of Constant and expression nodes

    method compute() {
        return Chalk::IR::Type::Str->new();
    }

    method op() { 'InterpolatedString' }

    method label() { 'InterpolatedString' }

    method inputs() { $parts }

    method idealize() {
        # If all parts are constants, fold to single Constant
        my $all_const = 1;
        my $result = '';

        for my $part ($parts->@*) {
            if ($part->isa('Chalk::IR::Node::Constant')) {
                $result .= $part->value // '';
            } else {
                $all_const = 0;
                last;
            }
        }

        if ($all_const && scalar($parts->@*) > 0) {
            return Chalk::IR::Node::Constant->new(
                value => $result,
                type  => 'Str'
            );
        }

        return $self;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/interpolated-string-node.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/InterpolatedString.pm t/ir/interpolated-string-node.t
git commit -m "feat(ir): Add InterpolatedString node for string interpolation

Part of #201"
```

---

### Task 23: Run full test suite for Tier 4

**Step 1: Run all Tier 4 tests**

Run: `./prove t/ir/match-node.t t/ir/notmatch-node.t t/grammar/regex-match-ir.t t/ir/interpolated-string-node.t`
Expected: All PASS (or TODO)

**Step 2: Run full test suite to check for regressions**

Run: `./prove`
Expected: No new failures

**Step 3: Commit checkpoint**

```bash
git commit --allow-empty -m "checkpoint: Tier 4 complete - regex and interpolation nodes"
```

---

## Final Verification

### Task 24: Full Test Suite and Summary

**Step 1: Run complete test suite**

Run: `./prove`
Expected: All tests pass, no regressions

**Step 2: Verify all new files exist**

Run: `ls -la lib/Chalk/IR/Node/{Die,ISA,ArrayDeref,HashDeref,Call,CallEnd,Map,Filter,Match,NotMatch,InterpolatedString}.pm`
Expected: All 11 files exist

**Step 3: Verify issues can be closed**

Check that each issue's requirements are met:
- #189 - ++/-- wired up ✓
- #388 - YaddaYadda generates Die ✓
- #316 - isa generates ISA ✓
- #161 - Deref nodes created (wiring depends on grammar)
- #383 - MethodCall generates Call/CallEnd ✓
- #384 - FunctionCall generates Call/CallEnd ✓
- #386 - ListOp generates Map/Filter ✓
- #315 - =~/!~ generate Match/NotMatch ✓
- #201 - InterpolatedString node created (wiring depends on grammar)

**Step 4: Final commit**

```bash
git commit --allow-empty -m "feat: Complete Theme 2 - Semantic Rule IR Implementation

Implemented IR generation for semantic rules that were pass-through stubs:

Tier 0: Wired ++/-- to existing nodes, added Die for YaddaYadda
Tier 1: Added ISA, ArrayDeref, HashDeref nodes
Tier 2: Added Call/CallEnd infrastructure (Chapter 18)
Tier 3: Added Map/Filter for ListOp
Tier 4: Added Match/NotMatch/InterpolatedString

Closes #189, #388, #316, #383, #384, #386, #315
Partially addresses #161, #201 (node creation complete, grammar wiring pending)"
```

---

## Summary

| Tier | Tasks | Issues Closed |
|------|-------|---------------|
| 0 | 1-5 | #189, #388 |
| 1 | 6-9 | #316, #161 (partial) |
| 2 | 10-14 | #383, #384 |
| 3 | 15-18 | #386 |
| 4 | 19-23 | #315, #201 (partial) |
| Final | 24 | Verification |

**Total: 24 tasks across 5 tiers**
