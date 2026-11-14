# ABOUTME: String concatenation operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the . operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::Concat :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'Concat' }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }
    method op_str()    { '.' }

    # const_choices -> each left choice joined to each right one.
    method const_choices() {
        my ( $l, $r ) = $self->inputs->@[ 0, 1 ];
        my @a = ( $l isa Chalk::IR::Node ? $l->const_choices : () ) or return ();
        my @z = ( $r isa Chalk::IR::Node ? $r->const_choices : () ) or return ();
        return map { my $x = $_; map { "$x$_" } @z } @a;
    }

    # const_pattern -> its parts' strings joined, where each part has one.
    method const_pattern() {
        my @p = map { $_->const_pattern } grep { blessed($_) } $self->inputs->@*;
        return undef if grep { !defined } @p;
        return join '', @p;
    }
}
