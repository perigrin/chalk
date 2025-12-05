# ABOUTME: Unary float negation node in the IR graph
# ABOUTME: Represents negation of a float operand (-x)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::MinusF {
    use Chalk::IR::Type::Float;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Node::Constant;

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

    ADJUST {
        die "operand is required" unless defined $operand;
        die "operand must have id()" unless blessed($operand) && $operand->can('id');
    }

    method id() { refaddr($self) }

    # Compute inputs from child nodes
    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'MinusF' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'MinusF',
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
        # Step 1: Algebraic simplification via idealize()
        # Check this first to preserve node identity (e.g., -(-x) = x, not new constant)
        if (my $idealized = $self->idealize()) {
            return $idealized->peephole();
        }

        # Step 2: Constant folding via compute()
        my $type = $self->compute();
        if ($type->is_constant) {
            return Chalk::IR::Node::Constant->new(
                type  => $type,
                value => $type->value,
            );
        }

        return $self;
    }

    # Type inference for constant folding - if input is constant, compute negation
    method compute() {
        my $operand_type = $operand->compute();

        if ($operand_type->is_constant) {
            return Chalk::IR::Type::Float->constant(
                -$operand_type->value
            );
        }

        # If operand is a float type, result is unknown float
        if ($operand_type isa Chalk::IR::Type::Float) {
            return Chalk::IR::Type::Float->TOP();
        }

        return Chalk::IR::Type::Top->top();
    }

    # Algebraic simplification for float negation
    method idealize() {
        # -(-x) -> x (double negation elimination)
        if ($operand isa Chalk::IR::Node::MinusF) {
            return $operand->operand;
        }

        return;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
