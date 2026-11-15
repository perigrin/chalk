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
    # ${ \ $a[i] } -- or undef. Not one written through (a store into the
    # aliased variable). Two forms:
    #  - GUARDED, over an array (`@_`, `my @a`, `@$r`): c ? \$a[i] : undef,
    #    c the element's existence. The loop reads the array's count each
    #    pass, so the element is read by index into the live array, as perl's
    #    iterator does. Over @_, only where nothing reshapes @_ (a sub's
    #    arguments are not one array a shift and an index both see).
    #  - BARE, over a list of the foreach's own (an ArrayLiteral naming no
    #    variable: `for (1, 2)`, `for (sort ...)`), its index the loop's
    #    counter: no one else holds the list, and the counter stays in it. A
    #    bare \$a[i] of another array is a reference to an element of no known
    #    place (one before the array's start dies; past its end, made).
    method alias_element() {
        return undef unless ( $sigil // '' ) eq '$';
        return undef if grep { blessed($_) && $_->operation =~ /\A(?:Assign|Increment|Decrement)\z/ && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($self) }
            $self->consumers->@*;
        my $t = $self->inputs->[0];
        my $guarded = blessed($t) && $t->operation eq 'TernaryExpr' && blessed( $t->inputs->[2] )
            && $t->inputs->[2]->operation eq 'Constant' && ( $t->inputs->[2]->const_type // '' ) eq 'undef';
        my $r = $guarded ? $t->inputs->[1] : $t;
        return undef unless blessed($r) && $r->operation eq 'Ref' && !$r->each;
        my $s = $r->inputs->[0];
        return undef unless blessed($s) && $s->operation eq 'Subscript' && ( $s->can('kind') ? $s->kind // 'array' : 'array' ) eq 'array';
        my $arr = $s->inputs->[0];
        return undef unless blessed($arr);
        unless ($guarded) {
            my $i = $s->inputs->[1];
            return undef unless $arr->operation eq 'ArrayLiteral' && !defined $arr->symbol && !$arr->is_my_array
                && blessed($i) && $i->operation eq 'Phi';
            return $s;
        }
        # (the guard is the element's existence)
        my $c = $t->inputs->[0];
        return undef unless blessed($c) && $c->operation eq 'Exists' && refaddr( $c->inputs->[0] ) == refaddr($arr)
            && refaddr( $c->inputs->[1] ) == refaddr( $s->inputs->[1] );
        if ( $arr->operation eq 'ArgsSource' ) {
            return undef if grep { blessed($_) && $_->operation eq 'Call' && $_->mutates_array
                                   && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($arr) } $arr->consumers->@*;
            return $s;
        }
        return undef unless $arr->is_my_array || $arr->is_array_deref || $arr->is_argv
            || $arr->is_package_aggregate && ( $arr->sigil // '' ) eq '@'
            || $arr->operation eq 'ArrayLiteral' && ( $arr->stamp // '' ) eq 'Array';   # static type
        # ONLY WHERE NOTHING CAN RESHAPE THE ARRAY: perl's alias holds the
        # element itself, an index read into an array a shift has moved does
        # not (`for my $e (@a) { shift @a; print $e }`: "2" for perl's "1").
        return undef if _may_reshape($arr);
        return $s;
    }

    # _may_reshape($array) -> true when something in the program may move or
    # drop the array's elements (shift, pop, unshift, splice, `$#a =`, an
    # element deleted): one naming it, or -- where it is no `my` array, or
    # one a reference to escapes -- one of any array not a `my` array, or a
    # call T2 cannot see into (a method's, a code value's). A push only
    # appends: an element's index stands.
    sub _my_symbol($n) {
        return undef unless blessed($n);
        return $n->symbol if $n->operation eq 'PadAccess' && $n->is_my_array;
        return $n->symbol if $n->operation eq 'ArrayLiteral' && defined $n->symbol && ( $n->stamp // '' ) eq 'Array' && !$n->stored_whole_into;   # static type
        return undef;
    }
    sub _may_reshape($arr) {
        require Chalk::IR::Graph;
        my @all = Chalk::IR::Graph::program_nodes($arr);
        my $sym = _my_symbol($arr);
        my @hits = map { $_->inputs->[0] } grep {
            $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin'
                && ( ( $_->mutates_array && ( $_->name // '' ) ne 'push' ) || ( $_->name // '' ) eq 'set_arylen' )
            || $_->operation eq 'Delete' && ( $_->can('kind') ? $_->kind // '' : '' ) eq 'array'
        } @all;
        my $escapes = defined $sym && grep { $_->operation eq 'Ref' && grep { ( _my_symbol($_) // "\0" ) eq $sym } $_->inputs->@* } @all;
        if ( defined $sym && !$escapes ) {
            return scalar grep { ( _my_symbol($_) // "\0" ) eq $sym } @hits;
        }
        return 1 if grep { !defined _my_symbol($_) || defined $sym && _my_symbol($_) eq $sym } @hits;
        return scalar grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) =~ /\A(?:method|indirect)\z/ } @all;
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
