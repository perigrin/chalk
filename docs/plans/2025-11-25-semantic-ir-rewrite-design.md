# Semantic/IR Rewrite Design

**Date:** 2025-11-25
**Status:** Draft
**Goal:** Simplify IR construction by following the AST semiring pattern - immutable nodes built during parsing, no Builder intermediary.

## Problem Statement

The current IR construction has accumulated complexity:
- Deferred materialization with pending nodes
- Content-addressable ID lookups during parsing
- Graph clearing between Earley parser completions
- IR::Builder as intermediary between Rules and Nodes
- Mixed ID-based and direct reference patterns

The AST semiring is simpler: immutable tree nodes created during parsing with direct child references. The IR should follow this pattern.

## Scope

**Rewrite:**
- Semantic semiring
- Semantic Actions in Rule classes
- IR::Builder (delete entirely)
- IR::Node classes (simplify)
- CEK interpreter (defer until structure is validated)

**Keep:**
- Content-addressable IDs
- Polymorphic IR::Node subclasses
- Semantic Actions in Rules pattern
- IR::Node::Scope for SSA tracking

## Design

### Node Structure

Nodes use simple constructors with content-addressable IDs computed in field declarations:

```perl
class IR::Node::Constant :isa(IR::Node::Base) {
    field $type :param :reader;
    field $value :param :reader;
    field $id :reader = "const_${type}_${value}";
}

class IR::Node::Add :isa(IR::Node::Base) {
    field $left :param :reader;
    field $right :param :reader;
    field $id :reader = "add_" . $left->id . "_" . $right->id;
}
```

### Node Categories

**Pure data nodes** (no control edges):
- Constant, Add, Sub, Mul, Div, Negate, Not
- Comparison: GT, LT, EQ, NE, LE, GE
- StrConcat, NewArray, NewHash

**Control nodes** (have control predecessor):
- Start - entry point, no predecessor
- Store - variable assignment, carries value reference
- If - branch on condition
- Proj - projection from If (true/false paths)
- Region - control flow merge point
- Return - exit point, carries value reference

**SSA merge:**
- Phi - references Region + alternative values from branches

### Store Node

Store sits in the control chain and carries a value reference:

```perl
class IR::Node::Store :isa(IR::Node::Base) {
    field $control :param :reader;  # Control predecessor
    field $var :param :reader;      # Variable name
    field $value :param :reader;    # Value node (direct reference)
    field $id :reader = "store_${var}_" . $control->id . "_" . $value->id;
}
```

### Semantic Actions

Rules directly construct IR nodes:

```perl
class Chalk::Grammar::Chalk::Rule::Integer :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my $digits = $context->child(0);
        return Chalk::IR::Node::Constant->new(
            type  => 'Int',
            value => $digits,
        );
    }
}

class Chalk::Grammar::Chalk::Rule::Assignment :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my $var_name = ...;
        my $value = $context->child(2);
        my $scope = $context->env->{scope};
        my $control = $scope->current_control;

        my $store = Chalk::IR::Node::Store->new(
            control => $control,
            var     => $var_name,
            value   => $value,
        );

        $scope->set_current_control($store);
        $scope->define($var_name, $value);

        return $store;
    }
}
```

### Program Rule

Finalizes IR with Start/Return:

```perl
class Chalk::Grammar::Chalk::Rule::Program :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my $scope = $context->env->{scope};

        # Create Start node
        my $start = Chalk::IR::Node::Start->new(label => 'main');
        $scope->set_current_control($start);

        # Evaluate statements (updates current_control)
        my $stmt_list = $context->child(1);
        my $final_stmt = $stmt_list->[-1];

        # Get final value (for implicit return)
        my $final_value = $final_stmt->can('value')
            ? $final_stmt->value
            : $final_stmt;

        # Create Return
        my $return = Chalk::IR::Node::Return->new(
            control => $scope->current_control,
            value   => $final_value,
        );

        return $return;  # Graph root
    }
}
```

### Conditionals and Phi

```perl
class Chalk::Grammar::Chalk::Rule::ConditionalStatement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my $condition = $context->child(...);
        my $scope = $context->env->{scope};

        my $before = $scope->snapshot();

        # True branch
        my $true_value = $context->child(...);
        my $true_scope = $scope->snapshot();

        # Restore and evaluate false branch
        $scope->restore($before);
        my $false_value = $context->child(...);
        my $false_scope = $scope->snapshot();

        # Control flow nodes
        my $if = Chalk::IR::Node::If->new(condition => $condition);
        my $if_true = Chalk::IR::Node::Proj->new(control => $if, index => 0);
        my $if_false = Chalk::IR::Node::Proj->new(control => $if, index => 1);
        my $region = Chalk::IR::Node::Region->new(
            controls => [$if_true, $if_false],
        );

        # Phi nodes for modified variables
        for my $var ($scope->modified_vars($before)) {
            my $phi = Chalk::IR::Node::Phi->new(
                region => $region,
                values => [$true_scope->get($var), $false_scope->get($var)],
            );
            $scope->define($var, $phi);
        }

        $scope->set_current_control($region);
        return $region;
    }
}
```

### Semantic Semiring

```perl
class Chalk::Semiring::Semantic {
    field $grammar :param :reader;
    field $env :param :reader = {};

    ADJUST {
        $env->{scope} //= Chalk::IR::Node::Scope->new();
    }

    method evaluate($rule_name, $context) {
        my $rule_class = "Chalk::Grammar::Chalk::Rule::$rule_name";
        if ($rule_class->can('evaluate')) {
            my $rule = $rule_class->new();
            return $rule->evaluate($context);
        }
        return $context->child(0);
    }
}
```

## Example: `my $x = 42;`

**IR Structure:**
```
Return
├── control: Store
│             ├── control: Start(main)
│             ├── var: "x"
│             └── value: Constant(Int, 42)
└── value: Constant(Int, 42)
```

**Control chain:** Start → Store → Return
**Data flow:** Return.value → Constant (direct reference)

## Validation

Compare generated IR against:
1. The IR corpus
2. Sea of Nodes tutorial graph structures

## What Gets Deleted

- `lib/Chalk/IR/Builder.pm` and all Builder/*.pm helpers
- Graph container usage during parsing
- Deferred materialization / pending nodes mechanism
- `clear_pending()`, `materialize_pending_nodes()`

## What Gets Simplified

- IR::Node classes - simple constructors, ID in field declaration
- Semantic Actions - direct node construction
- Scope - tracks SSA bindings + current control

## Migration Path

1. Create new simplified IR::Node classes
2. Update Semantic semiring to provide scope in env
3. Update Rule semantic actions one by one
4. Delete IR::Builder
5. Update/rewrite tests against corpus
6. Rewrite CEK interpreter (later)
