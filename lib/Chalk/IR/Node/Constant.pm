# ABOUTME: Constant value node in the IR graph
# ABOUTME: Represents compile-time constant values (integers, strings, etc.)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Constant {
    field $value :param :reader;
    field $type  :param :reader;
    field $source_info :param :reader = undef;

    field $id :reader = "const_" . $type . "_" . $value;

    # No inputs for constants (leaf nodes)
    method inputs() { return []; }

    method op() { 'Constant' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Constant',
            inputs => [],
            attributes => {
                value => $value,
                type  => $type,
            },
        };
    }

    method execute() {
        return $value;
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

    method get_transform_chain() {
        return [];
    }
}

1;
