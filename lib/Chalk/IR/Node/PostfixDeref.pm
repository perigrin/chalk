# ABOUTME: Postfix dereference node in the Chalk IR.
# ABOUTME: Carries the sigil (@, %, $) indicating the dereference type.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::PostfixDeref :isa(Chalk::IR::Value) {
    field $sigil :param :reader;

    method operation() { 'PostfixDeref' }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }

    method content_hash() {
        return join('|', 'PostfixDeref', "sigil=$sigil", $self->_serialize_inputs());
    }
}
