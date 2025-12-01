# ABOUTME: Phi node in the IR graph
# ABOUTME: Represents SSA phi function that selects value based on control flow path
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Phi :isa(Chalk::IR::Node::Base) {
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
        # Per Sea of Nodes: "RegionNodes keep their control inputs in sync with PhiNodes"
        # inputs[0] = region_id (not a data value)
        # inputs[1..n] = data values corresponding to Region's control inputs
        my @inputs = $self->inputs->@*;

        # Get the Region node to check its Proj inputs
        my $graph = $context->("graph:");
        my $region_node = $graph->nodes->{$region_id};
        my $region_inputs = $region_node->inputs;

        # Find which Proj returned 1 (active path)
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

        return $self;
    }
}

1;
