# ABOUTME: Not Equal comparison node in the IR graph
# ABOUTME: Represents != inequality comparison between two values
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::NE {
    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    # Compute inputs from child nodes
    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'NE' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'NE',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        my $left_val = $context->("node:" . $left->id);
        my $right_val = $context->("node:" . $right->id);
        return ($left_val != $right_val) ? 1 : 0;
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph) {
        return $self;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
