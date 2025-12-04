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
}

1;
