# ABOUTME: Truncate node narrows integers from wider to narrower types
# ABOUTME: Implements bit masking with optional sign extension
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Truncate {
    field $operand :param :reader;
    field $target_type :param :reader;
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

    method op() { 'Truncate' }

    method to_hash() {
        return {
            id => $self->id,
            op => 'Truncate',
            inputs => $self->inputs,
            attributes => {
                target_bits => $target_type->bits,
                target_signed => $target_type->signed,
            },
        };
    }

    method peephole($graph = undef) {
        # Constant folding
        if ($operand->isa('Chalk::IR::Node::Constant')) {
            my $val = $operand->value;
            my $mask = $target_type->mask;
            my $truncated = $val & $mask;

            # Sign extend if signed and high bit set
            if ($target_type->signed && ($truncated & $target_type->sign_bit)) {
                # Convert to signed by subtracting 2^bits
                $truncated = $truncated - (1 << $target_type->bits);
            }

            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $truncated,
                type => $target_type
            );
        }

        return $self;
    }

    method compute_type() {
        return $target_type;
    }

    # Compatibility methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method record_transform(@args) {
        return;
    }

    method clone_with_inputs($new_inputs, $node_map, $new_attributes = {}) {
        my $new_operand = $node_map->{$new_inputs->[0]};
        die "Operand not found in node_map: $new_inputs->[0]" unless $new_operand;

        return Chalk::IR::Node::Truncate->new(
            operand     => $new_operand,
            target_type => $new_attributes->{target_type} // $target_type,
            source_info => $source_info,
        );
    }
}

1;
