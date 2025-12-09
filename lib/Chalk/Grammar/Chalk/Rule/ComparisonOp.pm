# ABOUTME: Semantic action for ComparisonOp - flattened comparison and regex match operators
# ABOUTME: Handles comparison (>, <, ==, !=, isa) and regex match (=~, !~) with precedence validated by Precedence semiring

use 5.42.0;
use experimental qw(class);

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

        # Find the operator by scanning children - expression structure varies
        # because WS_OPT may or may not be present, so we can't use fixed indices
        my $operator_idx;
        my $operator;

        for my $i (0 .. $#children) {
            my $child = $context->child($i);
            if ($child isa Chalk::Grammar::Token::Operator) {
                $operator = "$child";  # Stringify to get operator value
                $operator_idx = $i;
                last;
            }
        }

        # If no operator found with multiple children, this is a bug
        unless (defined $operator) {
            my @children_debug = map { defined $_ ? "$_" : '<undef>' } map { $_->extract } @children;
            die "ComparisonOp matched with " . scalar(@children) . " children but no operator found: [@children_debug]";
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
            # Build child descriptions for error message
            my @child_descs;
            for my $i (0..$#children) {
                my $c = $context->child($i);
                my $desc;
                if (!defined($c)) {
                    $desc = 'undef';
                } elsif (blessed($c)) {
                    $desc = ref($c) . ($c->can('id') ? '->' . $c->id : '');
                } elsif (ref($c)) {
                    $desc = ref($c) . '{...}';  # Unblessed reference (HASH/ARRAY)
                } else {
                    $desc = "'$c'";
                }
                push @child_descs, "child[$i]: $desc";
            }

            my $left_desc = defined($left)
                ? (blessed($left) ? ref($left) . '->' . $left->id : (ref($left) ? ref($left) . '{...}' : "'$left'"))
                : 'NOT FOUND';
            my $right_desc = defined($right)
                ? (blessed($right) ? ref($right) . '->' . $right->id : (ref($right) ? ref($right) . '{...}' : "'$right'"))
                : 'NOT FOUND';

            die "ComparisonOp: Could not find IR nodes with id() for both operands\n" .
                "  operator: " . ($operator // 'undef') . " at index " . ($operator_idx // 'undef') . "\n" .
                "  left: $left_desc\n" .
                "  right: $right_desc\n" .
                "  children (" . scalar(@children) . "): " . join(", ", @child_descs) . "\n" .
                "  This usually means Expression or its sub-rules failed to build IR nodes.\n";
        }

        # Build appropriate IR node based on operator
        # Comparison operators - peephole immediately for constant folding
        if ($operator eq '>' || $operator eq 'gt') {
            return Chalk::IR::Node::GT->new(left => $left, right => $right)->peephole();
        } elsif ($operator eq '<' || $operator eq 'lt') {
            return Chalk::IR::Node::LT->new(left => $left, right => $right)->peephole();
        } elsif ($operator eq '==' || $operator eq 'eq') {
            return Chalk::IR::Node::EQ->new(left => $left, right => $right)->peephole();
        } elsif ($operator eq '>=' || $operator eq 'ge') {
            return Chalk::IR::Node::GE->new(left => $left, right => $right)->peephole();
        } elsif ($operator eq '<=' || $operator eq 'le') {
            return Chalk::IR::Node::LE->new(left => $left, right => $right)->peephole();
        } elsif ($operator eq '!=' || $operator eq 'ne') {
            return Chalk::IR::Node::NE->new(left => $left, right => $right)->peephole();
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

        # If we get here, we found an operator but didn't handle it - this is a bug
        die "ComparisonOp found unrecognized operator '$operator' - not handled by any branch";
    }

    # Type inference for TypeInference semiring
    # Comparison operators always return Bool type
    method infer_type($semiring, $element) {
        use Chalk::Semiring::TypeInference;  # For TypeInferenceElement

        # Element tree structure mirrors parse tree
        my @children = $element->children->@*;

        # ComparisonOp -> Expression (pass-through)
        # ComparisonOp -> Expression WS_OPT OPERATOR WS_OPT Expression
        # Single child means pass-through
        return $element if scalar(@children) < 2;

        # Find the comparison operator token
        my $operator;
        my $operator_idx;
        for my $i (0..$#children) {
            my $child = $children[$i];
            # Check if this child has a token that is a comparison operator
            # Grammar has already validated it's a valid comparison operator
            if (defined $child->token && $child->token isa Chalk::Grammar::Token::Operator) {
                $operator = $child->token->value;
                $operator_idx = $i;
                last;
            }
        }

        # Not a comparison operation, pass through
        return $element unless defined($operator);

        # Get type lattice
        my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

        # All comparison operators return Bool type
        # We could add more sophisticated type checking here (e.g., ensure operands are comparable)
        # but for now, we just return Bool
        my $result_type = $lattice->type_from_name('Bool');

        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $result_type,
            type_env => $element->type_env,
            children => $element->children,
            token => $element->token
        );
    }
}

1;
