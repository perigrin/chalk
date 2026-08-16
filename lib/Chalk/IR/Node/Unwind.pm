# ABOUTME: CFG exceptional-exit node for a Chalk computation graph.
# ABOUTME: inputs[0] is the exception-args arrayref; control flows via control_in.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Unwind :isa(Chalk::IR::Node) {
    method operation() { 'Unwind' }
    method staleness_kind() { 'opaque' }

    # FIXED: a die ABORTS. Absent from %STATEMENT_EFFECT_OPS, which is the gap this method exists to close -- a collapse pass consulting the registry would judge a die-only arm effect-free and fold it into a select
    method is_fixed() { return true }

    # The exception arguments (an arrayref). Control flows through the
    # control_in decoration (set via set_control_in), not through inputs.
    method value() { return $self->inputs->[0] }
}
