# ABOUTME: Phi node in the IR graph
# ABOUTME: Represents SSA phi function that selects value based on control flow path
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Phi :isa(Chalk::IR::Node::Base) {
    use Chalk::IR::Node::Add;
    use Chalk::IR::Node::Multiply;
    use Chalk::IR::Node::Subtract;
    use Chalk::IR::Node::Divide;
    field $region_id :param :reader;

    method op() { 'Phi' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Phi',
            inputs => $self->inputs,
            attributes => {
                region_id => $region_id,
            },
        };
    }

    method execute($context) {
        # Phi selects value based on which Region input path is active
        # For Loop regions, use the Loop's active_input_index directly
        # For regular Regions, find which Proj returned 1
        my @inputs = $self->inputs->@*;

        # Get the Region/Loop node
        my $graph = $context->("graph:");
        my $region_node = $graph->nodes->{$region_id};

        # Special handling for Loop regions
        if ($region_node->op eq 'Loop') {
            # Use Loop's active_input_index directly
            my $idx = $region_node->active_input_index;
            my $value_index = $idx + 1;  # inputs[0] is region_id, inputs[1] is entry, inputs[2] is backedge
            if ($value_index >= @inputs) {
                die "Phi node: Loop active path $idx out of range (only " . (@inputs - 1) . " data inputs)";
            }
            my $value_id = $inputs[$value_index];
            return $context->("node:$value_id");
        }

        # For regular Regions, find which Proj returned 1 (active path)
        my $region_inputs = $region_node->inputs;

        for my $i (0..$#$region_inputs) {
            my $proj_id = $region_inputs->[$i];
            my $proj_result = $context->("node:$proj_id");

            if ($proj_result == 1) {
                # This is the active path - select corresponding data value
                # Phi inputs are offset by 1 (input[0] is region, input[1] is first value)
                my $value_index = $i + 1;
                if ($value_index >= @inputs) {
                    die "Phi node: active path $i out of range";
                }
                my $value_id = $inputs[$value_index];
                return $context->("node:$value_id");
            }
        }

        die "Phi node: no active path found in Region $region_id";
    }

    # Peephole optimization for Phi nodes
    # If only one Region input is live, simplify to the corresponding value
    method peephole($graph = undef) {
        return $self unless $graph;

        my @inputs = $self->inputs->@*;

        # singleUniqueInput optimization: if all data inputs are the same node, return that node
        # Data inputs start at index 1 (index 0 is region_id)
        # BUT only for Region-based phis, not Loop-based phis
        if (@inputs > 1) {
            # Check if control is a Loop - if so, don't apply singleUniqueInput
            my $control_node = $graph->get_node($region_id);
            my $is_loop = $control_node && $control_node->op eq 'Loop';

            if (!$is_loop) {
                my @data_inputs = @inputs[1..$#inputs];
                my $first = $data_inputs[0];
                my $all_same = 1;
                for my $input (@data_inputs[1..$#data_inputs]) {
                    if ($input ne $first) {
                        $all_same = 0;
                        last;
                    }
                }
                if ($all_same && defined $first) {
                    my $node = $graph->get_node($first);
                    return $node if $node;
                }
            }
        }

        # Get the Region node
        my $region_node = $graph->get_node($region_id);
        return $self unless $region_node;

        # Get live input indices from Region
        return $self unless $region_node->can('get_live_input_indices');
        my @live_indices = $region_node->get_live_input_indices($graph);

        # If only one live input, return the corresponding Phi value
        if (@live_indices == 1) {
            my $live_idx = $live_indices[0];
            my @inputs = $self->inputs->@*;

            # Phi inputs: [region_id, value1, value2, ...]
            # Region inputs: [ctrl1, ctrl2, ...]
            # value at index i+1 corresponds to Region input at index i
            my $value_idx = $live_idx + 1;

            if ($value_idx < @inputs) {
                my $value_id = $inputs[$value_idx];
                my $value_node = $graph->get_node($value_id);
                return $value_node if $value_node;
            }
        }

        # Operation pulling: Phi(region, Op(a,b), Op(c,d)) -> Op(Phi(region,a,c), Phi(region,b,d))
        if (my $idealized = $self->idealize($graph)) {
            return $idealized->peephole($graph);
        }

        return $self;
    }

    # Idealize: algebraic simplification for Phi nodes
    # Implements operation pulling optimization from Simple compiler
    method idealize($graph = undef) {
        return unless $graph;

        my @inputs = $self->inputs->@*;
        return unless @inputs > 2;  # Need region + at least 2 data inputs

        # Check if control is a Loop - if so, don't apply operation pulling
        my $control_node = $graph->get_node($region_id);
        return if $control_node && $control_node->op eq 'Loop';

        # Get all data input nodes
        my @data_inputs = @inputs[1..$#inputs];
        my @data_nodes = map { $graph->get_node($_) } @data_inputs;

        # Verify all data input nodes exist
        return if grep { !defined $_ } @data_nodes;

        # Check if all data inputs have the same operation type
        my $first_op = $data_nodes[0]->op;

        # Skip CFG nodes - only pull data operations
        my %cfg_ops = (
            Region => 1, Loop => 1, If => 1, Proj => 1,
            Start => 1, Return => 1, Stop => 1,
        );
        return if $cfg_ops{$first_op};

        # Skip Phi and Constant - no benefit from pulling these
        return if $first_op eq 'Phi';
        return if $first_op eq 'Constant';

        # Check all inputs have the same op
        for my $node (@data_nodes[1..$#data_nodes]) {
            return unless $node->op eq $first_op;
        }

        # Check all operations have left/right accessors (binary ops)
        for my $node (@data_nodes) {
            return unless $node->can('left') && $node->can('right');
        }

        # All data inputs have the same binary operation
        # Create new Phi nodes for left and right operands

        # Collect left operands from each input
        my @left_nodes = map { $_->left } @data_nodes;
        my @left_ids = map { $_->id } @left_nodes;

        # Collect right operands from each input
        my @right_nodes = map { $_->right } @data_nodes;
        my @right_ids = map { $_->id } @right_nodes;

        # Create Phi for left operands
        my $left_phi = Chalk::IR::Node::Phi->new(
            region_id => $region_id,
            inputs => [$region_id, @left_ids],
        );
        $graph->add_node($left_phi);

        # Create Phi for right operands
        my $right_phi = Chalk::IR::Node::Phi->new(
            region_id => $region_id,
            inputs => [$region_id, @right_ids],
        );
        $graph->add_node($right_phi);

        # Create the pulled-out operation with the new Phi nodes
        my %op_class = (
            Add      => 'Chalk::IR::Node::Add',
            Subtract => 'Chalk::IR::Node::Subtract',
            Multiply => 'Chalk::IR::Node::Multiply',
            Divide   => 'Chalk::IR::Node::Divide',
        );

        my $op_class = $op_class{$first_op};
        return unless $op_class;

        my $new_op = $op_class->new(
            left  => $left_phi,
            right => $right_phi,
        );
        $graph->add_node($new_op);

        return $new_op;
    }
}

1;
