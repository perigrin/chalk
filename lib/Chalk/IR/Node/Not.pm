# ABOUTME: Logical negation node in the IR graph
# ABOUTME: Represents boolean negation of a single operand (!operand or not operand)
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Not :isa(Chalk::IR::Node::Base) {
    field $operand_id :param :reader;

    method op() { 'Not' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Not',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand_id,
            },
        };
    }

    method execute($values) {
        my $operand_val = $values->{$operand_id};
        # Perl 5.42.0 returns boolean objects, but for now return 1/0
        # TODO: Update to return proper boolean when boolean IR nodes are implemented
        return $operand_val ? 0 : 1;
    }
}

1;
