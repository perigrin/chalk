# ABOUTME: Base class for control flow graph nodes in the IR
# ABOUTME: Provides isCFG marker and dominator tree navigation methods
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::CFGNode {
    use Chalk::IR::Graph;

    # CFG marker method - returns true for all CFG nodes
    method isCFG() { return 1; }

    # Auto-register CFG nodes with the singleton graph
    ADJUST {
        my $graph = Chalk::IR::Graph->instance();
        $graph->add_node($self);
    }

    # Dominator tree methods (to be overridden by subclasses)
    # idom() returns the immediate dominator node
    # idepth() returns the dominator tree depth
    # dominates($other) checks if this node dominates another

    # Loop depth tracking: cached field defaults to undef
    field $_loopDepth = undef;

    # Compute loop depth by looking at control input (cfg(0))
    # Most CFG nodes get their loop depth from their immediate dominator
    # Loop nodes override this to return entry->loopDepth() + 1
    method loopDepth() {
        return $_loopDepth if defined $_loopDepth;

        # Get first control input (cfg(0))
        # This is typically the idom for most CFG nodes
        my $cfg0 = $self->can('idom') ? $self->idom() : undef;

        if (defined $cfg0 && $cfg0->can('loopDepth')) {
            $_loopDepth = $cfg0->loopDepth();
        } else {
            $_loopDepth = 0;  # Default: not in any loop
        }

        return $_loopDepth;
    }
}

1;
