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

    # Peephole optimization for Region nodes
    # If only one input is live (not ~Ctrl), collapse to that input
    method peephole($graph = undef) {
        return $self unless $graph;

        my @inputs = $self->inputs->@*;
        return $self unless @inputs;

        # Check each input - count live inputs and track the live one
        my @live_inputs;
        my @live_indices;

        for my $i (0..$#inputs) {
            my $input_id = $inputs[$i];
            next unless defined $input_id;

            my $input_node = $graph->get_node($input_id);
            next unless $input_node;

            # Check if this input is dead control (~Ctrl constant)
            my $is_dead = 0;
            if ($input_node->op eq 'Constant') {
                my $value = $input_node->attributes->{value} // $input_node->value;
                my $type = $input_node->attributes->{type} // $input_node->type;
                if ($type eq 'Control' && $value eq '~Ctrl') {
                    $is_dead = 1;
                }
            }

            unless ($is_dead) {
                push @live_inputs, $input_node;
                push @live_indices, $i;
            }
        }

        # If only one live input, collapse Region to that input
        if (@live_inputs == 1) {
            return $live_inputs[0];
        }

        return $self;
    }

    # Get the index of live inputs (for Phi node to use)
    method get_live_input_indices($graph) {
        return () unless $graph;

        my @inputs = $self->inputs->@*;
        return () unless @inputs;

        my @live_indices;
        for my $i (0..$#inputs) {
            my $input_id = $inputs[$i];
            next unless defined $input_id;

            my $input_node = $graph->get_node($input_id);
            next unless $input_node;

            # Check if dead control
            my $is_dead = 0;
            if ($input_node->op eq 'Constant') {
                my $value = $input_node->attributes->{value} // $input_node->value;
                my $type = $input_node->attributes->{type} // $input_node->type;
                if ($type eq 'Control' && $value eq '~Ctrl') {
                    $is_dead = 1;
                }
            }

            push @live_indices, $i unless $is_dead;
        }

        return @live_indices;
    }
}

1;
