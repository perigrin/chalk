# ABOUTME: Equal comparison node in the IR graph
# ABOUTME: Represents == equality comparison between two values
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::EQ :isa(Chalk::IR::Node::Base) {
    field $left_id  :param :reader;
    field $right_id :param :reader;

    method op() { 'EQ' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'EQ',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left_id,
                right_id => $right_id,
            },
        };
    }

    method execute($values) {
        my $left_val = $values->{$left_id};
        my $right_val = $values->{$right_id};
        return ($left_val == $right_val) ? 1 : 0;
    }
}

1;
