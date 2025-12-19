# ABOUTME: ZeroExtend node widens unsigned integers padding with zeros
# ABOUTME: Used when loading from narrower unsigned types
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ZeroExtend {
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

    method op() { 'ZeroExtend' }

    method to_hash() {
        return {
            id => $self->id,
            op => 'ZeroExtend',
            inputs => $self->inputs,
            attributes => {
                target_bits => $target_type->bits,
            },
        };
    }

    method peephole($graph = undef) {
        # Constant folding
        if ($operand isa Chalk::IR::Node::Constant) {
            my $val = $operand->value;
            # Mask to source type's range to ensure positive
            my $source_type = $operand->type;
            if ($source_type && $source_type->can('mask')) {
                $val = $val & $source_type->mask;
            }

            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $val,
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

        return Chalk::IR::Node::ZeroExtend->new(
            operand     => $new_operand,
            target_type => $new_attributes->{target_type} // $target_type,
            source_info => $source_info,
        );
    }
}

1;
