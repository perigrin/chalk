# ABOUTME: Projection node in the IR graph
# ABOUTME: Represents extraction of a specific control or data path from a multi-way node
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Proj :isa(Chalk::IR::Node::Base) {
    field $index  :param :reader;
    field $label  :param :reader;
    # Object reference to source node (If) for graph traversal
    field $source :param :reader = undef;
    # Issue #195 fix: Nodes that use this Proj as their control input
    # This enables forward traversal to find early returns in if-branches
    field $control_users :param :reader = undef;

    # Add a node that uses this Proj as control
    method add_control_user($node) {
        $control_users //= [];
        push $control_users->@*, $node;
    }

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
        return ($if_result == $index) ? 0 : 1;
    }
}

1;
