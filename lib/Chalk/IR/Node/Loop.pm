# ABOUTME: Loop node in the IR graph
# ABOUTME: Represents loop control flow structure with entry and backedge inputs
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Loop :isa(Chalk::IR::Node::Base) {
    use Chalk::IR::Graph;
    use Scalar::Util qw(refaddr);

    field $active_input_index :reader = 0;

    # CFG marker - Loop is a control flow node
    method isCFG() { return 1; }

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
        my @input_list = $self->inputs->@*;

        for my $i (0..$#input_list) {
            my $input_id = $input_list[$i];
            my $ctrl_result = $context->("node:$input_id");
            if ($ctrl_result) {
                $active_input_index = $i;  # Track which path is active
                return $i;  # Return index of active path
            }
        }

        # No active path found - shouldn't happen in valid IR
        die "Loop node has no active input path";
    }

    # Loop nodes override loopDepth to return entry->loopDepth() + 1
    # This marks nodes inside the loop as having increased depth
    field $_loopDepth = undef;

    method loopDepth() {
        return $_loopDepth if defined $_loopDepth;

        # Get entry control (inputs[0])
        my @input_list = $self->inputs->@*;
        return 1 unless @input_list;  # Default if no inputs

        my $entry_id = $input_list[0];
        my $graph = Chalk::IR::Graph->instance();
        my $entry = $graph->get_node($entry_id);

        if (defined $entry && $entry->can('loopDepth')) {
            $_loopDepth = $entry->loopDepth() + 1;
        } else {
            $_loopDepth = 1;  # Default: first loop level
        }

        return $_loopDepth;
    }

    # Dominator methods for Loop node
    # Loop's idom is its entry control (inputs[0])
    method idom() {
        my @input_list = $self->inputs->@*;
        return undef unless @input_list;

        my $entry_id = $input_list[0];
        my $graph = Chalk::IR::Graph->instance();
        return $graph->get_node($entry_id);
    }

    field $_idepth = undef;
    method idepth() {
        return $_idepth if defined $_idepth;

        my $idom = $self->idom();
        if (!defined $idom) {
            $_idepth = 0;
        } elsif ($idom->can('idepth')) {
            $_idepth = $idom->idepth() + 1;
        } else {
            $_idepth = 1;
        }

        return $_idepth;
    }

    # Force exit for infinite loops
    # Walk backedge idom chain looking for CProjNode (indicates natural exit)
    # If no exit found, create NeverNode and synthetic path to Stop
    method forceExit() {
        my @input_list = $self->inputs->@*;
        return unless @input_list >= 2;  # Need backedge

        # Get backedge (inputs[1])
        my $backedge_id = $input_list[1];
        my $graph = Chalk::IR::Graph->instance();
        my $backedge = $graph->get_node($backedge_id);

        # Walk up idom chain from backedge looking for Proj node
        # A Proj from an If indicates a natural loop exit
        my $current = $backedge;
        my $found_exit = 0;

        while (defined $current && $current->can('idom')) {
            # Check if this is a Proj node (control projection)
            if ($current->can('op') && $current->op eq 'Proj') {
                $found_exit = 1;
                last;
            }

            # Stop at loop header (don't go beyond the loop)
            last if refaddr($current) == refaddr($self);

            $current = $current->idom();
        }

        # If no natural exit found, create synthetic exit
        unless ($found_exit) {
            # Create Never node for synthetic exit condition
            # This represents a condition that's never true
            # Allows infinite loops to be reachable from Stop for scheduling
            use Chalk::IR::Node::Never;

            my $never = Chalk::IR::Node::Never->new(
                inputs => [refaddr($self)],  # Control input from loop
                condition_id => 0,           # Dummy condition
                control => $self,
            );

            # Note: In full implementation, this would wire the Never node
            # to create a path from loop to Stop, making code after the loop
            # unreachable but schedulable. For now, creating the Never node
            # is sufficient to demonstrate the infrastructure.
        }

        return;
    }
}

1;

