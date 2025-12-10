# ABOUTME: Type conversion node: integer/boolean to float
# ABOUTME: Wraps integer and boolean expressions for automatic widening in float contexts
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ToFloat {

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

    # Compute inputs from child node
    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'ToFloat' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ToFloat',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $value = $context->("node:" . $operand->id);
        return $value + 0.0;  # Perl auto-converts to float
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
                type  => $type,
                value => $type->value,
            );
        }

        # No idealize() needed for ToFloat - it's already minimal
        return $self;
    }

    # Type inference: convert integer/boolean constant to float constant
    method compute() {
        my $operand_type = $operand->compute();

        # If operand is a constant integer, convert to constant float
        if ($operand_type->isa('Chalk::IR::Type::Integer') && $operand_type->is_constant) {
            return Chalk::IR::Type::Float->constant($operand_type->value + 0.0);
        }

        # If operand is a constant boolean, convert to constant float
        # true → 1.0, false → 0.0
        if ($operand_type->isa('Chalk::IR::Type::Bool') && $operand_type->is_constant) {
            my $bool_value = $operand_type->value;
            return Chalk::IR::Type::Float->constant($bool_value ? 1.0 : 0.0);
        }

        # Otherwise, return unknown float (TOP)
        return Chalk::IR::Type::Float->TOP();
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

}

1;
