# ABOUTME: Loop node in the IR graph
# ABOUTME: Represents loop control flow structure with entry and backedge inputs
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Loop :isa(Chalk::IR::Node::CFGNode) {
    use Chalk::IR::Node::CFGNode;
    use Chalk::IR::Graph;

    field $active_input_index :reader = 0;
    field $inputs :param :reader = [];

    method id() { refaddr($self) }

    method op() { 'Loop' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Loop',
            inputs => $inputs,
            attributes => {},
        };
    }

    method execute($context) {
        # Loop merges control from entry and backedge paths
        # Works like Region: returns index of active path
        # inputs[0] = entry control
        # inputs[1] = backedge control (if present)
        my @input_list = $inputs->@*;

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
        my @input_list = $inputs->@*;
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
        my @input_list = $inputs->@*;
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
}

1;
