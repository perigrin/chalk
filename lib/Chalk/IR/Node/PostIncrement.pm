# ABOUTME: Post-increment node in the IR graph
# ABOUTME: Represents post-increment operation ($var++) - returns current value then increments
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::PostIncrement {
    field $operand :param :reader;
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

    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'PostIncrement' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'PostIncrement',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $val = $context->("node:" . $operand->id);
        return $val;  # Post-increment: return original value (increment happens as side effect)
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
