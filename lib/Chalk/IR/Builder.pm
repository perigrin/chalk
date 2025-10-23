# ABOUTME: IR builder for transforming parsed Chalk code into Sea of Nodes IR
# ABOUTME: Provides methods called by semantic actions to build IR nodes during parsing
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);;
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
    method build_return_node($value_node) {
        # Debug: check what we received
        my $ref_type = ref($value_node) || 'SCALAR';
        unless ($ref_type && $ref_type =~ /^Chalk::IR::Node/) {
            use Data::Dumper;
            warn "build_return_node received non-node: $ref_type\n";
            warn "Value: " . Dumper($value_node);
            return undef;
        }

        my $return = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Return',
            inputs => [$current_control, $value_node->id],
            attributes => {}
        );
        $graph->add_node($return);
        return $return;
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
    method build_store_node($var_name, $value_node) {
        my $store = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Store',
            inputs => [$current_control],
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
        my $store_id = $scope->lookup($var_name);
        return undef unless $store_id;

        my $load = Chalk::IR::Node->new(
            id => $self->next_node_id(),
            op => 'Load',
            inputs => [$current_control, $store_id],
            attributes => {
                name => $var_name,
                store_id => $store_id
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
}

1;
