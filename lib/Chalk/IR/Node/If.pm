# ABOUTME: Conditional branch node in the IR graph
# ABOUTME: Represents if/then control flow split based on a boolean condition
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::If :isa(Chalk::IR::Node::Base) {
    field $condition_id :param :reader;

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

    method execute($values) {
        # If node returns the condition value (1 or 0)
        # This tells Proj nodes which path is active
        return $values->{$condition_id};
    }
}

1;
