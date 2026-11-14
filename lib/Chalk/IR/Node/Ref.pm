# ABOUTME: Reference constructor operation node in the Chalk IR.
# ABOUTME: Unary data node wrapping the \ operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::UnaryOp;

class Chalk::IR::Node::Ref :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'Ref' }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }
    method op_str()    { '\\' }

    # `\(@a)`: a reference to each element of its operand. Identity-bearing:
    # `\@a` beside it must not hash-cons with it.
    field $each :param :reader = 0;
    # `\$x` of a `my` a loop renews each pass (B::SoN says so): each pass's
    # reference is to that pass's variable.
    field $fresh_each_pass :param :reader = 0;

    method content_hash() {
        return join('|', 'Ref', ($each ? 'each' : ()), ($fresh_each_pass ? 'fresh' : ()), $self->_serialize_inputs());
    }

    # is_alias_ref -> true when every use of it is a FOREACH ALIAS READ (it
    # escapes nowhere: the deref of it is the element, PostfixDeref's
    # alias_element), directly or through its guard's ?:.
    method is_alias_ref() {
        my @c = grep { blessed($_) } $self->consumers->@*;
        return 0 unless @c;
        for my $c (@c) {
            if ( $c->operation eq 'PostfixDeref' ) { return 0 unless $c->alias_element; next }
            if ( $c->operation eq 'TernaryExpr' && blessed( $c->inputs->[1] ) && refaddr( $c->inputs->[1] ) == refaddr($self) ) {
                my $t = $c;
                my @d = grep { my $u = $_; blessed($u) && grep { blessed($_) && refaddr($_) == refaddr($t) } $u->inputs->@* } $c->consumers->@*;   # (its values' users, not its control's)
                return 0 unless @d && !grep { !( $_->operation eq 'PostfixDeref' && $_->alias_element ) } @d;
                next;
            }
            return 0;
        }
        return 1;
    }
}
