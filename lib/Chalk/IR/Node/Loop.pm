# ABOUTME: CFG loop header node for a Chalk computation graph.
# ABOUTME: Holds the entry control and a mutable backedge slot set after the loop body is built.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Loop :isa(Chalk::IR::Node) {
    # Post-construct merge point. The loop-statement actions
    # (WhileStatement / ForeachStatement / PostfixModifier loop form)
    # construct a Region from the exit Proj after the loop body is
    # done; storing the reference here lets Block's control-chain
    # fixup advance past the Loop without rediscovering it from
    # annotations.
    field $region :reader = undef;

    method operation() { 'Loop' }

    # CFG nodes carry their control input in inputs[0] (entry_ctrl
    # for Loop), not in the base $control_in field. Override the
    # reader so a walker that calls $node->control_in() gets a
    # consistent answer across node types. Without this override,
    # the base reader would return the unset $control_in field
    # (undef) even though the Loop's entry control is live at
    # inputs[0].
    method control_in() { return $self->inputs->[0] }

    method set_backedge_ctrl($ctrl) {
        my $old = $self->inputs()->[1];
        $old->remove_consumer($self) if defined $old;
        $self->inputs()->[1] = $ctrl;
        $ctrl->add_consumer($self) if defined $ctrl;
    }

    # Late-binding setter for the post-Loop merge Region.
    method set_region($r) {
        $region = $r;
        return;
    }

    # Late-binding setter for the entry control input (inputs[0]).
    # Mirrors If::set_control_in. Called by Block's control-chain
    # fixup pass to rewire the Loop's entry to the actual chain
    # predecessor at statement-list position.
    method set_control_in($ctrl) {
        my $old = $self->inputs()->[0];
        $old->remove_consumer($self) if defined $old;
        $self->inputs()->[0] = $ctrl;
        $ctrl->add_consumer($self) if defined $ctrl;
        return;
    }
}
