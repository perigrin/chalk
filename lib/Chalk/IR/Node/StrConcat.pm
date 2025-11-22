# ABOUTME: Binary string concatenation node in the IR graph
# ABOUTME: Represents concatenation of two string operands (left . right)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::StrConcat :isa(Chalk::IR::Node::Base) {
    field $left_id  :param :reader;
    field $right_id :param :reader;

    method op() { 'StrConcat' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'StrConcat',
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
        return $left_val . $right_val;
    }
}

1;
