# ABOUTME: BitAnd node performs bitwise AND operation
# ABOUTME: NOT short-circuit like logical And - evaluates both operands
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::BitAnd {
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

    method op() { 'BitAnd' }

    method to_hash() {
        return {
            id => $self->id,
            op => 'BitAnd',
            inputs => $self->inputs,
            attributes => {
                left_id => $left->id,
                right_id => $right->id,
            },
        };
    }

    method peephole($graph = undef) {
        # Constant folding
        if ($left isa Chalk::IR::Node::Constant &&
            $right isa Chalk::IR::Node::Constant) {

            my $lval = $left->value;
            my $rval = $right->value;

            # Identity: x & -1 = x
            return $left if $rval == -1;
            return $right if $lval == -1;

            # Annihilator: x & 0 = 0
            if ($lval == 0 || $rval == 0) {
                use Chalk::IR::Node::Constant;
                return Chalk::IR::Node::Constant->new(
                    value => 0,
                    type => $left->type // Chalk::IR::Type::Integer->i64()
                );
            }

            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $lval & $rval,
                type => $left->type // Chalk::IR::Type::Integer->i64()
            );
        }

        return $self;
    }

    method compute_type() {
        return $left->compute_type if $left->can('compute_type');
        use Chalk::IR::Type::Integer;
        return Chalk::IR::Type::Integer->TOP();
    }

    # Compatibility methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method record_transform(@args) {
        return;
    }

    method clone_with_inputs($new_inputs, $node_map, $new_attributes = {}) {
        my $new_left = $node_map->{$new_inputs->[0]};
        my $new_right = $node_map->{$new_inputs->[1]};

        die "Left operand not found in node_map: $new_inputs->[0]" unless $new_left;
        die "Right operand not found in node_map: $new_inputs->[1]" unless $new_right;

        return Chalk::IR::Node::BitAnd->new(
            left        => $new_left,
            right       => $new_right,
            source_info => $source_info,
        );
    }
}

1;
