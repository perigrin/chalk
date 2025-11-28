# ABOUTME: Logical negation node in the IR graph
# ABOUTME: Represents boolean negation of a single operand (!operand or not operand)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Not {
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

        return $computed_id = "not_${op_id}";
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

    method op() { 'Not' }

    method to_hash() {
        my $op_id = defined($operand) && blessed($operand) && $operand->can('id') ? $operand->id : $operand_id;

        return {
            id     => $self->id,
            op     => 'Not',
            inputs => $self->inputs,
            attributes => {
                operand_id => $op_id,
            },
        };
    }

    method execute($context) {
        my $op_id = defined($operand) && blessed($operand) && $operand->can('id') ? $operand->id : $operand_id;
        my $operand_val = $context->("node:$op_id");
        # Perl 5.42.0 returns boolean objects, but for now return 1/0
        # TODO: Update to return proper boolean when boolean IR nodes are implemented
        return $operand_val ? 0 : 1;
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
