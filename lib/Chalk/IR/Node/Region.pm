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
    # A BLOCK EVAL'S JOIN: the control node its protected body follows. A
    # die between it and this Region is caught here (B::SoN's eval_entry).
    field $eval_entry :reader = undef;
    # 'list' or 'runtime' (the caller's) when the eval is not in scalar or
    # void context: there a die yields the empty list, not undef.
    field $eval_want :reader = undef;
    # The eval's body makes a value that may die (B::SoN's eval_may_die):
    # perl dies there even if it is unused, and an unused one is not in
    # the graph.
    field $eval_may_die :reader = 0;
    # The eval's id in its graph; each die it catches carries the same.
    field $eval_id :reader = undef;

    method set_eval_id($v) {
        $eval_id = $v;
        return;
    }

    method operation() { 'Region' }
    method staleness_kind() { 'opaque' }

    method set_eval_entry($node) {
        $eval_entry = $node;
        return;
    }

    method set_eval_may_die($v) {
        $eval_may_die = $v;
        return;
    }

    method set_eval_want($w) {
        $eval_want = $w;
        return;
    }

    method set_head($node) {
        $head = $node;
        return;
    }

    # goes_on -> true when control goes on from this merge: a statement after
    # it, or a Region it is a way into that goes on (a loop's latch has
    # neither: one that feeds only the latch does not).
    method goes_on() {
        return $self->successors || grep { blessed($_) && $_->operation eq 'Region' && ( grep { blessed($_) && refaddr($_) == refaddr($self) } $_->inputs->@* ) && $_->goes_on } $self->consumers->@*;
    }

    # out_regions -> the Regions this one is a way into, each once.
    method out_regions() {
        my %seen;
        return grep { blessed($_) && $_->operation eq 'Region' && !$seen{ refaddr($_) }++ && grep { blessed($_) && refaddr($_) == refaddr($self) } $_->inputs->@* } $self->consumers->@*;
    }

    # reached_by($ctl) -> true when control $ctl reaches this merge by the
    # control it goes on to: through the Regions it feeds, and what they head.
    method reached_by($ctl) {
        my (%seen, @q);
        @q = ($ctl);
        while (defined(my $n = shift @q)) {
            next if $seen{ refaddr($n) }++;
            return 1 if refaddr($n) == refaddr($self);
            push @q, grep { blessed($_) && ( $_->operation eq 'Region'
                            || ( $_->can('control_in') && blessed($_->control_in) && refaddr($_->control_in) == refaddr($n) ) ) }
                ( $n->consumers // [] )->@*;
        }
        return 0;
    }
}
