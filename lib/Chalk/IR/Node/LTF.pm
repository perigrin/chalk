# ABOUTME: Float less-than comparison node in the IR graph
# ABOUTME: Represents < comparison between two float values, returns integer (0 or 1)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::LTF {

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

    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'LTF' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'LTF',
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
        return ($left_val < $right_val) ? 1 : 0;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            my $result = ($left_type->value < $right_type->value) ? 1 : 0;
            return Chalk::IR::Type::Integer->constant($result);
        }

        return Chalk::IR::Type::Top->top();
    }

    method peephole($graph = undef) {
        # Step 1: Constant folding via compute()
        my $type = $self->compute();
        if ($type->is_constant) {
            return Chalk::IR::Node::Constant->new(
                value => $type->value,
                type  => Chalk::IR::Type::Integer->constant($type->value),
            );
        }

        # Step 2: Algebraic simplification via idealize()
        if (my $idealized = $self->idealize()) {
            return $idealized->peephole();
        }

        return $self;
    }

    # Algebraic simplification for float less-than comparison
    method idealize() {
        # x < x -> 0 (self-comparison: nothing is less than itself)
        if ($left->id eq $right->id) {
            return Chalk::IR::Node::Constant->new(
                value => 0,
                type  => Chalk::IR::Type::Integer->constant(0),
            );
        }
        return;
    }

    method record_transform(@args) {
        return;
    }
}

1;
