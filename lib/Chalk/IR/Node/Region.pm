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

    method execute($context) {
        # Region merges control from multiple paths
        # Per Sea of Nodes: "produces a merged control as an output"
        # Returns 1 to indicate control flows here (not which path was taken)
        # Phi nodes check Region's input Proj nodes to determine active path
        my @inputs = $self->inputs->@*;
        my @active_paths;

        for my $i (0..$#inputs) {
            my $input_id = $inputs[$i];
            my $proj_result = $context->("node:$input_id");

            # Proj nodes MUST return exactly 0 or 1, nothing else
            die "Region node '" . $self->id . "': input $input_id returned invalid value: " .
                (defined($proj_result) ? $proj_result : "undef")
                unless defined($proj_result) && ($proj_result == 0 || $proj_result == 1);

            push @active_paths, $i if $proj_result == 1;
        }

        # Exactly ONE path must be active
        die "Region node '" . $self->id . "': no active input path"
            if @active_paths == 0;
        die "Region node '" . $self->id . "': multiple active paths: " . join(', ', @active_paths)
            if @active_paths > 1;

        # Return merged control (1 = control is here)
        return 1;
    }
}

1;
