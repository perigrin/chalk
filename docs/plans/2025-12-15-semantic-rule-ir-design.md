# Theme 2: Semantic Rule IR Implementation Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement IR generation for semantic rules that are currently pass-through stubs, enabling full language functionality for function calls, operators, and expressions.

**Architecture:** Tier-ordered sequential implementation following Sea of Nodes Chapter 18 patterns for call infrastructure. Each tier builds on the previous, with quick wins first to unblock tests.

**Tech Stack:** Perl 5.42.0, existing IR node patterns, Sea of Nodes IR architecture.

**Related Issues:** #189, #388, #316, #161, #383, #384, #386, #315, #201

---

## Overview

### Dependency Tiers

| Tier | Issues | Description | Effort |
|------|--------|-------------|--------|
| 0 | #189, #388 | Quick wins - wire existing nodes, simple Die | 1-2 days |
| 1 | #316, #161 | Simple new nodes - ISA, dereference | 2-3 days |
| 2 | #383, #384 | Call infrastructure - Chapter 18 pattern | 3-5 days |
| 3 | #386 | Higher-order functions - depends on Tier 2 | 2-3 days |
| 4 | #315, #201 | Complex features - regex, interpolation | 5-7 days |

**Total Effort:** ~15-20 days

### New IR Nodes Required (10 total)

| Node | Tier | Purpose |
|------|------|---------|
| Die | 0 | Runtime panic for `...` operator |
| ISA | 1 | Type checking `isa` operator |
| ArrayDeref | 1 | `@$ref` prefix dereference |
| HashDeref | 1 | `%$ref` prefix dereference |
| Call | 2 | Function/method invocation |
| CallEnd | 2 | Call completion + projections |
| Map | 3 | `map { } @list` transformation |
| Filter | 3 | `grep { } @list` filtering |
| Match | 4 | `=~` regex match operator |
| InterpolatedString | 4 | `"Hello $name"` string interpolation |

### Semantic Rules Modified (8 total)

- `Unary.pm` - Wire up ++/-- to existing nodes
- `YaddaYadda.pm` - Generate Die node
- `ComparisonOp.pm` - Add ISA, Match, NotMatch
- `FunctionCall.pm` - Generate Call/CallEnd
- `MethodCall.pm` - Generate Call/CallEnd with receiver
- `ListOp.pm` - Generate Map/Filter/All/Any
- Dereference rule - Generate ArrayDeref/HashDeref
- `Literal.pm` - Handle interpolated strings

---

## Tier 0: Quick Wins

### Task 0.1: Wire up Increment/Decrement (#189)

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/Unary.pm`
- Test: `t/grammar/increment-decrement.t` (create or extend)

**Current State:** IR nodes exist (`PreIncrement`, `PreDecrement`, `PostIncrement`, `PostDecrement`) but `Unary.pm` just passes through.

**Implementation:**

In `Unary.pm`, replace pass-through for prefix operators:

```perl
elsif ($operator eq '++') {
    use Chalk::IR::Node::PreIncrement;
    return Chalk::IR::Node::PreIncrement->new(operand => $operand)->peephole();
}
elsif ($operator eq '--') {
    use Chalk::IR::Node::PreDecrement;
    return Chalk::IR::Node::PreDecrement->new(operand => $operand)->peephole();
}
```

For postfix in the `@children == 2` block:

```perl
if ($str_val eq '++') {
    use Chalk::IR::Node::PostIncrement;
    my $var = $context->child(0);
    return Chalk::IR::Node::PostIncrement->new(operand => $var)->peephole();
}
elsif ($str_val eq '--') {
    use Chalk::IR::Node::PostDecrement;
    my $var = $context->child(0);
    return Chalk::IR::Node::PostDecrement->new(operand => $var)->peephole();
}
```

**Done Criteria:**
- [ ] Tests pass for `$x++`, `$x--`, `++$x`, `--$x`
- [ ] IR graph shows correct increment/decrement nodes

---

### Task 0.2: YaddaYadda Die Node (#388)

**Files:**
- Create: `lib/Chalk/IR/Node/Die.pm`
- Modify: `lib/Chalk/Grammar/Chalk/Rule/YaddaYadda.pm`
- Test: `t/grammar/yaddayadda.t`

**Implementation:**

Create `lib/Chalk/IR/Node/Die.pm`:

```perl
# ABOUTME: Die node represents runtime panic/die
# ABOUTME: Used for yada-yada operator (...) and explicit die statements

use 5.42.0;
use experimental 'class';

class Chalk::IR::Node::Die :isa(Chalk::IR::Node::Base) {
    field $message :param :reader = 'Died';

    method compute() {
        # Die is a control flow terminator - returns Bottom
        return Chalk::IR::Type::Bottom->new();
    }

    method op() { 'Die' }
}

1;
```

Update `YaddaYadda.pm`:

```perl
method evaluate($context) {
    use Chalk::IR::Node::Die;
    return Chalk::IR::Node::Die->new(
        message => 'Unimplemented'
    )->peephole();
}
```

**Done Criteria:**
- [ ] `...` generates Die node in IR
- [ ] Tests verify Die node with correct message

---

## Tier 1: Simple New Nodes

### Task 1.1: ISA Operator (#316)

**Files:**
- Create: `lib/Chalk/IR/Node/ISA.pm`
- Modify: `lib/Chalk/Grammar/Chalk/Rule/ComparisonOp.pm`
- Test: `t/grammar/isa-operator.t`

**Implementation:**

Create `lib/Chalk/IR/Node/ISA.pm`:

```perl
# ABOUTME: ISA node for type checking operator
# ABOUTME: Returns boolean indicating if value is instance of type

use 5.42.0;
use experimental 'class';

class Chalk::IR::Node::ISA :isa(Chalk::IR::Node::Base) {
    field $operand :param :reader;    # The value to check
    field $type_name :param :reader;  # The type name (string or type object)

    method compute() {
        return Chalk::IR::Type::TypeBool->BOOL;
    }

    method op() { 'ISA' }
}

1;
```

In `ComparisonOp.pm`, add case for `isa`:

```perl
elsif ($operator eq 'isa') {
    use Chalk::IR::Node::ISA;
    return Chalk::IR::Node::ISA->new(
        operand   => $left,
        type_name => $right
    )->peephole();
}
```

**Done Criteria:**
- [ ] `$obj isa SomeClass` generates ISA node
- [ ] Type inference returns TypeBool

---

### Task 1.2: ListDereference (#161)

**Files:**
- Create: `lib/Chalk/IR/Node/ArrayDeref.pm`
- Create: `lib/Chalk/IR/Node/HashDeref.pm`
- Modify or create: Grammar rule for `@$ref`, `%$ref` syntax
- Test: `t/grammar/list-dereference.t`

**Implementation:**

Create `lib/Chalk/IR/Node/ArrayDeref.pm`:

```perl
# ABOUTME: ArrayDeref for @$ref prefix dereference syntax
# ABOUTME: Dereferences a reference to get array contents

use 5.42.0;
use experimental 'class';

class Chalk::IR::Node::ArrayDeref :isa(Chalk::IR::Node::Base) {
    field $ref :param :reader;  # The reference to dereference

    method compute() {
        return Chalk::IR::Type::Array->new();
    }

    method op() { 'ArrayDeref' }
}

1;
```

Similar pattern for `HashDeref.pm` returning `Chalk::IR::Type::Hash`.

**Done Criteria:**
- [ ] `@$arrayref` generates ArrayDeref node
- [ ] `%$hashref` generates HashDeref node

---

## Tier 2: Call Infrastructure

### Task 2.1: Call and CallEnd Nodes (#383, #384)

**Files:**
- Create: `lib/Chalk/IR/Node/Call.pm`
- Create: `lib/Chalk/IR/Node/CallEnd.pm`
- Test: `t/ir/call-nodes.t`

**Architecture (Sea of Nodes Chapter 18):**

```
CallNode
├── inputs: [ctrl, mem, arg0, arg1, ..., callee]
├── callee: ConstantNode (for named) or expression
└── rpc: unique call-site identifier

CallEndNode
├── inputs: [call_node, linked_functions...]
└── projections: ctrl, mem, return_value
```

**Simplified Implementation (Phase A):**

Create `lib/Chalk/IR/Node/Call.pm`:

```perl
# ABOUTME: Call node for function/method invocation
# ABOUTME: Sea of Nodes Chapter 18 - simplified initial implementation

use 5.42.0;
use experimental 'class';

class Chalk::IR::Node::Call :isa(Chalk::IR::Node::Base) {
    field $callee :param :reader;      # Function name or expression
    field $args :param :reader = [];   # Argument IR nodes
    field $receiver :param :reader;    # For method calls, the object/class
    field $rpc :param :reader;         # Return program counter (call-site ID)

    my $rpc_counter = 0;

    sub generate_rpc() {
        return 'rpc_' . $rpc_counter++;
    }

    method compute() {
        # Return type depends on callee - Any for now
        # Future: look up function signature for return type
        return Chalk::IR::Type::Any->new();
    }

    method op() { 'Call' }
}

1;
```

Create `lib/Chalk/IR/Node/CallEnd.pm`:

```perl
# ABOUTME: CallEnd node follows each Call
# ABOUTME: Provides projections for control, memory, return value

use 5.42.0;
use experimental 'class';

class Chalk::IR::Node::CallEnd :isa(Chalk::IR::Node::Base) {
    field $call :param :reader;  # The CallNode this ends

    method compute() {
        # Propagate return type from call
        return $call->compute();
    }

    method op() { 'CallEnd' }
}

1;
```

**Done Criteria:**
- [ ] Call and CallEnd nodes can be constructed
- [ ] RPC generation produces unique identifiers
- [ ] Basic peephole optimization works

---

### Task 2.2: FunctionCall Semantic Rule (#384)

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/FunctionCall.pm`
- Test: `t/grammar/function-call-ir.t`

**Implementation:**

```perl
method evaluate($context) {
    use Chalk::IR::Node::Call;
    use Chalk::IR::Node::CallEnd;

    # FunctionCall -> Identifier '(' WS_OPT ExpressionList WS_OPT ')'
    # FunctionCall -> Identifier '(' WS_OPT ')'

    # Extract function name
    my $callee = $context->child(0);

    # Extract arguments from ExpressionList if present
    my @args;
    for my $i (1 .. scalar(@{$context->children}) - 1) {
        my $child = $context->child($i);
        if (ref($child) && $child->can('id')) {
            push @args, $child;
        }
    }

    my $call = Chalk::IR::Node::Call->new(
        callee => "$callee",  # Stringify identifier
        args   => \@args,
        rpc    => Chalk::IR::Node::Call::generate_rpc(),
    );

    return Chalk::IR::Node::CallEnd->new(call => $call)->peephole();
}
```

**Done Criteria:**
- [ ] `foo()` generates Call + CallEnd
- [ ] `bar(1, 2, 3)` passes arguments correctly
- [ ] RPC is unique per call site

---

### Task 2.3: MethodCall Semantic Rule (#383)

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/Rule/MethodCall.pm`
- Test: `t/grammar/method-call-ir.t`

**Implementation:**

```perl
method evaluate($context) {
    use Chalk::IR::Node::Call;
    use Chalk::IR::Node::CallEnd;

    # MethodCall -> Variable '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
    # MethodCall -> QualifiedIdentifier '->' Identifier '(' ... ')'

    my @children = $context->children->@*;

    # Find receiver (first IR node)
    my $receiver;
    for my $child (@children) {
        my $evaled = $context->child($children[$_]);
        if (ref($evaled) && $evaled->can('id')) {
            $receiver = $evaled;
            last;
        }
    }

    # Find method name (identifier after ->)
    my $method_name;
    my $found_arrow = 0;
    for my $i (0 .. $#children) {
        my $child = $children[$i];
        if ("$child" eq '->') {
            $found_arrow = 1;
            next;
        }
        if ($found_arrow && !defined($method_name)) {
            $method_name = "$child";
            last;
        }
    }

    # Extract arguments
    my @args = _extract_arguments($context);

    my $call = Chalk::IR::Node::Call->new(
        callee   => $method_name,
        receiver => $receiver,
        args     => \@args,
        rpc      => Chalk::IR::Node::Call::generate_rpc(),
    );

    return Chalk::IR::Node::CallEnd->new(call => $call)->peephole();
}
```

**Done Criteria:**
- [ ] `$obj->method()` generates Call with receiver
- [ ] `Class->new()` generates Call with class as receiver
- [ ] Arguments passed correctly

---

## Tier 3: Higher-Order Functions

### Task 3.1: ListOp Nodes (#386)

**Files:**
- Create: `lib/Chalk/IR/Node/Map.pm`
- Create: `lib/Chalk/IR/Node/Filter.pm`
- Create: `lib/Chalk/IR/Node/All.pm`
- Create: `lib/Chalk/IR/Node/Any.pm`
- Modify: `lib/Chalk/Grammar/Chalk/Rule/ListOp.pm`
- Test: `t/grammar/listop-ir.t`

**Implementation:**

Create `lib/Chalk/IR/Node/Map.pm`:

```perl
# ABOUTME: Map node for map { BLOCK } @list
# ABOUTME: Transforms each element using the block

use 5.42.0;
use experimental 'class';

class Chalk::IR::Node::Map :isa(Chalk::IR::Node::Base) {
    field $block :param :reader;  # CodeRef - the transformation function
    field $list :param :reader;   # ArrayRef - input list

    method compute() {
        return Chalk::IR::Type::ArrayRef->new();
    }

    method op() { 'Map' }
}

1;
```

Similar for Filter (grep), All, Any - with All/Any returning TypeBool.

Update `ListOp.pm`:

```perl
method evaluate($context) {
    my $op_name = $context->child(0);
    my $op_str = "$op_name";

    my $block = _extract_block($context);
    my $list = _extract_list($context);

    if ($op_str eq 'map') {
        use Chalk::IR::Node::Map;
        return Chalk::IR::Node::Map->new(
            block => $block,
            list  => $list
        )->peephole();
    }
    elsif ($op_str eq 'grep') {
        use Chalk::IR::Node::Filter;
        return Chalk::IR::Node::Filter->new(
            block => $block,
            list  => $list
        )->peephole();
    }
    # ... all, any similar
}
```

**Done Criteria:**
- [ ] `map { $_ * 2 } @list` generates Map node
- [ ] `grep { $_ > 0 } @list` generates Filter node
- [ ] Type inference correct (ArrayRef for map/grep, Bool for all/any)

---

## Tier 4: Complex Features

### Task 4.1: Regex Match Operators (#315)

**Files:**
- Create: `lib/Chalk/IR/Node/Match.pm`
- Create: `lib/Chalk/IR/Node/NotMatch.pm`
- Modify: `lib/Chalk/Grammar/Chalk/Rule/ComparisonOp.pm`
- Test: `t/grammar/regex-match-ir.t`

**Note:** Full regex execution requires #157 (regex engine). These nodes enable syntax and type flow.

**Implementation:**

Create `lib/Chalk/IR/Node/Match.pm`:

```perl
# ABOUTME: Match node for =~ regex match operator
# ABOUTME: Returns bool in scalar context, captures in list context

use 5.42.0;
use experimental 'class';

class Chalk::IR::Node::Match :isa(Chalk::IR::Node::Base) {
    field $left :param :reader;   # Expression to match against
    field $right :param :reader;  # Regex pattern

    method compute() {
        # Scalar context returns bool, list context returns captures
        # For now, assume scalar context
        return Chalk::IR::Type::TypeBool->BOOL;
    }

    method op() { 'Match' }
}

1;
```

NotMatch is similar but represents `!~`.

Update `ComparisonOp.pm`:

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

**Done Criteria:**
- [ ] `$str =~ /pattern/` generates Match node
- [ ] `$str !~ /pattern/` generates NotMatch node
- [ ] Type inference returns Bool

---

### Task 4.2: Interpolated Strings (#201)

**Files:**
- Create: `lib/Chalk/IR/Node/InterpolatedString.pm`
- Modify: String literal handling in grammar
- Test: `t/grammar/interpolated-string-ir.t`

**Implementation:**

Create `lib/Chalk/IR/Node/InterpolatedString.pm`:

```perl
# ABOUTME: InterpolatedString for "Hello $name" syntax
# ABOUTME: Contains parts array of constants and expressions

use 5.42.0;
use experimental 'class';

class Chalk::IR::Node::InterpolatedString :isa(Chalk::IR::Node::Base) {
    field $parts :param :reader = [];  # Array of Constant and expression nodes

    method compute() {
        return Chalk::IR::Type::Str->new();
    }

    method op() { 'InterpolatedString' }

    method idealize() {
        my $self = shift;

        # If all parts are constants, fold to single Constant
        my $all_const = 1;
        my $result = '';
        for my $part ($self->parts->@*) {
            if ($part isa Chalk::IR::Node::Constant) {
                $result .= $part->value;
            } else {
                $all_const = 0;
                last;
            }
        }

        if ($all_const) {
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

**Done Criteria:**
- [ ] `"Hello $name"` generates InterpolatedString with parts
- [ ] Constant folding works for all-constant strings
- [ ] Type inference returns Str

---

## Summary

This design provides a complete path from quick wins (Tier 0) through complex features (Tier 4), following the tier-ordered sequential approach. The Call infrastructure in Tier 2 is the critical foundation that unblocks both ListOp (Tier 3) and the Stage 0 milestone.

### Success Criteria

- [ ] All 10 issues addressed (#189, #388, #316, #161, #383, #384, #386, #315, #201, #7)
- [ ] New IR nodes follow existing patterns (peephole, compute, etc.)
- [ ] Semantic rules generate proper IR instead of pass-through
- [ ] Tests verify IR generation for each feature
- [ ] No regressions in existing functionality

### References

- Sea of Nodes Chapter 18: https://github.com/SeaOfNodes/Simple/blob/main/chapter18/README.md
- Existing pattern: `lib/Chalk/Grammar/Chalk/Rule/ArithmeticOp.pm`
- IR node base: `lib/Chalk/IR/Node/Base.pm`
