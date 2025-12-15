# ABOUTME: Greater Than or Equal comparison node in the IR graph
# ABOUTME: Represents >= comparison between two values, returns native bool
use 5.42.0;
use experimental qw(class);
use utf8;
use Chalk::IR::Type::Bool;

class Chalk::IR::Node::GE {

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

    method op() { 'GE' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'GE',
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
        return ($left_val >= $right_val) ? true : false;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            my $result = $left_type->value >= $right_type->value;
            return Chalk::IR::Type::Bool->constant($result);
        }

        return Chalk::IR::Type::Top->top();
    }

    method peephole($graph = undef) {
        # Step 1: Constant folding via compute()
        my $type = $self->compute();
        if ($type->is_constant) {
            return Chalk::IR::Node::Constant->new(
                value => $type->value,
                type  => Chalk::IR::Type::Bool->constant($type->value),
            );
        }

        # Step 2: Algebraic simplification via idealize()
        if (my $idealized = $self->idealize()) {
            return $idealized->peephole();
        }

        return $self;
    }

    # Algebraic simplification for greater-than-or-equal comparison
    method idealize() {
        # x >= x -> true (self-comparison)
        if ($left->id eq $right->id) {
            return Chalk::IR::Node::Constant->new(
                value => true,
                type => Chalk::IR::Type::Bool->constant(true)
            );
        }
        return;
    }

    method record_transform(@args) {
        return;
    }
}

1;
