# ABOUTME: Unary negation node in the IR graph
# ABOUTME: Represents negation of a single operand (-operand)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Negate {

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

    # Compute inputs from child node
    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'Negate' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Negate',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $operand_val = $context->("node:" . $operand->id);
        return -$operand_val;
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # Step 1: Constant folding via compute()
        my $type = $self->compute();
        if ($type->is_constant) {
            return Chalk::IR::Node::Constant->new(
                value => $type->value,
                type  => 'Integer',
            );
        }

        # Step 2: Algebraic simplification via idealize()
        if (my $idealized = $self->idealize()) {
            return $idealized->peephole();
        }

        return $self;
    }

    # Type inference for constant folding - if input is constant, compute negation
    method compute() {
        my $operand_type = $operand->compute();

        if ($operand_type->is_constant) {
            return Chalk::IR::Type::Integer->constant(
                -$operand_type->value
            );
        }

        # If operand is a TypeInteger, result is unknown integer
        if ($operand_type isa Chalk::IR::Type::Integer) {
            return Chalk::IR::Type::Integer->TOP();
        }

        return Chalk::IR::Type::Top->top();
    }

    # Algebraic simplification for negation - no optimizations in chapter04
    method idealize() {
        return;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
