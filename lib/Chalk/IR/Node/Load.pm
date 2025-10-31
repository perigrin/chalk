# ABOUTME: Load node for heap memory read operations - currently unused by Builder
# ABOUTME: Reserved for future heap-allocated data (arrays, hashes, objects); local variables use SSA-style data flow
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
