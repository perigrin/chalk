# ABOUTME: Load node in the IR graph
# ABOUTME: Represents memory read operation retrieving a value from an address in the heap
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Load :isa(Chalk::IR::Node::Base) {
    method op() { 'Load' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Load',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($values, $heap) {
        # Load reads value from heap at address
        # inputs[0] = memory_in (dependency token from prior Store)
        # inputs[1] = address node
        my @inputs = $self->inputs->@*;

        my $address = $values->{$inputs[1]};

        # Read from heap
        my $value = $heap->{$address};

        return $value;
    }
}

1;
