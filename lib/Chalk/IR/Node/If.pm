# ABOUTME: Conditional branch node in the IR graph
# ABOUTME: Represents if/then control flow split based on a boolean condition
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::If :isa(Chalk::IR::Node::Base) {
    field $condition_id :param :reader;
    # Object reference to condition node for graph traversal
    field $condition :param :reader = undef;
    # Object reference to control input for graph traversal
    # This enables BFS to find the Start/Store node that controls this If
    field $control :param :reader = undef;

    method op() { 'If' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'If',
            inputs => $self->inputs,
            attributes => {
                condition_id => $condition_id,
            },
        };
    }

    method execute($context) {
        # If node returns the condition value (1 or 0)
        # This tells Proj nodes which path is active
        return $context->("node:$condition_id");
    }
}

1;
