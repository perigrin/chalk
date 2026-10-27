# ABOUTME: Regex match binding operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the =~ operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::Match :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'Match' }
    method staleness_kind() { 'opaque' }

    # FIXED: sets the capture state a later $N read depends on
    method is_fixed() { return true }
    method op_str()    { '=~' }

    # The match's flags (B::SoN), for a pattern made at run time -- a string
    # whose flags no qr// carries. undef: not sent. In the hash: /b/ and /b/i
    # are different matches.
    field $flags :param :reader = undef;
    method content_hash() {
        return join('|', 'Match', "flags=" . ( $flags // '-' ), $self->_serialize_inputs());
    }
}
