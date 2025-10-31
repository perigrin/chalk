# ABOUTME: Unary negation node in the IR graph
# ABOUTME: Represents negation of a single operand (-operand)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Negate :isa(Chalk::IR::Node::Base) {
    field $operand_id :param :reader;

    method op() { 'Negate' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Negate',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand_id,
            },
        };
    }

    method execute($values) {
        my $operand_val = $values->{$operand_id};
        return -$operand_val;
    }
}

1;
