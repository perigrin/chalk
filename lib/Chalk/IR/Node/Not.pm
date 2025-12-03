# ABOUTME: Logical negation node in the IR graph
# ABOUTME: Represents boolean negation of a single operand, returns native bool
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Not {
    use Chalk::IR::Type::Bool;
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

    method id() { refaddr($self) }

    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'Not' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Not',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $operand_val = $context->("node:" . $operand->id);
        return $operand_val ? false : true;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        my $operand_type = $operand->compute();
        if ($operand_type->is_constant) {
            my $result = $operand_type->value ? false : true;
            return Chalk::IR::Type::Bool->constant($result);
        }
        return Chalk::IR::Type::Top->top();
    }

    method peephole($graph = undef) {
        my $type = $self->compute();
        if ($type->is_constant) {
            return Chalk::IR::Node::Constant->new(
                value => $type->value,
                type  => 'Bool',
            );
        }
        return $self;
    }

    method record_transform(@args) {
        return;
    }

}

1;
