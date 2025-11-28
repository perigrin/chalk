# ABOUTME: Unary negation node in the IR graph
# ABOUTME: Represents negation of a single operand (-operand)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Negate {
    # v2-style direct node reference
    field $operand :param :reader = undef;

    # v1 backward compat: allow string ID param
    field $operand_id :param :reader = undef;

    # Accept but ignore legacy id/inputs params
    field $id :param = undef;
    field $inputs :param = undef;
    field $source_info :param :reader = undef;

    field $computed_id;

    ADJUST {
        # Normalize: operand stays as-is (prefer object when available)
        $operand //= undef;  # Keep as-is
    }

    # Content-addressable ID computed from operand ID
    method id() {
        return $computed_id if defined $computed_id;

        my $op_id = defined($operand) && blessed($operand) && $operand->can('id') ? $operand->id : ($operand_id // 'none');

        return $computed_id = "neg_${op_id}";
    }

    # Compute inputs from child node
    method inputs() {
        my @inputs;
        if (defined($operand) && blessed($operand) && $operand->can('id')) {
            push @inputs, $operand->id;
        } elsif (defined($operand_id)) {
            push @inputs, $operand_id;
        }
        return \@inputs;
    }

    method op() { 'Negate' }

    method to_hash() {
        my $op_id = defined($operand) && blessed($operand) && $operand->can('id') ? $operand->id : $operand_id;

        return {
            id     => $self->id,
            op     => 'Negate',
            inputs => $self->inputs,
            attributes => {
                operand_id => $op_id,
            },
        };
    }

    method execute($context) {
        my $op_id = defined($operand) && blessed($operand) && $operand->can('id') ? $operand->id : $operand_id;
        my $operand_val = $context->("node:$op_id");
        return -$operand_val;
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph) {
        return $self;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

    method get_transform_chain() {
        return [];
    }
}

1;
