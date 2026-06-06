# ABOUTME: Explicit coercion edge node in the Chalk IR typed-representation model.
# ABOUTME: Materialises a Perl implicit coercion as a visible graph node; from_repr/to_repr in content_hash.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Node;

class Chalk::IR::Node::Coerce :isa(Chalk::IR::Node) {

    # Source representation of the input value (e.g. 'Str', 'Int', 'Num', 'Scalar').
    # Part of content_hash: Coerce[Str->Num](x) and Coerce[Str->Int](x) are distinct
    # nodes. Two consumers needing the same coercion of the same value share one
    # hash-consed Coerce node (per typed-ir-representation.md §1a).
    field $from_repr :param :reader;

    # Target representation this node coerces the input to.
    # Part of content_hash for the same reason as from_repr.
    field $to_repr :param :reader;

    method operation() { 'Coerce' }

    method content_hash() {
        return join('|', 'Coerce',
            "from=$from_repr",
            "to=$to_repr",
            $self->_serialize_inputs());
    }
}
