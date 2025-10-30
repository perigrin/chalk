# ABOUTME: Semantic action for Assignment - binds variables to IR nodes using SSA
# ABOUTME: Assignment handles simple assignment (=) with direct data flow

use 5.42.0;
use experimental 'class';
use builtin qw(blessed);

# IR Quality Heuristic: Pick best parse based on IR completeness
# Prefer parses with more defined structure (more nodes in subtree)
sub _pick_best_ir_value($candidates, $builder) {
    return $candidates->[0] if $candidates->@* == 1;

    # Count IR nodes in the value subtree for each candidate
    # Build scored array manually to avoid map block with hash constructor
    my @scored = ();
    for my $cand ($candidates->@*) {
        my $score = _count_ir_nodes($cand, $builder->graph);
        my $entry = { value => $cand, score => $score };
        push(@scored, $entry);
    }

    # Sort by score descending (more nodes = more complete = better)
    # Using manual sort to avoid sort block syntax
    my $best = $scored[0];
    for my $candidate (@scored) {
        if ($candidate->{score} > $best->{score}) {
            $best = $candidate;
        }
    }

    return $best->{value};
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

        my $left = $node->attributes->{left};
        if ($left) {
            if ($left->{op} eq 'NodeRef') {
                my $left_node = $graph->get_node($left->{node_id});
                $count += _count_ir_nodes($left_node, $graph);
            }
        }

        my $right = $node->attributes->{right};
        if ($right) {
            if ($right->{op} eq 'NodeRef') {
                my $right_node = $graph->get_node($right->{node_id});
                $count += _count_ir_nodes($right_node, $graph);
            }
        }
    }

    # Note: Store nodes removed in SSA refactor - variables are direct data flow

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
            if (defined($child) && !ref($child) && $child eq '=') {
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
        # Two possible cases:
        # 1. Variable metadata hash (from ScalarVar before Primary processes it)
        # 2. Proj node (function parameters)
        # Note: With SSA-style variables, we no longer create Load nodes
        my $var_name;
        if (ref($lhs) eq 'HASH' && $lhs->{type} eq 'scalar_var') {
            # Case 1: Variable metadata
            $var_name = $lhs->{name};
        } elsif (blessed($lhs) && $lhs->can('op') && $lhs->op eq 'Proj') {
            # Case 2: Proj node from parameter
            $var_name = $lhs->label;  # Use label field, not attributes
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

            my $candidate_values = [];
            for my $alt_ctx (@rhs_alternatives) {
                # Extract semantic value from this alternative's context
                my $alt_value = $alt_ctx->extract if $alt_ctx->can('extract');
                next unless (blessed($alt_value) && $alt_value->can('id'));
                push($candidate_values->@*, $alt_value);
            }

            # If we got candidates, pick the best based on IR quality
            my $num_candidates = scalar($candidate_values->@*);
            if ($num_candidates > 0) {
                $rhs = _pick_best_ir_value($candidate_values, $builder);
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

        # Bind variable to value node using SSA (no Store node needed)
        # Variables are direct data flow edges in the IR graph
        return $builder->build_store_node($var_name, $rhs);
    }
}

1;
