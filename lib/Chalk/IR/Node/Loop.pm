# ABOUTME: Loop node in the IR graph
# ABOUTME: Represents loop control flow structure with entry and backedge inputs
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Loop :isa(Chalk::IR::Node::Base) {
    method op() { 'Loop' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Loop',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($context) {
        # Loop merges control from entry and backedge paths
        # Works like Region: returns index of active path
        # inputs[0] = entry control
        # inputs[1] = backedge control (if present)
        my @inputs = $self->inputs->@*;

        for my $i (0..$#inputs) {
            my $input_id = $inputs[$i];
            my $ctrl_result = $context->("node:$input_id");
            if ($ctrl_result) {
                return $i;  # Return index of active path
            }
        }

        # No active path found - shouldn't happen in valid IR
        die "Loop node has no active input path";
    }
}

1;
