# ABOUTME: IR node for accessing a lexical pad slot by target index and variable name.
# ABOUTME: Used to represent $x, @arr, %hash style variable reads in the Sea of Nodes graph.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::PadAccess :isa(Chalk::IR::Node::Access) {
    field $targ    :param :reader;
    field $varname :param :reader;

    method operation() { 'PadAccess' }

    method content_hash() {
        # Identity is the variable name plus inputs. `targ` (the pad-slot index)
        # is CV-local and unstable across compilation units, so it is NOT
        # identity-bearing: two semantically identical reads at different pad
        # indices must hash-cons together. `targ` is retained as a field for
        # diagnostics / round-trip only (no consumer reads it behaviorally;
        # PadAccess resolves to its VarDecl via inputs[0]).
        return join('|', 'PadAccess', "varname=$varname", $self->_serialize_inputs());
    }
}
