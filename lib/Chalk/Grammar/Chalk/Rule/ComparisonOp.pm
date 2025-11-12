# ABOUTME: Semantic action for ComparisonOp - flattened comparison and regex match operators
# ABOUTME: Handles comparison (>, <, ==, !=, isa) and regex match (=~, !~) with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ComparisonOp :isa(Chalk::GrammarRule) {
    # Grammar: ComparisonOp -> Expression WS_OPT %COMPARE_OP% WS_OPT Expression
    # Child indices for binary comparison operations
    use constant {
        LEFT_EXPR  => 0,  # Left operand (Expression)
        OPERATOR   => 2,  # Comparison operator
        RIGHT_EXPR => 4,  # Right operand (Expression)
    };
    method evaluate($context) {
        # ComparisonOp -> StringOp (pass-through)
        # ComparisonOp -> ComparisonOp WS_OPT %NUM_COMPARE_OP% WS_OPT StringOp
        # ComparisonOp -> ComparisonOp WS_OPT %STRING_COMPARE_OP% WS_OPT StringOp
        # ComparisonOp -> ComparisonOp WS_OPT 'isa' WS_OPT QualifiedIdentifier
        # ComparisonOp -> ComparisonOp WS_OPT %REGEX_MATCH_OP% WS_OPT StringOp

        # Count children to determine which alternative matched
        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through StringOp
            return $context->child(LEFT_EXPR);
        }

        # For binary operation: check OPERATOR child for the operator
        return $context->child(LEFT_EXPR) unless defined $children[OPERATOR];
        my $op_child = $children[OPERATOR]->extract;
        return $context->child(LEFT_EXPR) unless defined $op_child && !ref($op_child);

        my $operator = $op_child;
        my $builder = $context->env->{ir_builder};
        return $context->child(LEFT_EXPR) unless $builder;

        # Get left and right operands
        my $left = $context->child(LEFT_EXPR);
        my $right = $context->child(RIGHT_EXPR);

        # Validate that we got IR nodes
        return $left unless (blessed($left) && $left->can('id'));
        return $left unless (blessed($right) && $right->can('id'));

        # Build appropriate IR node based on operator
        # Comparison operators
        if ($operator eq '>' || $operator eq 'gt') {
            return $builder->build_greater_node($left, $right);
        } elsif ($operator eq '<' || $operator eq 'lt') {
            return $builder->build_less_node($left, $right);
        } elsif ($operator eq '==' || $operator eq 'eq') {
            return $builder->build_equal_node($left, $right);
        } elsif ($operator eq '>=' || $operator eq 'ge') {
            return $builder->build_greater_or_equal_node($left, $right);
        } elsif ($operator eq '<=' || $operator eq 'le') {
            return $builder->build_less_or_equal_node($left, $right);
        } elsif ($operator eq '!=' || $operator eq 'ne') {
            return $builder->build_not_equal_node($left, $right);
        }
        # Regex match operators (=~, !~)
        # TODO: implement when regex match IR nodes are available
        elsif ($operator eq '=~' || $operator eq '!~') {
            # For now, just pass through left side
            return $left;
        }

        return $context->child(LEFT_EXPR);
    }
}

1;
