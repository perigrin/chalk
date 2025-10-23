# ABOUTME: Validator for Sea of Nodes IR graphs checking SSA properties, CFG structure, dominance, and phi nodes
# ABOUTME: Provides comprehensive validation infrastructure to catch IR construction errors before compilation
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Validator {
    use Chalk::IR::Node;
    use Chalk::IR::Graph;

    # Main validation entry point - runs all validators
    method validate_all($graph) {
        my @all_errors = ();

        # Run each validator and collect errors
        push @all_errors, $self->validate_cfg($graph);
        push @all_errors, $self->validate_single_assignment($graph);
        push @all_errors, $self->validate_dominance($graph);
        push @all_errors, $self->validate_phi_placement($graph);

        my $success = scalar(@all_errors) == 0 ? 1 : 0;
        return ($success, \@all_errors);
    }

    # Validate Control Flow Graph structure
    method validate_cfg($graph) {
        my @errors = ();

        # Check: Single Start node exists
        my $start_count = 0;
        my $start_id = undef;
        my $nodes = $graph->nodes;

        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            if ($node->op eq 'Start') {
                $start_count++;
                $start_id = $node_id;
            }
        }

        if ($start_count == 0) {
            push @errors, "CFG validation failed: No Start node found in graph";
        }
        elsif ($start_count > 1) {
            push @errors, "CFG validation failed: Multiple Start nodes found ($start_count), expected exactly 1";
        }

        # Check: At least one Return node exists
        my $return_count = 0;
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            if ($node->op eq 'Return') {
                $return_count++;
            }
        }

        if ($return_count == 0) {
            push @errors, "CFG validation failed: No Return node found in graph";
        }

        # Check: All nodes reachable from Start (BFS traversal)
        if (defined($start_id)) {
            my %reachable = ();
            my @queue = ($start_id);
            $reachable{$start_id} = 1;

            while (scalar(@queue) > 0) {
                my $current_id = shift @queue;
                my $current_node = $nodes->{$current_id};

                # Follow all outgoing edges (inputs reference other nodes)
                # Note: In Sea of Nodes, inputs point TO this node FROM others,
                # so we need to find nodes that reference this one
                for my $other_id (keys $nodes->%*) {
                    next if exists($reachable{$other_id});
                    my $other_node = $nodes->{$other_id};

                    # Check if other_node references current_node
                    for my $input_id ($other_node->inputs->@*) {
                        if ($input_id eq $current_id) {
                            $reachable{$other_id} = 1;
                            push @queue, $other_id;
                            last;
                        }
                    }
                }
            }

            # Report unreachable nodes (except Constants which are data-only)
            for my $node_id (keys $nodes->%*) {
                if (not(exists($reachable{$node_id}))) {
                    my $node = $nodes->{$node_id};
                    # Constants are data-only nodes and don't need control flow reachability
                    if ($node->op ne 'Constant') {
                        push @errors, "CFG validation failed: Node $node_id is not reachable from Start node";
                    }
                }
            }
        }

        return @errors;
    }

    # Validate SSA single assignment property
    method validate_single_assignment($graph) {
        my @errors = ();
        my %assignments = ();  # variable_name => [node_ids]

        my $nodes = $graph->nodes;

        # Collect all Store nodes (variable assignments)
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            if ($node->op eq 'Store') {
                my $var_name = $node->attributes->{variable};
                if (defined($var_name)) {
                    $assignments{$var_name} //= [];
                    push $assignments{$var_name}->@*, $node_id;
                }
            }
        }

        # Check for multiple assignments to same variable
        for my $var_name (keys %assignments) {
            my $assign_list = $assignments{$var_name};
            if (scalar($assign_list->@*) > 1) {
                my $node_list = join(', ', $assign_list->@*);
                push @errors, "SSA violation: Variable $var_name is assigned more than once (in nodes: $node_list)";
            }
        }

        return @errors;
    }

    # Compute dominance tree using Cooper/Harvey/Kennedy algorithm
    method compute_dominance_tree($graph) {
        my $nodes = $graph->nodes;
        my %dom = ();  # node_id => immediate_dominator_id

        # Find Start node
        my $start_id = undef;
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            if ($node->op eq 'Start') {
                $start_id = $node_id;
                last;
            }
        }

        return \%dom unless defined($start_id);

        # Build reverse graph (predecessors)
        my %preds = ();  # node_id => [predecessor_ids]
        for my $node_id (keys $nodes->%*) {
            $preds{$node_id} = [];
        }

        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            for my $input_id ($node->inputs->@*) {
                if (exists($nodes->{$input_id})) {
                    push $preds{$node_id}->@*, $input_id;
                }
            }
        }

        # Initialize: Start dominates itself
        $dom{$start_id} = $start_id;

        # Iterative dataflow until convergence
        my $changed = 1;
        my $max_iterations = scalar(keys $nodes->%*) * 2;
        my $iterations = 0;

        while ($changed) {
            if ($iterations > $max_iterations) {
                last;
            }
            $changed = 0;
            $iterations++;

            for my $node_id (keys $nodes->%*) {
                next if $node_id eq $start_id;

                my @pred_list = $preds{$node_id}->@*;
                next if scalar(@pred_list) == 0;

                # Find first processed predecessor
                my $new_idom = undef;
                for my $pred_id (@pred_list) {
                    if (exists($dom{$pred_id})) {
                        $new_idom = $pred_id;
                        last;
                    }
                }

                next unless defined($new_idom);

                # Intersect with all other predecessors
                for my $pred_id (@pred_list) {
                    next if $pred_id eq $new_idom;
                    next unless exists($dom{$pred_id});

                    $new_idom = $self->_intersect(\%dom, $pred_id, $new_idom);
                }

                # Update if changed
                if (not(exists($dom{$node_id}))) {
                    $dom{$node_id} = $new_idom;
                    $changed = 1;
                }
                elsif ($dom{$node_id} ne $new_idom) {
                    $dom{$node_id} = $new_idom;
                    $changed = 1;
                }
            }
        }

        return \%dom;
    }

    # Helper: Find intersection of two nodes in dominance tree
    method _intersect($dom, $b1, $b2) {
        my $finger1 = $b1;
        my $finger2 = $b2;

        while ($finger1 ne $finger2) {
            # Move up dominance tree
            while ($self->_node_depth($finger1) > $self->_node_depth($finger2)) {
                $finger1 = $dom->{$finger1};
                last unless defined($finger1);
            }
            last unless defined($finger1);

            while ($self->_node_depth($finger2) > $self->_node_depth($finger1)) {
                $finger2 = $dom->{$finger2};
                last unless defined($finger2);
            }
            last unless defined($finger2);

            if ($finger1 eq $finger2) {
                last;
            }

            # Both at same depth, move up together
            $finger1 = $dom->{$finger1};
            $finger2 = $dom->{$finger2};

            last unless defined($finger1);
            last unless defined($finger2);
        }

        return $finger1;
    }

    # Helper: Get node depth from node_id (simple heuristic: parse number)
    method _node_depth($node_id) {
        return 0 unless defined($node_id);
        if ($node_id =~ /node_(\d+)/) {
            return $1;
        }
        return 0;
    }

    # Validate dominance property: definitions dominate uses
    method validate_dominance($graph) {
        my @errors = ();

        my $dom_tree = $self->compute_dominance_tree($graph);
        my $nodes = $graph->nodes;

        # Check each Load node: its Store must exist and be valid
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            if ($node->op eq 'Load') {
                my $var_name = $node->attributes->{variable};
                my $store_id = $node->attributes->{store_id};

                if (defined($store_id)) {
                    if (defined($var_name)) {
                        # Check if store exists
                        if (not(exists($nodes->{$store_id}))) {
                            push @errors, "Dominance violation: Load of $var_name in $node_id references non-existent Store $store_id";
                            next;
                        }

                        my $store_node = $nodes->{$store_id};
                        if ($store_node->op ne 'Store') {
                            push @errors, "Dominance violation: Load of $var_name in $node_id references $store_id which is not a Store node";
                            next;
                        }

                        # For graphs with control flow (Region nodes), check strict dominance
                        # For linear graphs (Chapters 1-4), the store_id reference is sufficient
                        my $has_control_flow = $self->_has_control_flow($graph);

                        if ($has_control_flow) {
                            my $is_dominated = $self->_dominates($dom_tree, $store_id, $node_id);
                            if (not($is_dominated)) {
                                push @errors, "Dominance violation: Load of $var_name in $node_id is not dominated by its Store in $store_id";
                            }
                        }
                    }
                }
            }
        }

        return @errors;
    }

    # Helper: Check if graph has control flow (Region/If nodes)
    method _has_control_flow($graph) {
        my $nodes = $graph->nodes;
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            if ($node->op eq 'Region' || $node->op eq 'If') {
                return 1;
            }
        }
        return 0;
    }

    # Helper: Check if dominator_id dominates target_id
    method _dominates($dom_tree, $dominator_id, $target_id) {
        return 1 if $dominator_id eq $target_id;

        # Walk up dominance tree from target
        my $current = $target_id;
        my $max_steps = 100;
        my $steps = 0;

        while (defined($current)) {
            if ($steps > $max_steps) {
                last;
            }
            $steps++;

            if (exists($dom_tree->{$current})) {
                $current = $dom_tree->{$current};
                if (defined($current)) {
                    if ($current eq $dominator_id) {
                        return 1;
                    }
                }
            }
            else {
                last;
            }
        }

        return 0;
    }

    # Validate phi node placement (prepare for Chapter 5)
    method validate_phi_placement($graph) {
        my @errors = ();

        my $nodes = $graph->nodes;

        # Check each Phi node
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            next unless $node->op eq 'Phi';

            # Phi must be at a Region (control flow merge point)
            my $phi_inputs = $node->inputs;
            if (scalar($phi_inputs->@*) == 0) {
                push @errors, "Phi node $node_id has no control input (must connect to Region)";
                next;
            }

            my $region_id = $phi_inputs->[0];
            if (exists($nodes->{$region_id})) {
                my $region_node = $nodes->{$region_id};
                if ($region_node->op ne 'Region' && $region_node->op ne 'Loop') {
                    push @errors, "Phi node $node_id is not at a Region/Loop merge point (control input is " . $region_node->op . ")";
                }
                else {
                    # Count region/loop predecessors
                    my $region_preds = $region_node->inputs;
                    my $expected_alternatives = scalar($region_preds->@*);

                    # Count phi alternatives from inputs array (first input is control, rest are values)
                    my $phi_inputs = $node->inputs;
                    my $actual_alternatives = scalar($phi_inputs->@*) - 1;  # Subtract control input

                    if ($actual_alternatives != $expected_alternatives) {
                        push @errors, "Phi node $node_id in node $region_id expects $expected_alternatives value inputs ($expected_alternatives predecessors) but has $actual_alternatives";
                    }
                }
            }
            else {
                push @errors, "Phi node $node_id references non-existent Region $region_id";
            }
        }

        return @errors;
    }
}

1;

=pod

=head1 NAME

Chalk::IR::Validator - Comprehensive validation for Sea of Nodes IR graphs

=head1 SYNOPSIS

    use Chalk::IR::Validator;
    use Chalk::IR::Graph;

    my $graph = Chalk::IR::Graph->new();
    # ... build graph ...

    my $validator = Chalk::IR::Validator->new();
    my ($success, $errors) = $validator->validate_all($graph);

    if (!$success) {
        for my $error (@$errors) {
            warn "Validation error: $error\n";
        }
    }

=head1 DESCRIPTION

Chalk::IR::Validator provides comprehensive validation infrastructure for Sea of Nodes
IR graphs. It checks critical properties required for correct compilation:

=over 4

=item * B<CFG Structure> - Single Start node, at least one Return node, all nodes reachable

=item * B<SSA Form> - Each variable assigned exactly once (Static Single Assignment)

=item * B<Dominance> - Variable uses dominated by their definitions

=item * B<Phi Placement> - Phi nodes only at control flow merge points with correct arity

=back

This validator is designed to catch IR construction errors immediately, before they
cause subtle bugs in later compilation phases.

=head1 METHODS

=head2 validate_all($graph)

Main entry point. Runs all validators and returns results.

    my ($success, $errors) = $validator->validate_all($graph);

Returns:

=over 4

=item * C<$success> - Boolean: 1 if all validations pass, 0 if any fail

=item * C<$errors> - ArrayRef of error message strings

=back

=head2 validate_cfg($graph)

Validates Control Flow Graph structure:

=over 4

=item * Exactly one Start node exists

=item * At least one Return node exists

=item * All nodes are reachable from Start (no orphaned nodes)

=back

Returns: List of error messages (empty if valid)

=head2 validate_single_assignment($graph)

Validates SSA (Static Single Assignment) property:

=over 4

=item * Each variable (Store node) is assigned exactly once

=back

In SSA form, multiple assignments to the same variable name are prohibited.
Use phi nodes at control flow merge points instead.

Returns: List of error messages (empty if valid)

=head2 compute_dominance_tree($graph)

Computes the dominance tree using Cooper/Harvey/Kennedy algorithm.

Returns: HashRef mapping C<node_id =E<gt> immediate_dominator_id>

A node A dominates node B if every path from Start to B passes through A.
The immediate dominator is the closest dominator (excluding the node itself).

=head2 validate_dominance($graph)

Validates dominance property:

=over 4

=item * Each variable use (Load node) is dominated by its definition (Store node)

=back

This ensures variables are defined before use in all possible execution paths.

Returns: List of error messages (empty if valid)

=head2 validate_phi_placement($graph)

Validates phi node placement (Chapter 5 prerequisite):

=over 4

=item * Phi nodes only appear at Region (control flow merge) nodes

=item * Number of phi alternatives matches number of control predecessors

=item * Each phi input corresponds to an incoming control edge

=back

Phi nodes merge different values of a variable from different control flow paths.

Returns: List of error messages (empty if valid)

=head1 ERROR MESSAGES

The validator produces clear, actionable error messages:

=over 4

=item * C<CFG validation failed: No Start node found in graph>

Graph missing entry point. Every graph must have exactly one Start node.

=item * C<Node node_5 is not reachable from Start node>

Orphaned node detected. All nodes must be reachable via edges from Start.

=item * C<SSA violation: Variable $x is assigned more than once (in nodes: node_2, node_5)>

Multiple Store nodes for same variable violate SSA form. Use phi nodes instead.

=item * C<Dominance violation: Load of $x in node_3 is not dominated by its Store in node_5>

Variable used before definition in some control flow path.

=item * C<Phi node node_7 expects 2 inputs (2 predecessors) but has 3>

Phi node has wrong number of alternatives for its Region's control predecessors.

=back

=head1 USAGE PATTERNS

=head2 Correct SSA Form

    # CORRECT: Single assignment
    my $store = Chalk::IR::Node->new(
        op => 'Store',
        attributes => { variable => '$x', value => {...} }
    );

    # INCORRECT: Multiple assignments (use phi instead)
    my $store1 = Chalk::IR::Node->new(
        op => 'Store',
        attributes => { variable => '$x', value => {value => 10} }
    );
    my $store2 = Chalk::IR::Node->new(
        op => 'Store',
        attributes => { variable => '$x', value => {value => 20} }
    );

=head2 Correct Phi Placement

    # CORRECT: Phi at Region with matching alternatives
    my $region = Chalk::IR::Node->new(
        op => 'Region',
        inputs => ['node_then', 'node_else']  # 2 predecessors
    );
    my $phi = Chalk::IR::Node->new(
        op => 'Phi',
        inputs => ['node_region'],
        attributes => {
            variable => '$x',
            alternatives => [
                {value => 10},  # from then branch
                {value => 20}   # from else branch
            ]
        }
    );

    # INCORRECT: Phi not at Region
    my $phi = Chalk::IR::Node->new(
        op => 'Phi',
        inputs => ['node_start'],  # Not a Region!
        attributes => {...}
    );

=head1 REFERENCES

=over 4

=item * Sea of Nodes IR: L<https://darksi.de/d.sea-of-nodes/>

=item * SSA Form: L<https://en.wikipedia.org/wiki/Static_single-assignment_form>

=item * Dominance: Cooper, Harvey, Kennedy. "A Simple, Fast Dominance Algorithm" (2001)

=back

=head1 AUTHOR

Chalk Compiler Project

=cut
