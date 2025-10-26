# ABOUTME: Reference node in the IR graph
# ABOUTME: Represents reference operator (\$var) - creates a reference to a variable
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Reference :isa(Chalk::IR::Node::Base) {
    field $operand_id :param :reader;

    method op() { 'Reference' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Reference',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand_id,
            },
        };
    }
}

1;
