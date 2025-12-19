# ABOUTME: BitNot node performs bitwise NOT (complement) operation
# ABOUTME: Unary operator that inverts all bits
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::BitNot {
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

    method op() { 'BitNot' }

    method to_hash() {
        return {
            id => $self->id,
            op => 'BitNot',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method peephole($graph = undef) {
        # Constant folding
        if ($operand->isa('Chalk::IR::Node::Constant')) {
            my $val = $operand->value;
            my $result;
            {
                use integer;
                $result = ~$val;
            }
            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $result,
                type => $operand->type // Chalk::IR::Type::Integer->i64()
            );
        }

        # Double negation: ~~x = x
        if ($operand->isa('Chalk::IR::Node::BitNot')) {
            return $operand->operand;
        }

        return $self;
    }

    method compute_type() {
        return $operand->compute_type if $operand->can('compute_type');
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
        my $new_operand = $node_map->{$new_inputs->[0]};
        die "Operand not found in node_map: $new_inputs->[0]" unless $new_operand;

        return Chalk::IR::Node::BitNot->new(
            operand     => $new_operand,
            source_info => $source_info,
        );
    }
}

1;
