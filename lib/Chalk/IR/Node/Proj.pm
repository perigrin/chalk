# ABOUTME: Projection node in the IR graph
# ABOUTME: Represents extraction of a specific control or data path from a multi-way node
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Proj :isa(Chalk::IR::Node::Base) {
    use Chalk::IR::Type::Top;

    field $index  :param :reader;
    field $label  :param :reader;
    # Object reference to source node (If) for graph traversal
    field $source :param :reader = undef;
    # Early returns collected from the branch this Proj controls (immutable)
    # Passed at construction time by ConditionalStatement after rewiring
    # This enables Program.pm to find Returns inside if-blocks
    field $early_returns :param :reader = undef;

    method op() { 'Proj' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Proj',
            inputs => $self->inputs,
            attributes => {
                index => $index,
                label => $label,
            },
        };
    }

    method execute($context) {
        # Proj extracts a control path from If node
        # Returns 1 if this path is active, 0 otherwise
        # Index 0 = true branch (IfTrue), Index 1 = false branch (IfFalse)
        # If result: 1 = true (condition met), 0 = false (condition not met)
        my $source_id = $self->inputs->[0];
        my $if_result = $context->("node:$source_id");

        # Check if this projection matches the active path
        # True condition (if_result=1) activates index 0 (IfTrue)
        # False condition (if_result=0) activates index 1 (IfFalse)
        # Return 0 when if_result matches index (inactive), 1 otherwise (active)
        # Coerce if_result to boolean (0 or 1) to avoid warnings on non-numeric values
        my $if_bool = $if_result ? 1 : 0;
        return ($if_bool == $index) ? 0 : 1;
    }

    method compute() {
        return Chalk::IR::Type::Top->top() unless $source;

        my $source_type = $source->compute();

        # Extract type at index from tuple
        if ($source_type->can('at')) {
            return $source_type->at($index);
        }

        return Chalk::IR::Type::Top->top();
    }

    # Peephole optimization for Proj nodes
    # If source is an If with constant condition, detect if this branch is dead
    # Dead branches return a ~Ctrl constant; live branches pass through control
    method peephole($graph = undef) {
        return $self unless $graph;

        # Get source node (should be an If)
        my $source_id = $self->inputs->[0];
        return $self unless $source_id;

        my $source_node = $source // $graph->get_node($source_id);
        return $self unless $source_node;

        # Only optimize if source is an If node
        return $self unless $source_node->op eq 'If';

        # Check if the If node has a constant condition
        if ($source_node->can('is_constant_condition')) {
            my ($is_const, $cond_value) = $source_node->is_constant_condition($graph);

            if ($is_const) {
                # cond_value: 1 = true (take true branch), 0 = false (take false branch)
                # index: 0 = true branch (IfTrue), 1 = false branch (IfFalse)
                #
                # If condition is true (1): index 0 is live, index 1 is dead
                # If condition is false (0): index 0 is dead, index 1 is live
                my $is_live = ($cond_value == 1 && $index == 0) ||
                              ($cond_value == 0 && $index == 1);

                if ($is_live) {
                    # Live branch: pass through to the control input of the If node
                    my $if_inputs = $source_node->inputs;
                    if ($if_inputs && $if_inputs->[0]) {
                        my $ctrl_node = $graph->get_node($if_inputs->[0]);
                        return $ctrl_node if $ctrl_node;
                    }
                } else {
                    # Dead branch: return a ~Ctrl constant
                    return Chalk::IR::Node::Constant->new(
                        value => '~Ctrl',
                        type  => 'Control',
                    );
                }
            }
        }

        return $self;
    }
}

1;
