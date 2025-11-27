# ABOUTME: Constant value node in the IR graph
# ABOUTME: Represents compile-time constant values (integers, strings, etc.)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Constant {
    field $value :param :reader;
    field $type  :param :reader;
    # Accept but ignore legacy params for backward compatibility
    field $id :param = undef;
    field $inputs :param = undef;
    field $source_info :param :reader = undef;
    field $computed_id;

    # Content-addressable ID computed from type and value
    method id() {
        return $computed_id //= "const_${type}_${value}";
    }

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

    # Stub for transform tracking (not used in v2 but called by Builder)
    method record_transform(@args) {
        # No-op for compatibility
        return;
    }

    method get_transform_chain() {
        return [];
    }
}

1;
