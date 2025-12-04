# ABOUTME: Float constant value node in the IR graph
# ABOUTME: Represents compile-time floating-point constant values
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ConstantF {
    use Chalk::IR::Type::Float;

    field $value :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    # No inputs for constants (leaf nodes)
    method inputs() { return []; }

    method op() { 'ConstantF' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ConstantF',
            inputs => [],
            attributes => {
                value => $value,
                type  => Chalk::IR::Type::Float->constant($value),
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

    method peephole($graph = undef) {
        return $self;
    }

    # Return type for constant folding - constants always have known type
    method compute() {
        return Chalk::IR::Type::Float->constant($value);
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
