# ABOUTME: Base class for all access IR nodes in the Chalk Sea of Nodes graph.
# ABOUTME: Groups PadAccess, FieldAccess, EntryDef, and Subscript under a common type.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::Access :isa(Chalk::IR::Value) {
    # A constant-key read of %main:: (Exists, Subscript): whether its key was
    # there when the program compiled -- B::SoN's stash_has, 1 or 0.
    field $stash_has :reader = undef;
    method set_stash_has($v) { $stash_has = $v; return }
    # A PLACE (wire `fields.place`): the storage itself, which an alias is
    # bound to -- lowered to a pointer to it, never read as a value. `vivify`:
    # the binder makes the element exist (perl's foreach, map or grep item).
    field $place  :param :reader = false;
    field $vivify :param :reader = false;
}
