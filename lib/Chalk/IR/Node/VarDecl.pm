# ABOUTME: Variable declaration node in the Chalk IR.
# ABOUTME: Side-effect-shaped: inputs[0]=name Constant, inputs[1]=init (or undef); control flows via control_in.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::VarDecl :isa(Chalk::IR::Node) {
    field $scope :param :reader = 'my';

    method operation() { 'VarDecl' }

    # VarDecl has per-position (counter) identity, not content-hash
    # identity: two textually-identical declarations in different control
    # positions are distinct nodes (each carries its own control_in
    # decoration). The content_hash is therefore the node's unique id so
    # nothing — factory cache or graph merge/unmerge — ever deduplicates
    # two declarations by their textual content.
    method content_hash() {
        return $self->id();
    }

    # Convenience accessors for the standard input slots. Control flows
    # through the control_in decoration (set via set_control_in), not an
    # inputs slot.
    method control() { return $self->control_in }
    method name()    { return $self->inputs->[0] }
    method init()    { return $self->inputs->[1] }
}
