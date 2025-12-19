# ABOUTME: BitXor node performs bitwise XOR operation
# ABOUTME: Includes identity (x ^ 0 = x) and self-inverse (x ^ x = 0) optimizations
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::BitXor {
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

    method op() { 'BitXor' }

    method to_hash() {
        return {
            id => $self->id,
            op => 'BitXor',
            inputs => $self->inputs,
            attributes => {
                left_id => $left->id,
                right_id => $right->id,
            },
        };
    }

    method peephole($graph = undef) {
        if ($left->isa('Chalk::IR::Node::Constant') &&
            $right->isa('Chalk::IR::Node::Constant')) {

            my $lval = $left->value;
            my $rval = $right->value;

            # Identity: x ^ 0 = x
            return $left if $rval == 0;
            return $right if $lval == 0;

            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $lval ^ $rval,
                type => $left->type // Chalk::IR::Type::Integer->i64()
            );
        }

        # Self-inverse: x ^ x = 0 (same node reference)
        if (refaddr($left) == refaddr($right)) {
            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => 0,
                type => $left->compute_type // Chalk::IR::Type::Integer->i64()
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

        return Chalk::IR::Node::BitXor->new(
            left        => $new_left,
            right       => $new_right,
            source_info => $source_info,
        );
    }
}

1;
