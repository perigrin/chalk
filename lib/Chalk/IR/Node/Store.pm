# ABOUTME: Store node for heap memory write operations - currently unused by Builder
# ABOUTME: Reserved for future heap-allocated data (arrays, hashes, objects); local variables use SSA-style data flow
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Store :isa(Chalk::IR::Node::Base) {
    method op() { 'Store' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Store',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($values, $heap) {
        # Store writes value to heap at address
        # inputs[0] = memory_in (dependency token)
        # inputs[1] = address node
        # inputs[2] = value node
        my @inputs = $self->inputs->@*;

        my $address = $values->{$inputs[1]};
        my $value = $values->{$inputs[2]};

        # Write to heap
        $heap->{$address} = $value;

        # Return memory state token
        return 1;
    }
}

1;
