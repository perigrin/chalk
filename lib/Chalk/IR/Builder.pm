# ABOUTME: IR builder for transforming parsed Chalk code into Sea of Nodes IR
# ABOUTME: Provides methods called by semantic actions to build IR nodes during parsing
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Builder {
    use Chalk::IR::Node;
    use Chalk::IR::Graph;
    use Chalk::IR::Scope;

    field $graph :reader;
    field $scope :reader;
    field $node_counter :reader = 0;
    field $current_control :reader;  # Current control flow node

    ADJUST {
        $graph = Chalk::IR::Graph->new();
        $scope = Chalk::IR::Scope->new();
    }

    # Generate unique node ID
    method next_node_id() {
        my $id = "node_$node_counter";
        $node_counter++;
        return $id;
    }

    # Set current control flow node
    method set_control($ctrl) {
        $current_control = $ctrl;
    }

    # Create Start node for a function/method
    method build_start_node($function_name = 'main', $params = []) {
        my $start = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Start',
            inputs => [],
            attributes => {
                function => $function_name,
                params => $params
            }
        );
        $graph->add_node($start);
        $self->set_control($start->id);

        # Create Proj nodes for each parameter and register in scope
        for my $i (0..$#{$params}) {
            my $param_name = $params->[$i];
            my $proj = $self->build_proj_node($start, $i, $param_name);
            # Register parameter Proj in scope so lookups return it directly
            $scope->define($param_name, $proj->id);
        }

        return $start;
    }

    # Create Constant node
    method build_constant_node($value, $type = 'Int') {
        my $constant = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Constant',
            inputs => [$current_control],
            attributes => { value => $value, type => $type }
        );
        $graph->add_node($constant);
        return $constant;
    }

    # Create Return node
    # If $control is undef, uses current_control. Otherwise uses provided control.
    method build_return_node($value_node, $control = undef) {
        # Debug: check what we received
        my $ref_type = ref($value_node) || 'SCALAR';
        unless ($ref_type && $ref_type =~ /^Chalk::IR::Node/) {
            use Data::Dumper;
            warn "build_return_node received non-node: $ref_type\n";
            warn "Value: " . Dumper($value_node);
            return undef;
        }

        # Use provided control, or current_control, or '__CONTROL_PLACEHOLDER__'
        my $ctrl = $control // $current_control // '__CONTROL_PLACEHOLDER__';

        my $return = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Return',
            inputs => [$ctrl, $value_node->id],
            attributes => {}
        );
        $graph->add_node($return);
        return $return;
    }

    # Set control input for an existing node
    method set_node_control($node, $control_id) {
        my $inputs = $node->inputs;
        $inputs->[0] = $control_id;  # Control is always first input
    }

    # Create arithmetic operation nodes
    method build_add_node($left_node, $right_node) {
        my $add = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Add',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => {
                left => { op => 'NodeRef', node_id => $left_node->id },
                right => { op => 'NodeRef', node_id => $right_node->id }
            }
        );
        $graph->add_node($add);
        return $add;
    }

    method build_multiply_node($left_node, $right_node) {
        my $mul = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Multiply',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => {
                left => { op => 'NodeRef', node_id => $left_node->id },
                right => { op => 'NodeRef', node_id => $right_node->id }
            }
        );
        $graph->add_node($mul);
        return $mul;
    }

    method build_sub_node($left_node, $right_node) {
        my $sub = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Sub',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => {
                left => { op => 'NodeRef', node_id => $left_node->id },
                right => { op => 'NodeRef', node_id => $right_node->id }
            }
        );
        $graph->add_node($sub);
        return $sub;
    }

    method build_divide_node($left_node, $right_node) {
        my $div = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Div',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => {
                left => { op => 'NodeRef', node_id => $left_node->id },
                right => { op => 'NodeRef', node_id => $right_node->id }
            }
        );
        $graph->add_node($div);
        return $div;
    }

    # Create Store node (variable assignment)
    method build_store_node($var_name, $value_node, $control = undef) {
        # Use provided control, or current_control, or '__CONTROL_PLACEHOLDER__'
        my $ctrl = $control // $current_control // '__CONTROL_PLACEHOLDER__';

        my $store = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Store',
            inputs => [$ctrl, $value_node->id],
            attributes => {
                name => $var_name,
                value => { op => 'NodeRef', node_id => $value_node->id }
            }
        );
        $graph->add_node($store);
        $scope->define($var_name, $store->id);
        return $store;
    }

    # Create Load node (variable read)
    method build_load_node($var_name) {
        my $node_id = $scope->lookup($var_name);
        return undef unless $node_id;

        # Check if this is a Proj node (parameter) - if so, return it directly
        my $node = $graph->nodes->{$node_id};
        if ($node && $node->op eq 'Proj') {
            # Parameter: return the Proj node directly
            return $node;
        }

        # Regular variable: create Load node from Store
        my $load = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Load',
            inputs => [$current_control, $node_id],
            attributes => {
                name => $var_name,
                store_id => $node_id
            }
        );
        $graph->add_node($load);
        return $load;
    }

    # Create Proj node (projection from MultiNode like Start)
    method build_proj_node($source_node, $index, $label) {
        my $proj = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Proj',
            inputs => [$source_node->id],
            attributes => {
                index => $index,
                label => $label
            }
        );
        $graph->add_node($proj);
        return $proj;
    }

    # Comparison nodes
    method build_greater_node($left_node, $right_node) {
        my $cmp = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Greater',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => {
                left => { op => 'NodeRef', node_id => $left_node->id },
                right => { op => 'NodeRef', node_id => $right_node->id }
            }
        );
        $graph->add_node($cmp);
        return $cmp;
    }

    method build_less_node($left_node, $right_node) {
        my $cmp = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Less',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => {
                left => { op => 'NodeRef', node_id => $left_node->id },
                right => { op => 'NodeRef', node_id => $right_node->id }
            }
        );
        $graph->add_node($cmp);
        return $cmp;
    }

    method build_equal_node($left_node, $right_node) {
        my $cmp = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Equal',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => {
                left => { op => 'NodeRef', node_id => $left_node->id },
                right => { op => 'NodeRef', node_id => $right_node->id }
            }
        );
        $graph->add_node($cmp);
        return $cmp;
    }

    # Control flow nodes
    method build_if_node($condition_node) {
        my $if_node = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'If',
            inputs => [$current_control, $condition_node->id],
            attributes => {
                condition => { op => 'NodeRef', node_id => $condition_node->id }
            }
        );
        $graph->add_node($if_node);
        return $if_node;
    }

    method build_if_true_node($if_node) {
        my $if_true = $self->build_proj_node($if_node, 0, 'IfTrue');
        return $if_true;
    }

    method build_if_false_node($if_node) {
        my $if_false = $self->build_proj_node($if_node, 1, 'IfFalse');
        return $if_false;
    }

    method build_region_node(@control_inputs) {
        my $region = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Region',
            inputs => \@control_inputs,
            attributes => {}
        );
        $graph->add_node($region);
        return $region;
    }

    method build_phi_node($region_node, @value_inputs) {
        my $phi = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Phi',
            inputs => [$region_node->id, @value_inputs],
            attributes => {}
        );
        $graph->add_node($phi);
        return $phi;
    }

    # Loop control flow nodes
    method build_loop_node($entry_control = undef) {
        my $ctrl = $entry_control // $current_control // '__CONTROL_PLACEHOLDER__';
        my $loop = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Loop',
            inputs => [$ctrl],  # Entry control; backedge added later
            attributes => {}
        );
        $graph->add_node($loop);
        return $loop;
    }

    method build_loop_phi_node($loop_node, $initial_value, $loop_value = undef) {
        # Loop phi starts with control and initial value
        # Loop value added later (lazy phi pattern)
        my @inputs = ($loop_node->id, $initial_value);
        push @inputs, $loop_value if defined $loop_value;

        my $phi = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Phi',
            inputs => \@inputs,
            attributes => {}
        );
        $graph->add_node($phi);
        return $phi;
    }

    # Function call nodes
    method build_call_node($function_name, @arg_nodes) {
        # Call: control, memory, arguments...
        # For now, use current_control for both control and memory
        my $call = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Call',
            inputs => [$current_control, $current_control, map { $_->id } @arg_nodes],
            attributes => { function => $function_name }
        );
        $graph->add_node($call);
        return $call;
    }
}

1;
