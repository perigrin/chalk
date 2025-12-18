# Ternary Operator Implementation Design

## Overview

Implement the ternary conditional operator (`$cond ? $true_expr : $false_expr`) by generating If/Region/Phi IR nodes directly in the semantic action.

**Related Issue:** #399

## Design Decision

**Keep separate from ConditionalStatement** - Ternary generates its own If/Region/Phi nodes rather than sharing code with ConditionalStatement.pm.

**Rationale:**
- Ternary is expression-only (~30 lines), ConditionalStatement handles statements (300+ lines)
- No scope manipulation, statement wiring, or early return tracking needed
- Lower risk than refactoring ConditionalStatement
- Can extract shared helper later if patterns emerge

## IR Structure

```
         condition
            │
         [If node]
          /     \
    [IfTrue]   [IfFalse]
    (Proj 0)   (Proj 1)
        │          │
   true_expr  false_expr
        \         /
        [Region]
            │
      [Phi node]
       (result)
```

## Implementation

### File: `lib/Chalk/Grammar/Chalk/Rule/Ternary.pm`

```perl
method evaluate($context) {
    use Chalk::IR::Node::If;
    use Chalk::IR::Node::Proj;
    use Chalk::IR::Node::Region;
    use Chalk::IR::Node::Phi;

    my @children = $context->children->@*;

    # Pass-through case: just LogicalOr (no ? :)
    if (@children == 1) {
        return $context->child(0);
    }

    # Full ternary: LogicalOr '?' Expression ':' Ternary
    # Find condition, true_expr, false_expr by scanning children

    my $condition = $context->child(0);  # LogicalOr

    # Find expressions after '?' and ':'
    my ($true_expr, $false_expr);
    my $found_question = 0;
    my $found_colon = 0;

    for my $i (0 .. $#children) {
        my $child = $children[$i]->extract;
        my $str = defined($child) ? "$child" : '';

        if ($str eq '?') {
            $found_question = 1;
            next;
        }
        if ($str eq ':') {
            $found_colon = 1;
            next;
        }

        # After '?', first IR node is true_expr
        if ($found_question && !$true_expr) {
            my $val = $context->child($i);
            if (blessed($val) && $val->can('id')) {
                $true_expr = $val;
            }
        }

        # After ':', first IR node is false_expr
        if ($found_colon && !$false_expr) {
            my $val = $context->child($i);
            if (blessed($val) && $val->can('id')) {
                $false_expr = $val;
            }
        }
    }

    die "Ternary: missing true expression" unless $true_expr;
    die "Ternary: missing false expression" unless $false_expr;

    # Create If node
    my $if_node = Chalk::IR::Node::If->new(condition => $condition);

    # Create Proj nodes for branches
    my $if_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index  => 0,
        label  => 'IfTrue',
        source => $if_node,
    );
    my $if_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index  => 1,
        label  => 'IfFalse',
        source => $if_node,
    );

    # Create Region merging both branches
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$if_true->id, $if_false->id],
    );

    # Create Phi to select result value
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs    => [$region->id, $true_expr->id, $false_expr->id],
    );

    return $phi;
}
```

## Test Plan

1. **Basic ternary**: `1 ? 2 : 3` → returns 2
2. **False condition**: `0 ? 2 : 3` → returns 3
3. **Variable condition**: `$x ? $a : $b`
4. **Nested ternary**: `$a ? $b ? 1 : 2 : 3` (right-associative)
5. **IR structure**: Verify If/Proj/Region/Phi nodes created correctly

## Files Affected

- `lib/Chalk/Grammar/Chalk/Rule/Ternary.pm` - Main implementation
- `t/grammar/ternary.t` - New test file
