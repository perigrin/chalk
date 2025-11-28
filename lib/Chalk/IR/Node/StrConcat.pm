# ABOUTME: Binary string concatenation node in the IR graph
# ABOUTME: Represents concatenation of two string operands (left . right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::StrConcat {
    # v2-style direct node references
    field $left :param :reader = undef;
    field $right :param :reader = undef;

    # v1 backward compat: allow string ID params
    field $left_id :param :reader = undef;
    field $right_id :param :reader = undef;

    # Accept but ignore legacy id/inputs params
    field $id :param = undef;
    field $inputs :param = undef;
    field $source_info :param :reader = undef;

    field $computed_id;

    ADJUST {
        # Normalize: left <-> left_id (prefer objects when available)
        $left //= undef;  # Keep as-is
        $right //= undef;  # Keep as-is
    }

    # Content-addressable ID computed from operand IDs
    method id() {
        return $computed_id if defined $computed_id;

        my $l_id = defined($left) && blessed($left) && $left->can('id') ? $left->id : ($left_id // 'none');
        my $r_id = defined($right) && blessed($right) && $right->can('id') ? $right->id : ($right_id // 'none');

        return $computed_id = "concat_${l_id}_${r_id}";
    }

    # Compute inputs from child nodes
    method inputs() {
        my @inputs;
        if (defined($left) && blessed($left) && $left->can('id')) {
            push @inputs, $left->id;
        } elsif (defined($left_id)) {
            push @inputs, $left_id;
        }
        if (defined($right) && blessed($right) && $right->can('id')) {
            push @inputs, $right->id;
        } elsif (defined($right_id)) {
            push @inputs, $right_id;
        }
        return \@inputs;
    }

    method op() { 'StrConcat' }

    method to_hash() {
        my $l_id = defined($left) && blessed($left) && $left->can('id') ? $left->id : $left_id;
        my $r_id = defined($right) && blessed($right) && $right->can('id') ? $right->id : $right_id;

        return {
            id     => $self->id,
            op     => 'StrConcat',
            inputs => $self->inputs,
            attributes => {
                left_id  => $l_id,
                right_id => $r_id,
            },
        };
    }

    method execute($context) {
        my $l_id = defined($left) && blessed($left) && $left->can('id') ? $left->id : $left_id;
        my $r_id = defined($right) && blessed($right) && $right->can('id') ? $right->id : $right_id;
        my $left_val = $context->("node:$l_id");
        my $right_val = $context->("node:$r_id");
        return $left_val . $right_val;
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
