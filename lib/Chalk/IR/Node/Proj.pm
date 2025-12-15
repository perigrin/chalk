# ABOUTME: Projection node in the IR graph
# ABOUTME: Represents extraction of a specific control or data path from a multi-way node
use 5.42.0;
use experimental qw(class);
use utf8;
use Chalk::IR::Type::Ctrl;

class Chalk::IR::Node::Proj :isa(Chalk::IR::Node::Base) {

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
                        type  => Chalk::IR::Type::Ctrl->CTRL(),
                    );
                }
            }
        }

        return $self;
    }

    # Dominator tree: Proj's immediate dominator depends on source type
    # For Proj from If: idom is the If's control input (not the If itself)
    # For Proj from Start: idom is Start itself
    # Caches result for efficiency
    field $_idom :reader = undef;
    field $_idepth :reader = undef;

    method idom() {
        return $_idom if defined $_idom;

        return undef unless $source;

        # If source is Start, this Proj's idom IS the Start node
        if ($source->op eq 'Start') {
            $_idom = $source;
            return $_idom;
        }

        # If source is an If node, the Proj's idom is the If's control input
        if ($source->op eq 'If' && $source->can('control')) {
            $_idom = $source->control;
            return $_idom;
        }

        # Default: try source's idom if it has one
        if ($source->can('idom')) {
            $_idom = $source->idom;
            return $_idom;
        }

        return undef;
    }

    method idepth() {
        return $_idepth if defined $_idepth;

        my $dom = $self->idom();
        return 0 unless $dom;

        if ($dom->can('idepth')) {
            $_idepth = $dom->idepth() + 1;
        } else {
            $_idepth = 1;  # Default if idom doesn't support idepth
        }

        return $_idepth;
    }
}

1;
