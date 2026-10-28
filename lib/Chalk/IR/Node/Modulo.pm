# ABOUTME: Modulo operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the % operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::Modulo :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'Modulo' }

    # One that may die names the block eval whose body made it and its
    # statement's site (B::SoN), which perl's message names.
    field $eval_id :reader = undef;
    field $file    :reader = undef;
    field $line    :reader = undef;

    method set_die_site($e, $f, $l) {
        ($eval_id, $file, $line) = ($e, $f, $l);
        return;
    }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }
    method op_str()    { '%' }
}
