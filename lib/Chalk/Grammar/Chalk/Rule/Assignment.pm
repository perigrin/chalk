# ABOUTME: Semantic action for Assignment - builds Store nodes for variable assignments
# ABOUTME: Assignment handles simple assignment (=) with placeholder control pattern

use 5.42.0;
use experimental 'class';
use Scalar::Util qw(blessed);

class Chalk::Grammar::Chalk::Rule::Assignment :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Assignment -> Ternary (pass-through)
        # Assignment -> Ternary WS_OPT '=' WS_OPT Assignment
        # Assignment -> Ternary WS_OPT %ASSIGN_OP% WS_OPT Assignment (TODO: compound assignment)

        my @children = $context->children->@*;
        my $builder = $context->env->{ir_builder};

        # Check if this is an assignment operation (has '=' operator)
        my $has_assignment = 0;
        my $equals_index = -1;
        for my $i (0..$#children) {
            my $child = $children[$i]->extract;
            if (defined $child && !ref($child) && $child eq '=') {
                $has_assignment = 1;
                $equals_index = $i;
                last;
            }
        }

        # If no '=' operator, just pass through the Ternary child
        return $context->child(0) unless $has_assignment;

        # We have an assignment: Ternary = Assignment
        return $context->child(0) unless $builder;

        # Get left side (variable being assigned to)
        my $lhs = $context->child(0);

        # Extract variable name from lhs
        # Three possible cases:
        # 1. Variable metadata hash (from ScalarVar before Primary processes it)
        # 2. Load node (from regular variables after Primary)
        # 3. Proj node (from parameters - build_load_node returns Proj directly for params)
        my $var_name;
        if (ref($lhs) eq 'HASH' && $lhs->{type} eq 'scalar_var') {
            # Case 1: Variable metadata
            $var_name = $lhs->{name};
        } elsif (blessed($lhs) && $lhs->can('op')) {
            if ($lhs->op eq 'Load') {
                # Case 2: Load node from regular variable
                $var_name = $lhs->attributes->{name};
            } elsif ($lhs->op eq 'Proj') {
                # Case 3: Proj node from parameter
                $var_name = $lhs->attributes->{label};
            } else {
                # Unsupported node type for assignment target
                return $context->child(0);
            }
        } else {
            # Can't handle this lhs type for assignment
            return $context->child(0);
        }

        # Get right side (value to assign) - after '=' + WS_OPT, which is equals_index + 2
        my $rhs_index = $equals_index + 2;
        my $rhs = $context->child($rhs_index);

        # Validate we got an IR node for the value
        return $context->child(0) unless (blessed($rhs) && $rhs->can('id'));

        # Create Store node with placeholder control
        # Parent rule (Block, ConditionalStatement, WhileStatement) will wire actual control
        #
        # NOTE: SPPF may create multiple parse trees for complex expressions like "$i = $i - 1"
        # Both parses create Store nodes in the graph, semiring picks one for the parse tree.
        # Currently semiring may pick incomplete parse (rhs=$i instead of rhs=$i-1).
        # This is expected SPPF behavior - will need optimization pass to detect/fix later.
        return $builder->build_store_node($var_name, $rhs, '__CONTROL_PLACEHOLDER__');
    }
}

1;
