# ABOUTME: Semantic action for Unary - handles both prefix and postfix unary operators
# ABOUTME: Phase 4: Flattened from Unary + Postfix - handles prefix (!, -, +, \, ++, --) and postfix (++, --)

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Unary :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Negate;
        use Chalk::IR::Node::Not;

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
                if ($str_val eq '++' || $str_val eq '--') {
                    # This is postfix: Variable '++' or Variable '--'
                    # TODO: Implement postfix increment/decrement when IR nodes available
                    return $context->child(0);
                }
            }
        }

        # Otherwise, this is a prefix operator: check child(0) for the operator
        my $op_child = $children[0]->extract;
        return $context->child(0) unless defined $op_child;

        # Stringify operator (may be Token object or plain string)
        my $operator = "$op_child";

        # Get operand at child 1 (WS_OPT is collapsed/absent when empty)
        my $operand = $context->child(1);

        # Validate that we got an IR node
        return $operand unless (ref($operand) && $operand->can('id'));

        # Build appropriate unary node
        if ($operator eq '!') {
            return Chalk::IR::Node::Not->new(operand => $operand);
        } elsif ($operator eq '-') {
            return Chalk::IR::Node::Negate->new(operand => $operand);
        } elsif ($operator eq '+') {
            # Unary + is a no-op, just pass through
            return $operand;
        } elsif ($operator eq '\\') {
            # TODO: Reference node needs to be updated to Builder-less architecture
            # For now, just pass through
            return $operand;
        } elsif ($operator eq '++' || $operator eq '--') {
            # Prefix ++/--
            # TODO: Implement prefix increment/decrement when IR nodes available
            return $operand;
        }

        return $context->child(0);
    }
}

1;
