# ABOUTME: Postfix dereference node in the Chalk IR.
# ABOUTME: Carries the sigil (@, %, $) indicating the dereference type.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::PostfixDeref :isa(Chalk::IR::Value) {
    field $sigil :param :reader;
    # A COPY, not an alias: `my %p = %$h` is a new hash with %$h's entries,
    # which a later store through $h does not reach (B::SoN `copy`).
    field $copy  :param :reader = 0;
    # A SCALAR DEREF'S SITE (B::SoN's): perl's die names it; under `strict
    # refs` a string there dies, without it it is a name.
    field $eval_id :param :reader = undef;
    field $file    :param :reader = undef;
    field $line    :param :reader = undef;
    field $strict  :param :reader = 0;
    field $package :param :reader = undef;   # (without strict refs a string names its variable)

    method operation() { 'PostfixDeref' }

    # is_array_deref -> true for `@$r`, `@{...}`, `$r->@*`: an array deref (a
    # `${...}` is a scalar's: not this).
    method is_array_deref() { return ( $sigil // '@' ) eq '@' }

    # alias_element -> the element a FOREACH ALIAS READ reads -- B::SoN's
    # ${ \ $_[i] } (inside a guard of $_[i]'s existence, its other way undef)
    # -- or undef. Not one written through (a store into the caller's
    # variable).
    method alias_element() {
        return undef unless ( $sigil // '' ) eq '$';
        return undef if grep { blessed($_) && $_->operation =~ /\A(?:Assign|Increment|Decrement)\z/ && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($self) }
            $self->consumers->@*;
        # ONLY THE GUARDED FORM (a bare \$a[i] deref is a reference to an element
        # of no known place: one before the array's start dies), ONLY OVER @_,
        # ONLY WHERE NOTHING RESHAPES @_ -- a foreach over an array its body
        # shifts reads by index into the changing array, which this is not.
        my $t = $self->inputs->[0];
        return undef unless blessed($t) && $t->operation eq 'TernaryExpr' && blessed( $t->inputs->[2] )
            && $t->inputs->[2]->operation eq 'Constant' && ( $t->inputs->[2]->const_type // '' ) eq 'undef';
        my $r = $t->inputs->[1];
        return undef unless blessed($r) && $r->operation eq 'Ref';
        my $s = $r->inputs->[0];
        return undef unless blessed($s) && $s->operation eq 'Subscript' && ( $s->can('kind') ? $s->kind // 'array' : 'array' ) eq 'array';
        my $args = $s->inputs->[0];
        return undef unless blessed($args) && $args->operation eq 'ArgsSource';
        return undef if grep { blessed($_) && $_->operation eq 'Call' && $_->mutates_array
                               && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($args) } $args->consumers->@*;
        return $s;
    }

    # memory_operand -> it reads at its second input (the first is what it reads).
    method memory_operand() { return $self->inputs->[1] }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }

    method content_hash() {
        return join('|', 'PostfixDeref', "sigil=$sigil", ($copy ? 'copy' : ()),
            ( defined $line ? ( 'site', $eval_id // '', $file, $line, $strict ? 'strict' : '' ) : () ),
            $self->_serialize_inputs());
    }
}
