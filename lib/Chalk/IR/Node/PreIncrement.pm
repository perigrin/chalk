# ABOUTME: Pre-increment node in the IR graph
# ABOUTME: Represents pre-increment operation (++$var) - increments then returns new value
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::PreIncrement {
    field $operand :param :reader;
    field $source_info :param :reader = undef;

    field $id :reader = "preincr_" . $operand->id;

    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'PreIncrement' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'PreIncrement',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $val = $context->("node:" . $operand->id);
        return $val + 1;  # Pre-increment: return incremented value
    }

    # Compatibility methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph) {
        return $self;
    }

    method record_transform(@args) {
        return;
    }

    method get_transform_chain() {
        return [];
    }
}

1;
