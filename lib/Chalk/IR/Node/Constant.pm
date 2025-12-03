# ABOUTME: Constant value node in the IR graph
# ABOUTME: Represents compile-time constant values (integers, strings, etc.)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Constant {
    use Chalk::IR::Type::Integer;
    use Chalk::IR::Type::Bool;

    field $value :param :reader;
    field $type  :param :reader;
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

    method peephole($graph = undef) {
        return $self;
    }

    # Return type for constant folding - constants always have known type
    method compute() {
        if ($type eq 'Bool') {
            return Chalk::IR::Type::Bool->constant($value);
        }
        return Chalk::IR::Type::Integer->constant($value);
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
