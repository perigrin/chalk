# ABOUTME: Base class for IR nodes that DEFINE a value, carrying that value's Chalk type.
# ABOUTME: Control nodes stay on Chalk::IR::Node and have no type field at all.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

# A node either defines a value or it does not, and that is a STRUCTURAL fact
# about the node kind, not a property to be filled in.
#
# The field lived on Chalk::IR::Node, so every node could carry a type and
# control nodes simply left it undef. That made `undef` mean three unrelated
# things with no way to tell them apart:
#
#   1. this node produces no value at all   (correct, permanent)
#   2. inference has not run yet            (temporary)
#   3. inference ran and could not decide   (a bug)
#
# Splitting the hierarchy removes meaning (1) from the field entirely, so an
# undef `type` can only ever be an inference question. That is the same
# absence-vs-value distinction `Unknown` exists to make, applied to the other
# axis -- see docs/plans/2026-08-21-type-vs-representation-seams.md.
#
# THE PREDICATE IS `$node isa Chalk::IR::Value`, never `->can('type')`. `can`
# is duck-typing over a NAME and answers true for any class that happens to
# define a `type` method for unrelated reasons; `isa` asks the actual question.
# It is also CLOSED -- there is no opt-in-by-defining-a-method escape hatch --
# so a value node nobody reparents fails by not being recognised as a value,
# which is loud, rather than by silently carrying an untyped field.
#
# This is Graal's ValueNode shape. LLVM (`void` as a real type) and C2
# (Type::CONTROL in the lattice) both leave a control node ASKABLE for its type;
# making the question unaskable is the property worth having.
#
# ORTHOGONAL TO EFFECTS. Value-ness and fixedness are independent axes:
# Assign and CompoundAssign are `is_fixed` (they write) AND value-producing
# (an assignment's result is the stored value, so `$x = $y = 5` works). Being a
# statement does not stop a node being a value. Perl core lacking Roles is why
# these cannot both be expressed as inheritance; the effect axis stays a method
# (`is_fixed`) and the value axis takes the hierarchy slot.
class Chalk::IR::Value :isa(Chalk::IR::Node) {
}

1;
