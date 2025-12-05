# ABOUTME: Type conversion node: integer to float
# ABOUTME: Wraps integer expressions for automatic widening in float contexts
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ToFloat {
    use Chalk::IR::Type::Float;
    use Chalk::IR::Type::Integer;
    use Chalk::IR::Node::ConstantF;

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
            return Chalk::IR::Node::ConstantF->new(
                value => $type->value,
            );
        }

        # No idealize() needed for ToFloat - it's already minimal
        return $self;
    }

    # Type inference: convert integer constant to float constant
    method compute() {
        my $operand_type = $operand->compute();

        # If operand is a constant integer, convert to constant float
        if ($operand_type->isa('Chalk::IR::Type::Integer') && $operand_type->is_constant) {
            return Chalk::IR::Type::Float->constant($operand_type->value + 0.0);
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
