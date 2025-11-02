# ABOUTME: Binary division node in the IR graph
# ABOUTME: Represents division of two operands (left / right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Divide :isa(Chalk::IR::Node::Base) {
    field $left_id  :param :reader;
    field $right_id :param :reader;

    method op() { 'Divide' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Divide',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left_id,
                right_id => $right_id,
            },
        };
    }

    method execute($context) {
        my $left_val = $context->("node:$left_id");
        my $right_val = $context->("node:$right_id");
        return $left_val / $right_val;
    }
}

1;
