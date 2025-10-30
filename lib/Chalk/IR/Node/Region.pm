# ABOUTME: Region node in the IR graph
# ABOUTME: Represents control flow merge point where multiple paths converge
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Region :isa(Chalk::IR::Node::Base) {
    method op() { 'Region' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Region',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method execute($values) {
        # Region merges control from multiple paths
        # Returns the index of the active path (which Proj returned 1)
        my @inputs = $self->inputs->@*;

        for my $i (0..$#inputs) {
            my $input_id = $inputs[$i];
            my $proj_result = $values->{$input_id};
            if ($proj_result) {
                return $i;  # Return index of active path
            }
        }

        # No active path found - shouldn't happen in valid IR
        die "Region node has no active input path";
    }
}

1;
