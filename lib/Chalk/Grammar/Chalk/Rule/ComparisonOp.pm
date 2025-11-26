# ABOUTME: Semantic action for ComparisonOp - flattened comparison and regex match operators
# ABOUTME: Handles comparison (>, <, ==, !=, isa) and regex match (=~, !~) with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ComparisonOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        use Chalk::IR::Node::EQ;
        use Chalk::IR::Node::NE;
        use Chalk::IR::Node::LT;
        use Chalk::IR::Node::LE;
        use Chalk::IR::Node::GT;
        use Chalk::IR::Node::GE;

        # Grammar: ComparisonOp -> Expression WS_OPT %COMPARE_OP% WS_OPT Expression
        # But WS_OPT may be filtered out, so we get either 3 or 5 children
        # Search for the operator dynamically instead of hardcoding indices

        # Count children to determine which alternative matched
        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through StringOp
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
                # Match comparison operators: ==, !=, <, <=, >, >=, eq, ne, lt, le, gt, ge
                if ($str_val =~ qr/^(==|!=|<=?|>=?|eq|ne|lt|le|gt|ge|=~|!~|isa)$/) {
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
        # Comparison operators
        if ($operator eq '>' || $operator eq 'gt') {
            return Chalk::IR::Node::GT->new(left => $left, right => $right);
        } elsif ($operator eq '<' || $operator eq 'lt') {
            return Chalk::IR::Node::LT->new(left => $left, right => $right);
        } elsif ($operator eq '==' || $operator eq 'eq') {
            return Chalk::IR::Node::EQ->new(left => $left, right => $right);
        } elsif ($operator eq '>=' || $operator eq 'ge') {
            return Chalk::IR::Node::GE->new(left => $left, right => $right);
        } elsif ($operator eq '<=' || $operator eq 'le') {
            return Chalk::IR::Node::LE->new(left => $left, right => $right);
        } elsif ($operator eq '!=' || $operator eq 'ne') {
            return Chalk::IR::Node::NE->new(left => $left, right => $right);
        }
        # Regex match operators (=~, !~)
        # TODO: implement when regex match IR nodes are available
        elsif ($operator eq '=~' || $operator eq '!~') {
            # For now, just pass through left side
            return $left;
        }
        # isa operator
        # TODO: implement when isa IR node is available
        elsif ($operator eq 'isa') {
            # For now, just pass through left side
            return $left;
        }

        return $context->child(0);
    }
}

1;
