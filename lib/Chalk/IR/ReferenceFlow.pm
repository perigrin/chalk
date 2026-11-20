# ABOUTME: Where a reference's value may flow in a program: through assignments, phis, calls' arguments
# ABOUTME: and returns, element and field stores -- a T1 question (may this Ref reach that `$` deref?).
use 5.42.0;
use utf8;
use experimental 'class';

# WHY A FLOW AND NOT A COEXISTENCE. T2 makes some references and not others
# (a glob's, a field's); a scalar deref of one it does not make must be
# refused, never read wrong at run time. Asked as "is there such a Ref and a
# `$` deref anywhere in the program?" it refused every program that loads a
# module with one -- Symbol::gensym's `\*{...}` behind File::Temp, whether or
# not gensym is ever called. Asked as "may that Ref's VALUE reach the
# reference operand of that deref?" it refuses only where it may.
#
# THE ANSWER IS CONSERVATIVE. A value is followed forward from the Ref to
# every node that may hold it -- or hold something holding it (a list, an
# array, a reference to it): one taint for both, so a deref of a container of
# it counts as a deref of it. Where the walk cannot say where the value goes
# next (a store through a reference, a closure cell, a call through a code
# value, a die, a builtin that may keep it), it ESCAPES, and the answer is
# "may reach" -- a refusal by name, never a silent wrong answer.
#
# WHAT IS FOLLOWED:
#   - every value use (inputs, not the memory operand): a node whose value may
#     be its operand's (a Phi, a choice, a coercion to Scalar, an element read
#     of a container holding it, a list or reference built of it);
#   - a store: an Assign's targets, an EntryWrite's global, push's array --
#     by LOCATION (the variable, the global, the field), so every read of it
#     anywhere in the program holds what the store put there;
#   - a call: the callee's parameters and @_ (every one: positions are not
#     tracked); a callee's return, every call of that callee;
#   - a builtin: stops where its value is a plain scalar (a string, a number,
#     a truth) and it keeps nothing; a bless is its operand; else ESCAPES.
# A node whose value is a plain scalar (Int, Num, Str, Boolean, Undef) and
# that stores nothing ends the walk: what it holds is no reference.
class Chalk::IR::ReferenceFlow {
    field $nodes :param;           # every node of the program (subs, blocks)
    field $mop   :param = undef;   # the MOP: callees by name

    field %uses;        # refaddr(node) -> [ [consumer, position], ... ]
    field %at;          # location key -> [ nodes reading or naming it ]
    field %sub_of_ret;  # refaddr(Return) -> the sub it returns from
    field %callers;     # refaddr(sub) -> [ Calls of it ]
    field %by_short;    # short name -> [ MOP subs ]
    field %live;        # refaddr(node) -> 1: in code the program may run
    field %code_taken;  # refaddr(sub) -> 1: its code value may be called
    field %code_call;   # refaddr(node) -> 1: a call through a code value or a name made at run time
    field @code_calls;
    field @subs;        # the MOP's subs with graphs
    field $any_code = 0;   # a call may run any sub (a name made at run time, a code value of unknown origin)
    field $ties     = 0;   # a tie anywhere: FETCH's value goes where the variable's does

    ADJUST {
        my ( %seen, %in_sub );
        for my $sub ( $mop ? map { $_->subs } $mop->classes : () ) {
            next unless $sub->can('graph') && blessed( $sub->graph ) && !$seen{ refaddr($sub) }++;
            push @subs, $sub;
            push $by_short{ ( $sub->name // '' ) =~ s/\A.*:://r }->@*, $sub;
            $in_sub{ refaddr($_) } //= $sub for $sub->graph->component;
        }
        # MAY A CALL RUN ANY SUB? One of a method named at run time may; so
        # may one through a code value where a call to no sub the program
        # defines (UNIVERSAL::can, an XS sub) may have handed it back.
        # shortcut: any such call anywhere, not one whose value may reach the
        # code call -- T2 compiles every sub where can() is called anyway.
        $any_code = 1 if grep { $_->operation eq 'Call' && !$_->is_builtin && !$_->is_sub_call } $nodes->@*;
        $any_code = 1 if ( grep { $_->operation eq 'Call' && $_->is_sub_call && !$self->_callees($_) } $nodes->@* )
            && grep { $_->operation eq 'PostfixDeref' && ( $_->sigil // '' ) eq '&'
                      || $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'indirect' && !$self->_callees($_) } $nodes->@*;
        # WHAT MAY RUN: the program, its blocks, the subs they may call -- by
        # name, by a code value named, by a name perl calls itself (DESTROY,
        # AUTOLOAD, a tie's FETCH: all capitals) -- or every sub, where a
        # call may run any. A sub nothing may call makes no reference.
        my %sub_live;
        my @todo = grep { !$in_sub{ refaddr($_) } } $nodes->@*;
        my $wake = sub ($sub) { push @todo, $sub->graph->component unless $sub_live{ refaddr($sub) }++ };
        $wake->($_) for $any_code ? @subs : grep { ( $_->name // '' ) =~ /\A(?:.*::)?[A-Z_]+\z/ } @subs;
        while ( defined( my $n = shift @todo ) ) {
            next if $live{ refaddr($n) }++;
            my $op = $n->operation;
            $wake->($_) for $op eq 'Call' && !$n->is_builtin ? $self->_callees($n) : ();
            $wake->($_) for $op eq 'Call' && blessed( $n->can('sort_cmp_sub') ? $n->sort_cmp_sub : undef ) && $n->sort_cmp_sub->can('graph') ? $n->sort_cmp_sub : ();
            if ( $op eq 'Constant' && ( $n->const_type // '' ) eq 'code' ) {
                for my $sub ( ( $by_short{ ( $n->value // '' ) =~ s/\A.*:://r } // [] )->@* ) { $code_taken{ refaddr($sub) } = 1; $wake->($sub) }
            }
        }
        $self->_index;
    }

    # _index: the uses, locations, calls and returns of the live nodes.
    method _index () {
        %uses = %at = %callers = %sub_of_ret = %code_call = ();
        @code_calls = ();
        for my $sub (@subs) { $sub_of_ret{ refaddr($_) } = $sub for $sub->graph->returns->@* }
        for my $n ( grep { $live{ refaddr($_) } } $nodes->@* ) {
            my @in = $n->inputs->@*;
            for my $i ( 0 .. $#in ) {
                push $uses{ refaddr( $in[$i] ) }->@*, [ $n, $i ] if blessed( $in[$i] );
            }
            # A CELL MADE AT A VERSION holds the variable as that version left
            # it: what a store there put into it reaches the closure through
            # the cell (position -1: no value input).
            push $uses{ refaddr( $n->mem_in ) }->@*, [ $n, -1 ]
                if $n->operation eq 'MakeCell' && blessed( $n->mem_in );
            my $k = _location_key($n);
            push $at{$k}->@*, $n if defined $k;
            if ( $n->operation eq 'PostfixDeref' && ( $n->sigil // '' ) eq '&'
                || $n->operation eq 'Call' && !$n->is_builtin && !blessed( $n->target ) && ( $n->dispatch_kind // '' ) !~ /\A(?:method|direct)\z/ ) {
                push @code_calls, $n;
                $code_call{ refaddr($n) } = 1;
            }
            $ties = 1 if $n->operation eq 'Call' && $n->is_tie_builtin;
            next unless $n->operation eq 'Call' && $n->is_sub_call;
            for my $sub ( $self->_callees($n) ) {
                push $callers{ refaddr($sub) }->@*, $n;
                # (an anonymous sub called directly is no MOP class's: its
                # returns are found from the call, its code value is taken)
                next unless $sub->can('graph') && blessed( $sub->graph );
                $sub_of_ret{ refaddr($_) } //= $sub for $sub->graph->returns->@*;
                $code_taken{ refaddr($sub) } = 1 if !grep { refaddr($_) == refaddr($sub) } ( $by_short{ ( $sub->name // '' ) =~ s/\A.*:://r } // [] )->@*;
            }
        }
    }

    # _location_key($node) -> the variable, global or field a node names
    # (every read and every store target of it share one), or undef.
    sub _location_key ($n) {
        my $op = $n->operation;
        # (a `my` by its name: same-named ones in other subs are one location
        # here -- more held, never less; a `my @a = (...)` is its literal)
        return 'pad:' . ( $n->sigil // '' ) . ( $n->symbol // '' ) if $op eq 'PadAccess';
        return 'pad:' . ( $op eq 'ArrayLiteral' ? '@' : '%' ) . $n->symbol if $op =~ /\A(?:Array|Hash)Literal\z/ && defined $n->symbol;
        return 'gv:' . ( $n->sigil // '' ) . $n->qualified_name if $op eq 'EntryDef';
        return 'field:' . ( $n->field_stash // '' ) . ':' . ( $n->field_index // '' ) if $op eq 'FieldAccess';
        return undef;
    }

    # _callees($Call) -> the MOP subs a sub call may run: its resolved target,
    # else every sub of the method's name (dispatch at run time).
    method _callees ($c) {
        my %seen;
        return grep { !$seen{ refaddr($_) }++ }
            ( blessed( $c->target ) ? $c->target : () ),
            # (a method: whichever class's the object is, at run time)
            ( !blessed( $c->target ) || ( $c->dispatch_kind // '' ) eq 'method'
                ? ( $by_short{ ( $c->name // '' ) =~ s/\A.*:://r } // [] )->@* : () );
    }

    # scalar_deref_reached(@refs) -> undef where no value of these Refs may
    # reach the reference operand of a `$` deref; else why it may: a string
    # naming the deref reached, or the place the value escaped the walk.
    method scalar_deref_reached (@refs) {
        return $self->_walk( [ grep { $live{ refaddr($_) } } @refs ], sub ($c, $pos) {
            $c->operation eq 'PostfixDeref' && $pos == 0 && ( $c->sigil // '' ) eq '$' && !$c->alias_element ? 'a scalar deref' . _site($c) : undef } );
    }

    # _walk(\@seeds, $hit) -> the first reason $hit->($consumer, $position)
    # gives for a use of a value the seeds may be, or where one escapes the
    # walk; undef where neither.
    method _walk ($seeds, $hit) {
        my ( %held, %loc_done, @work );
        my $hold = sub ($n) { push @work, $n unless $held{ refaddr($n) }++ };
        my $store = sub ($t) {
            # A STORE INTO an element is into its container; through a
            # reference, into what it may name -- not followed.
            $t = $t->inputs->[0] while blessed($t) && $t->operation eq 'Subscript';
            my $k = blessed($t) ? _location_key($t) : undef;
            return 'a store into ' . ( blessed($t) ? $t->operation : 'nothing' ) . _site($t) unless defined $k;
            return undef if $loc_done{$k}++;
            $hold->($_) for ( $at{$k} // [] )->@*;
            return undef;
        };
        $hold->($_) for $seeds->@*;
        while ( defined( my $v = shift @work ) ) {
            for my $u ( ( $uses{ refaddr($v) } // [] )->@* ) {
                my ( $c, $pos ) = @$u;
                my $op = $c->operation;
                # (as the memory a node reads at -- its mem_in -- it is no
                # use of a value: $uses holds inputs only)
                if ( defined( my $why = $hit->( $c, $pos ) ) ) { return $why }
                if ( $op eq 'PostfixDeref' ) {
                    next unless $pos == 0;
                    $hold->($c);
                    next;
                }
                if ( $op eq 'Assign' || $op eq 'CompoundAssign' ) {
                    my $nt = defined( $c->can('targets') ? $c->targets : undef ) ? $c->targets : 1;
                    next if $pos < $nt;    # a target, not the value stored
                    for my $t ( $c->inputs->@[ 0 .. $nt - 1 ] ) {
                        next unless blessed($t);
                        # (`my ($a, $b) = @_`: a parameter, held where it is read)
                        if ( $t->operation eq 'PadAccess' && !$t->is_location ) { $hold->($t); my $why = $store->($t); return $why if $why; next }
                        my $why = $store->($t);
                        return $why if $why;
                    }
                    $hold->($c);
                    next;
                }
                if ( $op eq 'EntryWrite' ) {
                    next if $pos == 0;
                    my $why = $store->( $c->inputs->[0] );
                    return $why if $why;
                    next;
                }
                if ( $op eq 'Return' ) {
                    my $sub = $sub_of_ret{ refaddr($c) };   # (none: the program's end, or a sub no MOP holds)
                    # (a TIED variable's read is its FETCH's return: not followed)
                    return 'a return from ' . ( blessed($sub) ? $sub->name : 'a sub' ) . ' where a tie may read it' if $ties;
                    # (a call through a code value, or of a name made at run
                    # time, may be of this sub where its code is taken: each
                    # is a caller)
                    $hold->($_) for !blessed($sub) || $any_code || $code_taken{ refaddr($sub) } ? @code_calls : ();
                    $hold->($_) for blessed($sub) ? ( $callers{ refaddr($sub) } // [] )->@* : ();
                    next;
                }
                if ( $op eq 'Call' && $c->is_sub_call ) {
                    my @callee = $self->_callees($c);
                    return 'an argument of ' . ( $c->name // 'a call' ) . _site($c) . ' to no sub the program defines'
                        unless @callee && !grep { !blessed( $_->graph ) } @callee;
                    for my $sub (@callee) {
                        $hold->($_) for grep { $_->operation =~ /\A(?:Parameter|ArgsSource)\z/ } $sub->graph->component;
                    }
                    next;
                }
                if ( $op eq 'Call' ) {
                    # A BUILTIN: one that may keep its operand escapes.
                    if ( $c->mutates_array ) {
                        if ( $pos == 0 ) { $hold->($c); next }   # an element taken off it
                        my $why = $store->( $c->inputs->[0] );
                        return $why if $why;
                        next;
                    }
                    return 'an operand of ' . ( $c->name // 'a builtin' ) . _site($c)
                        if $c->is_tie_builtin || $c->changes_state || $c->writes_first_argument
                        || ( $c->builtin_kind // '' ) eq 'selects_output';
                    next if $c->does_handle_io;
                    next if _plain_scalar( $c->result_type );
                    if ( ( $c->builtin_kind // '' ) eq 'blesses' || $c->reorders_list ) { $hold->($c); next }
                    return 'an operand of ' . ( $c->name // 'a builtin' ) . _site($c);
                }
                # CONTROL: a branch on it, a join -- no value.
                next if $op =~ /\A(?:If|Region|Loop|Start)\z/;
                next if $op eq 'Phi' && $c->is_memory;
                if ( $op =~ /\A(?:Unwind|CellWrite|MakeCell|LocalAlias|ElemRestore|ListAssign|VarDecl)\z/ ) {
                    return 'a ' . $op . _site($c);
                }
                # A PLAIN SCALAR made of it is no reference.
                # (not a choice: its stamp is its arms' join, which a stamp
                # missing a reference arm -- B::SoN's, by the read -- would hide)
                next if _plain_scalar( $c->stamp ) && $op !~ /\A(?:Phi|TernaryExpr|DefinedOr|Or|And)\z/;
                # (any other store: not followed)
                return 'a ' . $op . ' storing it' if $c->is_memory_version && $op !~ /\A(?:Subscript|Count|Exists|Delete|Ref|Match|RegexMatch|Transliterate|RegexSubst)\z/;
                $hold->($c);
            }
        }
        return undef;
    }

    sub _plain_scalar ($type) { return ( $type // '' ) =~ /\A(?:Int|Num|Str|Boolean|Undef|Maybe\[Boolean\])\z/ ? 1 : 0 }

    sub _site ($n) {
        return $n->can('line') && defined $n->line ? ' at ' . ( $n->file // '-' ) . ' line ' . $n->line : '';
    }
}

1;
