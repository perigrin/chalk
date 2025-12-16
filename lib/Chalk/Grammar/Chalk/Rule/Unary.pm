# ABOUTME: Semantic action for Unary - handles both prefix and postfix unary operators
# ABOUTME: Phase 4: Flattened from Unary + Postfix - handles prefix (!, -, +, \, ++, --) and postfix (++, --)

use 5.42.0;
use experimental 'class';
use Scalar::Util 'blessed';

class Chalk::Grammar::Chalk::Rule::Unary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Negate;
        use Chalk::IR::Node::Not;
        use Chalk::IR::Node::PreIncrement;
        use Chalk::IR::Node::PreDecrement;
        use Chalk::IR::Node::PostIncrement;
        use Chalk::IR::Node::PostDecrement;

        # Unary -> Primary (pass-through)
        # Unary -> '!' WS_OPT Unary (prefix operators)
        # Unary -> Variable '++' (postfix increment)
        # Unary -> Variable '--' (postfix decrement)

        my @children = $context->children->@*;

        if (@children == 1) {
            # First alternative: just pass through Primary
            return $context->child(0);
        }

        # Check if this is a postfix operator (Variable ++)
        # Postfix pattern: child(0) is Variable, child(1) is operator
        if (@children == 2) {
            my $last_child = $children[-1]->extract;
            if (defined($last_child)) {
                my $str_val = "$last_child";  # Stringify (Token or string)
                if ($str_val eq '++') {
                    # Postfix increment: Variable '++'
                    my $operand = $context->child(0);
                    return Chalk::IR::Node::PostIncrement->new(operand => $operand)->peephole();
                } elsif ($str_val eq '--') {
                    # Postfix decrement: Variable '--'
                    my $operand = $context->child(0);
                    return Chalk::IR::Node::PostDecrement->new(operand => $operand)->peephole();
                }
            }
        }

        # Otherwise, this is a prefix operator: check child(0) for the operator
        my $op_child = $children[0]->extract;
        die "Unary: expected operator at children[0], got undefined - grammar bug" unless defined $op_child;

        # Stringify operator (may be Token object or plain string)
        my $operator = "$op_child";

        # Find the operand by scanning children for an IR node (has 'id' method)
        # Grammar: Unary -> OPERATOR WS_OPT Expression
        # Children: [operator, ws_opt?, expression] - WS_OPT may or may not be present
        my $operand;
        for my $i (1 .. $#children) {
            my $child = $context->child($i);
            if (blessed($child) && $child->can('id')) {
                $operand = $child;
                last;
            }
        }

        # Validate that we found an IR node operand
        unless (defined($operand)) {
            my @children_debug = map {
                my $c = $context->child($_);
                defined $c ? (ref($c) || "'$c'") : '<undef>';
            } (0 .. $#children);
            die "Unary: no IR node operand found in children: [@children_debug] - operator was '$operator'";
        }

        # Build appropriate unary node - peephole immediately for constant folding
        if ($operator eq '!') {
            return Chalk::IR::Node::Not->new(operand => $operand)->peephole();
        } elsif ($operator eq '-') {
            return Chalk::IR::Node::Negate->new(operand => $operand)->peephole();
        } elsif ($operator eq '+') {
            # Unary + is a no-op, just pass through
            return $operand;
        } elsif ($operator eq '\\') {
            # Reference node exists but needs wiring up here
            # For now, just pass through
            return $operand;
        } elsif ($operator eq '++') {
            return Chalk::IR::Node::PreIncrement->new(operand => $operand)->peephole();
        } elsif ($operator eq '--') {
            return Chalk::IR::Node::PreDecrement->new(operand => $operand)->peephole();
        }

        die "Unary: unrecognized operator '$operator' - grammar bug";
    }
}

1;
