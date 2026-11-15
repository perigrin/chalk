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

    # memory_operand -> the memory version a reference to an element reads the
    # array at (B::SoN: the element at its index THERE -- which scalar sits at
    # which index is the array's layout, which a shift or push changes); undef
    # for one that reads none.
    method memory_operand() { return $self->inputs->@* > 1 ? $self->inputs->[1] : undef }
    # taken_where_it_stands -> B::SoN takes it where its statement runs: it
    # reads memory, on the control chain, the memory version after it (taking
    # it may make the element).
    method taken_where_it_stands() { return $self->is_pinned && defined $self->memory_operand ? 1 : 0 }
    method is_memory_version() { return $self->taken_where_it_stands }

    method content_hash() {
        return join('|', 'Ref', ($each ? 'each' : ()), ($fresh_each_pass ? 'fresh' : ()), $self->_serialize_inputs());
    }

    # element_subscript -> the array element this is a reference to (`\$a[i]`):
    # its Subscript; undef for any other (a hash's element, `\(@a)`, `\$x`).
    method element_subscript() {
        return undef if $each;
        my $s = $self->inputs->[0];
        return undef unless blessed($s) && $s->operation eq 'Subscript' && ( $s->can('kind') ? $s->kind // 'array' : 'array' ) eq 'array';
        return $s;
    }

    # is_element_ref -> a reference to an array's element, or to each one (`\(@a)`).
    method is_element_ref() {
        return 1 if $self->element_subscript;
        return 0 unless $each;
        my $a = $self->inputs->[0];
        return blessed($a) && ( $a->is_my_array || $a->is_array_deref || $a->operation eq 'ArgsSource'
            || $a->operation eq 'ArrayLiteral' && defined $a->symbol ) ? 1 : 0;
    }

    # element_ref_unsound -> why a reference to an element (or to each one)
    # may not be the element perl's is, or undef. Perl's is taken where its
    # statement runs; B::SoN gives one NO PLACE among the statements -- `my $r
    # = \$a[0]; shift @a` and `shift @a; my $r = \$a[0]` are one graph -- so
    # it is sound only where the element is one wherever it is made:
    #  - UNDER A FOREACH ALIAS'S GUARD (c ? \$a[i] : undef, the guard on the
    #    control chain): made where the guard stands; its existence test keeps
    #    the index in the array;
    #  - TAKEN WHERE IT STANDS (taken_where_it_stands: B::SoN orders it on
    #    the array's memory) -- made there, in order, it is the element at its
    #    index then, whatever reshapes the array before or after; its index a
    #    constant not before the start (perl's die there names a site B::SoN
    #    does not give the reference);
    #  - else its index a constant not before the start (perl's die before it
    #    would have no place either), its array one nothing reshapes: no shift,
    #    pop, unshift, splice, `$#a =`, delete, store of the whole array, nor a
    #    push unless the element is there from the array's making.
    method element_ref_unsound() {
        return 'a reference to what is no array element' unless $self->is_element_ref;
        if ( my $why = $self->element_ref_unseen ) { return $why }
        my @c = grep { my $u = $_; blessed($u) && grep { blessed($_) && refaddr($_) == refaddr($self) } $u->inputs->@* } $self->consumers->@*;
        my $s = $self->element_subscript;
        my $arr = $s ? $s->inputs->[0] : $self->inputs->[0];
        my $ix  = $s ? $s->inputs->[1] : undef;
        if ( $s && @c && !grep { !_guards($_, $self) } @c ) { return undef }
        if ($s) {
            return 'a reference to an element at an index not a constant (perl dies before the start, naming a site B::SoN does not give it)'
                if $self->taken_where_it_stands && !_nonnegative_constant($ix);
            return 'a reference to an element at an index not a constant (perl takes it where its statement runs; B::SoN gives it no place)'
                unless _nonnegative_constant($ix);
        }
        return undef if $self->taken_where_it_stands;
        return 'a reference to an element of an array that may be reshaped (perl takes it where its statement runs; B::SoN gives it no place)'
            if _reshaped( $arr, $s ? $ix->value : undef );
        return undef;
    }

    sub _nonnegative_constant($ix) {
        return blessed($ix) && $ix->operation eq 'Constant' && ( $ix->const_type // '' ) eq 'integer' && ( $ix->value // -1 ) =~ /\A\+?\d+\z/ ? 1 : 0;
    }

    # element_ref_unseen -> why a store through this reference to an element
    # may go unseen, or undef: B::SoN takes a `my` array nothing else writes
    # for never written -- every read of it folded to what it was made with,
    # read at no memory version -- so a store through the reference is not
    # what a later read of the array sees (`my $r = \$a[0]; $$r = 5; print
    # "@a"` prints what @a was made with). Where the program may store
    # through any scalar reference (or into @_, or in a call T2 cannot see
    # into), refused.
    method element_ref_unseen() {
        my $s = $self->element_subscript;
        my $arr = $s ? $s->inputs->[0] : $self->inputs->[0];
        return undef unless blessed($arr) && $arr->operation eq 'ArrayLiteral' && defined $arr->symbol;
        return undef if grep { my $u = $_; blessed($u) && grep { blessed($_) && $_->is_memory_version } $u->inputs->@* } ( $arr->consumers // [] )->@*;
        # (one a reference to the whole array, or to each element, escapes:
        # B::SoN reads it at its memory versions, through either name)
        return undef if grep { blessed($_) && $_->operation eq 'Ref' && !$_->element_subscript } ( $arr->consumers // [] )->@*;
        require Chalk::IR::Graph;
        my $stores = stores_through( Chalk::IR::Graph::program_nodes($arr) );
        return $stores ? 'a reference to an element of an array B::SoN reads as never written, where a store may go through it' : undef;
    }

    # stores_through(@nodes) -> some node may store through a scalar
    # reference, or into @_ (`$$r = ...`, `$_[0] .= ...`, a chomp of one), or is
    # a call T2 cannot see into (a method's, a code value's).
    sub stores_through(@nodes) {
        my $deref = sub ($x) {
            $x = $x->inputs->[0] while blessed($x) && $x->operation eq 'Coerce';
            return blessed($x) && ( $x->operation eq 'PostfixDeref' && ( $x->sigil // '' ) eq '$'
                || $x->operation eq 'Subscript' && blessed( $x->inputs->[0] ) && $x->inputs->[0]->operation eq 'ArgsSource' );
        };
        return scalar grep {
            my $n = $_;
            $n->operation =~ /\A(?:Assign|Increment|Decrement|RegexSubst|Transliterate|Chomp|Chop)\z/ && $deref->( $n->inputs->[0] )
                || $n->operation eq 'Call' && $n->writes_first_argument && $deref->( $n->inputs->[0] )
                || $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) =~ /\A(?:method|indirect|dynamic_method)\z/
        } @nodes;
    }

    # _guards($t, $ref): $t is a foreach alias's guard of $ref, on the
    # control chain -- `exists $a[i] ? \$a[i] : undef`.
    sub _guards($t, $r) {
        return 0 unless $t->operation eq q{TernaryExpr} && $t->is_pinned;
        my ( $c, $then, $else ) = $t->inputs->@*;
        my $s = $r->element_subscript;
        return blessed($then) && refaddr($then) == refaddr($r)
            && blessed($else) && $else->operation eq 'Constant' && ( $else->const_type // '' ) eq 'undef'
            && blessed($c) && $c->operation eq 'Exists' && blessed( $c->inputs->[0] ) && blessed( $c->inputs->[1] )
            && refaddr( $c->inputs->[0] ) == refaddr( $s->inputs->[0] ) && refaddr( $c->inputs->[1] ) == refaddr( $s->inputs->[1] ) ? 1 : 0;
    }

    # _reshaped($array, $index) -> something may change which element is at
    # $index of $array (undef: at any index, `\(@a)`). @_: a change of it in
    # its sub, or its sub handing it on (`&g`). A `my` array: as a foreach
    # alias's (PostfixDeref's _may_reshape), or a store of it whole, or a push
    # where the element is not one the array is made with. Any other: any
    # change of any array T2 cannot tell from it, a push too.
    sub _reshaped($arr, $index) {
        require Chalk::IR::Graph;
        require Chalk::IR::Node::PostfixDeref;
        return 1 unless blessed($arr);
        my @all = Chalk::IR::Graph::program_nodes($arr);
        if ( $arr->operation eq 'ArgsSource' ) {
            return scalar grep {
                my $u = $_;
                $u->operation eq 'Call' && ( $u->mutates_array || ( $u->name // '' ) eq 'set_arylen' ) && blessed( $u->inputs->[0] ) && refaddr( $u->inputs->[0] ) == refaddr($arr)
                    || $u->operation eq 'Call' && $u->can('shares_args') && $u->shares_args
                    || $u->operation =~ /\A(?:Assign|Delete)\z/ && blessed( $u->inputs->[0] ) && refaddr( $u->inputs->[0] ) == refaddr($arr)
            } @all;
        }
        return 1 if Chalk::IR::Node::PostfixDeref::_may_reshape($arr);
        my $sym = Chalk::IR::Node::PostfixDeref::_my_symbol($arr);
        my $pushes = sub ($pred) { scalar grep { $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin' && ( $_->name // '' ) eq 'push' && $pred->( $_->inputs->[0] ) } @all };
        unless ( defined $sym ) {
            # (through a reference: a whole store of any array, any push, a
            # call T2 cannot see into)
            return 1 if grep { $_->operation =~ /\A(?:Assign|EntryWrite)\z/ && blessed( $_->inputs->[0] ) && ( $_->inputs->[0]->is_array_deref || $_->inputs->[0]->is_my_array ) } @all;
            return $pushes->( sub ($x) { 1 } ) ? 1 : 0;
        }
        # (a `my` array stored whole is a new version of it: B::SoN makes another node of its name)
        my %seen;
        my @versions = grep { !$seen{ refaddr($_) }++ } grep { $_->operation eq 'ArrayLiteral' && ( $_->symbol // "\0" ) eq $sym } @all;
        return 1 if @versions > 1;
        return 1 if grep { $_->operation =~ /\A(?:Assign|EntryWrite)\z/ && ( Chalk::IR::Node::PostfixDeref::_my_symbol( $_->inputs->[0] ) // "\0" ) eq $sym } @all;
        my $made = ( $arr->operation eq 'ArrayLiteral' && !grep { !( blessed($_) && $_->operation eq 'Constant' ) } $arr->inputs->@* )
            ? scalar $arr->inputs->@* : 0;
        return 0 if defined $index && $index < $made;
        return $pushes->( sub ($x) { ( Chalk::IR::Node::PostfixDeref::_my_symbol($x) // "\0" ) eq $sym } ) ? 1 : 0;
    }

    # is_alias_ref -> true when every use of it is a FOREACH ALIAS READ (it
    # escapes nowhere: the deref of it is the element, PostfixDeref's
    # alias_element), directly or through its guard's ?:.
    method is_alias_ref() {
        # (its values' users: one pinned on the chain is the next statement's control)
        my @c = grep { my $u = $_; blessed($u) && grep { blessed($_) && refaddr($_) == refaddr($self) } $u->inputs->@* } $self->consumers->@*;
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
