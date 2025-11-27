# ABOUTME: Semantic action for LogicalOp - flattened logical operators
# ABOUTME: Handles logical OR (||, or, //) and AND (&&, and) operators with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::LogicalOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        use Chalk::IR::Node::And;
        use Chalk::IR::Node::Or;
        use Chalk::IR::Node::DefinedOr;

        # Grammar: LogicalOp -> ComparisonOp (pass-through)
        # LogicalOp -> LogicalOp WS_OPT '||' WS_OPT ComparisonOp
        # LogicalOp -> LogicalOp WS_OPT 'or' WS_OPT ComparisonOp
        # LogicalOp -> LogicalOp WS_OPT '//' WS_OPT ComparisonOp
        # LogicalOp -> LogicalOp WS_OPT '&&' WS_OPT ComparisonOp
        # LogicalOp -> LogicalOp WS_OPT 'and' WS_OPT ComparisonOp
        # But WS_OPT may be filtered out, so we get either 3 or 5 children
        # Search for the operator dynamically instead of hardcoding indices

        # Count children to determine which alternative matched
        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through ComparisonOp
            return $context->child(0);
        }

        # Find the operator by searching through children
        # Operators may be Token objects or plain strings, so stringify and check
        my $operator_idx;
        my $operator;

        for my $i (0 .. $#children) {
            my $child = $context->child($i);
            if (defined $child) {
                my $str_val = "$child";  # Stringify (works for both Token objects and strings)
                # Match logical operators: ||, or, //, &&, and
                if ($str_val =~ qr/^(\|\||or|\/\/|&&|and)$/) {
                    $operator = $str_val;
                    $operator_idx = $i;
                    last;
                }
            }
        }

        # If no operator found, return first child
        return $context->child(0) unless defined $operator;

        # Extract left operand (first IR node before operator)
        my $left;
        for my $i (0 .. $operator_idx - 1) {
            my $child = $context->child($i);
            if (ref($child) && $child->can('id')) {
                $left = $child;
                last;
            }
        }

        # Extract right operand (first IR node after operator)
        my $right;
        for my $i ($operator_idx + 1 .. $#children) {
            my $child = $context->child($i);
            if (ref($child) && $child->can('id')) {
                $right = $child;
                last;
            }
        }

        # Validate that we got both operands
        return $context->child(0) unless $left && $right;

        # Build appropriate IR node based on operator
        # Logical operators
        if ($operator eq '||' || $operator eq 'or') {
            return Chalk::IR::Node::Or->new(left => $left, right => $right);
        } elsif ($operator eq '//') {
            return Chalk::IR::Node::DefinedOr->new(left => $left, right => $right);
        } elsif ($operator eq '&&' || $operator eq 'and') {
            return Chalk::IR::Node::And->new(left => $left, right => $right);
        }

        return $context->child(0);
    }
}

1;
