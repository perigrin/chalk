# ABOUTME: Stop node representing program termination point in the IR graph
# ABOUTME: Collects all Return nodes to mark where the function exits
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Stop :isa(Chalk::IR::Node::Base) {
    method op() { 'Stop' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Stop',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($context) {
        # Stop node collects all returns and executes the one from the active path
        # Returns are connected as inputs to Stop
        my @inputs = $self->inputs->@*;

        # Execute each Return input - the active one will return a value
        for my $input_id (@inputs) {
            my $return_result = $context->("node:$input_id");
            # If this Return executed (not undef), return its value
            return $return_result if defined($return_result);
        }

        # No active return found
        return undef;
    }
}

1;
