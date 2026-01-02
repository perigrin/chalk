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

        # Find the operator by scanning children - expression structure varies
        # because WS_OPT may or may not be present, so we can't use fixed indices
        my $operator_idx;
        my $operator;

        for my $i (0 .. $#children) {
            my $child = $context->child($i);
            # Check for any Token (not just Token::Operator) since grammar uses
            # literal strings '&&', '||', etc. instead of token patterns
            if (blessed($child) && $child->isa('Chalk::Grammar::Token')) {
                my $value = "$child";  # Stringify to get token value
                # Only accept logical operator tokens
                if ($value =~ /^(&&|and|\|\||or|\/\/)$/) {
                    $operator = $value;
                    $operator_idx = $i;
                    last;
                }
            }
        }

        # If no operator found with multiple children, this is a bug
        unless (defined $operator) {
            my @children_debug = map { defined $_ ? "$_" : '<undef>' } map { $_->extract } @children;
            die "LogicalOp matched with " . scalar(@children) . " children but no operator found: [@children_debug]";
        }

        # Extract left operand (first IR node before operator)
        my $left;
        for my $i (0 .. $operator_idx - 1) {
            my $child = $context->child($i);
            if (blessed($child) && $child->can('id')) {
                $left = $child;
                last;
            }
        }

        # Extract right operand (first IR node after operator)
        my $right;
        for my $i ($operator_idx + 1 .. $#children) {
            my $child = $context->child($i);
            if (blessed($child) && $child->can('id')) {
                $right = $child;
                last;
            }
        }

        # Validate that we got both operands - die if not
        unless ($left && $right) {
            my @children_debug = map { defined $_ ? "$_" : '<undef>' } map { $_->extract } @children;
            die "LogicalOp found operator '$operator' at index $operator_idx but missing operands: " .
                "left=" . (defined $left ? $left->id : '<undef>') . ", " .
                "right=" . (defined $right ? $right->id : '<undef>') . ", " .
                "children=[@children_debug]";
        }

        # Build appropriate IR node based on operator
        # Logical operators
        if ($operator eq '||' || $operator eq 'or') {
            return Chalk::IR::Node::Or->new(left => $left, right => $right);
        } elsif ($operator eq '//') {
            return Chalk::IR::Node::DefinedOr->new(left => $left, right => $right);
        } elsif ($operator eq '&&' || $operator eq 'and') {
            return Chalk::IR::Node::And->new(left => $left, right => $right);
        }

        # If we get here, we found an operator but didn't handle it - this is a bug
        die "LogicalOp found unrecognized operator '$operator' - expected ||, or, //, &&, or and";
    }
}

1;
