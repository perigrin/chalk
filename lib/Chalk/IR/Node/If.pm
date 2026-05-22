# ABOUTME: CFG conditional branch node for a Chalk computation graph.
# ABOUTME: Takes control and condition inputs; produces two Proj outputs (true/false).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::If :isa(Chalk::IR::Node) {
    # Post-construct merge point. The IfStatement action constructs a
    # Region that joins this If's two Proj outputs; storing a reference
    # here lets Block's control-chain fixup advance past the If without
    # rediscovering the structure from annotations.
    field $region :reader = undef;

    method operation() { 'If' }

    # Late-binding setter for the post-construct Region. Called by
    # the IfStatement / ElsifChain action right after the Region is
    # built.
    method set_region($r) {
        $region = $r;
        return;
    }

    # Late-binding setter for the forward control input. Mutates
    # inputs[0] (the convention for CFG nodes) while maintaining the
    # bidirectional use-def edge. Called by Block's control-chain
    # fixup pass when the parsing-time control assigned at If
    # construction needs to be replaced with the actual chain
    # predecessor at statement-list position.
    method set_control_in($ctrl) {
        my $old = $self->inputs->[0];
        $old->remove_consumer($self) if defined $old;
        $self->inputs->[0] = $ctrl;
        $ctrl->add_consumer($self) if defined $ctrl;
        return;
    }
}
