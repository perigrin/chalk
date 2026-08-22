# ABOUTME: IR node representing a constant value in the Chalk Sea of Nodes graph.
# ABOUTME: Holds a typed literal (string, integer, etc.) with a stable content_hash.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::Constant :isa(Chalk::IR::Value) {
    field $value      :param :reader;
    field $const_type :param :reader = 'string';

    method operation() { 'Constant' }
    method staleness_kind() { 'opaque' }
    sub identity_kind { 'hash_consed' }

    method content_hash() {
        return join('|', 'Constant',
            "const_type=$const_type",
            "value=" . (defined $value ? $value : 'undef'));
    }
}
