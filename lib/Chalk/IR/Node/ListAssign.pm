# ABOUTME: List-context multi-assignment IR node for my ($a, $b) = (1, 2) form.
# ABOUTME: Carries an arrayref of name Constants and a single init node (ExpressionList or similar).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::ListAssign :isa(Chalk::IR::Node) {
    field $scope :param :reader = 'my';

    method operation() { 'ListAssign' }

    # ListAssign has per-position (counter) identity, like VarDecl:
    # two textually-identical list declarations in different control
    # positions are distinct nodes (each carries its own control_in).
    method content_hash() {
        return $self->id();
    }

    # Convenience accessors for the standard input slots.
    # inputs->[0] = arrayref of name Constant nodes (the LHS variables)
    # inputs->[1] = init node (the RHS expression; typically an ExpressionList)
    # Control flows through control_in (set via set_control_in), not an input slot.
    method control() { return $self->control_in }
    method names()   { return $self->inputs->[0] }
    method init()    { return $self->inputs->[1] }
}
