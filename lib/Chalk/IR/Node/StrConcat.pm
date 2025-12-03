# ABOUTME: Binary string concatenation node in the IR graph
# ABOUTME: Represents concatenation of two string operands (left . right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::StrConcat {
    field $left :param :reader;
    field $right :param :reader;
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

    # Compute inputs from child nodes
    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'StrConcat' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'StrConcat',
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
        return $left_val . $right_val;
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
