# ABOUTME: CFG merge node for a Chalk computation graph.
# ABOUTME: Joins multiple control-flow paths into one; inputs are Proj or other control nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Region :isa(Chalk::IR::Node) {
    # Back-pointer to the CFG node whose control flow this Region
    # merges (an If for if/else joins, a Loop for loop-exit joins).
    # Set by that node's set_region() side-effect. The scheduler
    # uses this to traverse past a Region in the effect chain:
    # `Return.inputs[0] = Region`, but Region has no single chain
    # predecessor (its inputs are Projs from divergent branches), so
    # the scheduler reads $region->head() and continues from
    # $head->control_in().
    field $head :reader = undef;

    method operation() { 'Region' }

    method set_head($node) {
        $head = $node;
        return;
    }
}
