# ABOUTME: Semantic action for Assignment - builds Store nodes for variable assignments
# ABOUTME: Assignment handles simple assignment (=) with placeholder control pattern

use 5.42.0;
use experimental 'class';
use Scalar::Util qw(blessed);

# IR Quality Heuristic: Pick best parse based on IR completeness
# Prefer parses with more defined structure (more nodes in subtree)
sub _pick_best_ir_value($candidates, $builder) {
    return $candidates->[0] if @$candidates == 1;

    # Count IR nodes in the value subtree for each candidate
    my @scored = map {
        { value => $_, score => _count_ir_nodes($_, $builder->graph) }
    } @$candidates;

    # Sort by score descending (more nodes = more complete = better)
    @scored = sort { $b->{score} <=> $a->{score} } @scored;

    return $scored[0]->{value};
}

# Recursively count nodes in IR subtree
# More nodes indicates more complete parse
sub _count_ir_nodes($node, $graph) {
    return 0 unless $node;
    return 0 unless blessed($node) && $node->can('op');

    my $count = 1;  # Count self

    # Recursively count children based on operation type
    my $op = $node->op;

    # Binary operations have left/right children
    if ($op eq 'Add' || $op eq 'Subtract' || $op eq 'Multiply' || $op eq 'Divide' ||
        $op eq 'GT' || $op eq 'LT' || $op eq 'EQ' || $op eq 'NE' || $op eq 'LE' || $op eq 'GE') {

        if (my $left = $node->attributes->{left}) {
            if ($left->{op} eq 'NodeRef') {
                my $left_node = $graph->get_node($left->{node_id});
                $count += _count_ir_nodes($left_node, $graph);
            }
        }

        if (my $right = $node->attributes->{right}) {
            if ($right->{op} eq 'NodeRef') {
                my $right_node = $graph->get_node($right->{node_id});
                $count += _count_ir_nodes($right_node, $graph);
            }
        }
    }

    # Store nodes have value children
    if ($op eq 'Store') {
        if (my $value = $node->attributes->{value}) {
            if ($value->{op} eq 'NodeRef') {
                my $value_node = $graph->get_node($value->{node_id});
                $count += _count_ir_nodes($value_node, $graph);
            }
        }
    }

    return $count;
}

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

        # Query parse alternatives for RHS to handle ambiguous parses
        # For expressions like "$i = $i - 1", SPPF may create multiple parse trees
        my @rhs_alternatives = $context->child_alternatives($rhs_index);

        my $rhs;
        if (@rhs_alternatives > 1) {
            # Multiple parse alternatives exist - evaluate each and pick best
            # The "best" is the one with most complete IR structure

            my @candidate_values;
            for my $alt_ctx (@rhs_alternatives) {
                # Extract semantic value from this alternative's context
                my $alt_value = $alt_ctx->extract if $alt_ctx->can('extract');
                next unless (blessed($alt_value) && $alt_value->can('id'));
                push @candidate_values, $alt_value;
            }

            # If we got candidates, pick the best based on IR quality
            if (@candidate_values > 0) {
                $rhs = Chalk::Grammar::Chalk::Rule::Assignment::_pick_best_ir_value(\@candidate_values, $builder);
            } else {
                # Fallback to default if no valid candidates
                $rhs = $context->child($rhs_index);
            }
        } else {
            # No ambiguity - use the single parse (default behavior)
            $rhs = $context->child($rhs_index);
        }

        # Validate we got an IR node for the value
        return $context->child(0) unless (blessed($rhs) && $rhs->can('id'));

        # Create Store node with placeholder control
        # Parent rule (Block, ConditionalStatement, WhileStatement) will wire actual control
        return $builder->build_store_node($var_name, $rhs, '__CONTROL_PLACEHOLDER__');
    }
}

1;
