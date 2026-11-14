# ABOUTME: Defined-or short-circuit operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the // operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::DefinedOr :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'DefinedOr' }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }
    method op_str()    { '//' }

    # makes_a_string -> a default of strings is a string.
    method makes_a_string() {
        my ( $l, $r ) = $self->inputs->@[ 0, 1 ];
        return ( $l isa Chalk::IR::Node ? $l->makes_a_string : 0 ) && ( $r isa Chalk::IR::Node ? $r->makes_a_string : 0 );
    }
}
