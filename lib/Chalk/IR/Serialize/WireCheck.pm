# ABOUTME: Checks a B::SoN wire before it is loaded for what chalk would lower wrong -- a read at no
# ABOUTME: memory version beside a write, a DESTROY, an argument a closure captured -- refused here, by name.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Grammar::Perl::BuiltinTable;

# WHY THE WIRE AND NOT THE GRAPH (docs: the IR audit of 2026-11-19). The
# loader drops what control does not reach, so a write B::SoN left floating
# is gone from the loaded graph, and a checker over that graph says "ok" of a
# program whose store was never made. Every rule here is a STOPGAP for a gap
# in the producer or the wire format: it refuses, it never repairs.
#
# AN EFFECT ON NO CONTROL CHAIN, and a division that may die floating, were
# refused here until wire v2 stage 6: on v2 the loader's invariant
# (WireInvariant) refuses a memory version off the chain, and B::SoN pins a
# division that may fault; with both rules off no audit probe changed.
# A DIE SKIPPING A `local`, a store in an eval that dies, and a die of a
# reference were refused here until wire v2 stage 8: on its `eval` profile a
# die's way out (Exc) carries the restores, $@ is stored from the exception
# in flight, and a die outside an eval puts its locals back before it. Only
# a call dying under a `local` in a sub with no eval is left (W6, narrowed).
#
#   Chalk::IR::Serialize::WireCheck->new( methods => \%wire_graphs, defined => \%every_graph )->check;
#
# `methods` is the wire's graphs the program may run (name => { nodes => [...] });
# `defined` holds every sub the program's own file defines, run or not (not a
# module's it loads: Config's DESTROY is of an object no program here makes).
# check() returns nothing, or dies "GAP: ...\n" at the first rule broken.
class Chalk::IR::Serialize::WireCheck {
    field $methods :param;
    field $defined :param = {};    # every sub the program's own file defines (run or not): name => wire graph
    field %index;    # graph name => { by => { id => node }, cons => { id => [[consumer, slot], ...] } }

    # A store that is a node of its own (each takes memory as an input), a
    # print and a die: never off the chain.
    my %EFFECT_OP = map { $_ => 1 } qw(EntryWrite CellWrite Delete ElemRestore LocalAlias Print Unwind);
    # A change in place of its first operand.
    my %IN_PLACE = map { $_ => 1 } qw(Assign CompoundAssign RegexSubst Transliterate Chomp);

    method _gap($why) { die "GAP: $why\n" }

    method _graph($name) {
        return $index{$name} //= do {
            my $ns = ( $methods->{$name} // $defined->{$name} // {} )->{nodes} // [];
            my @nodes = ref $ns eq 'HASH' ? values $ns->%* : $ns->@*;
            my ( %by, %cons );
            for my $n (@nodes) {
                $by{ $n->{id} } = $n;
                my $slot = 0;
                for my $in ( $self->_inputs($n) ) {
                    push $cons{$in}->@*, [ $n, $slot ] if defined $in;
                    $slot++;
                }
                # A READ AT A VERSION uses it (slot -1: no value slot). What
                # only follows it on the chain -- a Return, a die, a store, a
                # sub call -- does not.
                push $cons{ $n->{mem_in} }->@*, [ $n, -1 ]
                    if defined $n->{mem_in} && !$self->_follows_memory($n);
            }
            { nodes => [ sort { $a->{id} <=> $b->{id} } @nodes ], by => \%by, cons => \%cons };
        };
    }

    method _inputs($n) { return map { ref $_ ? $_->@* : $_ } ( $n->{inputs} // [] )->@* }
    # What a node is made from: its values and the memory version it reads.
    method _deps($n) { return ( $self->_inputs($n), $n->{mem_in} // () ) }
    # A node whose mem_in is where it stands on the chain, not what it reads.
    method _follows_memory($n) {
        return 1 if $n->{op} =~ /\A(?:Return|Unwind|Assign)\z/;
        return $self->_is_sub_call($n);
    }
    method _f( $n, $key ) { return ( $n->{fields} // {} )->{$key} }
    method _pinned($n) { return defined $n->{control_in} ? 1 : 0 }

    method _is_sub_call($n) { return $n->{op} eq 'Call' && ( $self->_f( $n, 'dispatch_kind' ) // '' ) ne 'builtin' ? 1 : 0 }

    method _builtin_fact( $n, $column ) {
        return undef unless $n->{op} eq 'Call' && ( $self->_f( $n, 'dispatch_kind' ) // '' ) eq 'builtin';
        return Chalk::Grammar::Perl::BuiltinTable::fact( $self->_f( $n, 'name' ), $column );
    }
    method _is_bless($n)   { return ( $self->_builtin_fact( $n, 'kind' ) // '' ) eq 'blesses' ? 1 : 0 }

    # A package variable's name (`$main::g`), of its EntryDef.
    method _pkg_name($n) {
        return undef unless defined $n && $n->{op} eq 'EntryDef';
        return ( $self->_f( $n, 'sigil' ) // '$' ) . ( $self->_f( $n, 'package' ) // 'main' ) . '::' . ( $self->_f( $n, 'symbol' ) // '' );
    }

    # The package variable an EntryWrite stores to, by name; undef for another node.
    method _written_pkg( $g, $n ) {
        return undef unless $n->{op} eq 'EntryWrite';
        return $self->_pkg_name( $g->{by}{ ( $self->_inputs($n) )[0] // '' } );
    }

    method _inert($name) {
        my $g = $self->_graph($name);
        for my $n ( $g->{nodes}->@* ) {
            return 0 if $self->_pinned($n) && $n->{op} ne 'Return';
            return 0 if $n->{op} eq 'MemStart' && grep { $_->[0]{op} ne 'Return' } ( $g->{cons}{ $n->{id} } // [] )->@*;
            return 0 if $n->{op} eq 'Call' || $EFFECT_OP{ $n->{op} } || $IN_PLACE{ $n->{op} };
        }
        return 1;
    }

    # ------------------------------------------------------------------
    # W10. A `my` ARRAY OR HASH A SUB ALSO REACHES (B::SoN's `shared`),
    # flattened beside a sub call -- in one list, one call's arguments, one
    # join: the call may change it, and T2 reads such an aggregate where the
    # list is made, after the call -- `(@a, f())` with f pushing onto @a gave
    # `1 2 0` for `1 0`.
    # ------------------------------------------------------------------
    method _shared_aggregate_read_before_a_call($name) {
        my $g = $self->_graph($name);
        my $call = sub ($id) {
            my $c = $g->{by}{ $id // '' } // return 0;
            $c = $g->{by}{ ( $self->_inputs($c) )[0] // '' } // return 0 while $c->{op} eq 'Coerce';
            return $c->{op} eq 'Call' && ( $self->_f( $c, 'dispatch_kind' ) // '' ) ne 'builtin';
        };
        my $agg = sub ($id) {
            my $n = $g->{by}{ $id // '' } // return 0;
            return $n->{op} eq 'PadAccess' && $self->_f( $n, 'shared' ) && ( $self->_f( $n, 'sigil' ) // '' ) =~ /\A[\@%]\z/;
        };
        # (beside it: one list, one call's arguments, one join -- perl takes
        # the aggregate's elements where it stands, before the call runs)
        for my $n ( $g->{nodes}->@* ) {
            my @in = grep { defined } $self->_inputs($n);
            for my $i ( grep { $agg->( $in[$_] ) } 0 .. $#in ) {
                $self->_gap("a `my` aggregate a sub also reaches, flattened beside a call that may change it (in $name)")
                    if grep { $call->( $in[$_] ) } $i + 1 .. $#in;
            }
        }
        return;
    }

    # ------------------------------------------------------------------
    # W9. A READ THROUGH AN ELEMENT THAT IS NOT THERE makes it in perl
    # (`$h->{b}{c}` leaves $h->{b} a hash); T2's read makes nothing.
    # Refused where B::SoN knows the element is missing (its stamp, Undef).
    # ------------------------------------------------------------------
    method _autovivifying_reads($name) {
        my $g = $self->_graph($name);
        for my $n ( grep { $_->{op} eq 'Subscript' && defined $_->{mem_in} } $g->{nodes}->@* ) {
            my $c = $g->{by}{ ( $self->_inputs($n) )[0] // '' } // next;
            next unless $c->{op} eq 'Subscript' && ( $c->{stamp} // '' ) eq 'Undef';
            # (a store through it made it: `$r->{a}{b} = 3; print $r->{a}{b}`)
            next if grep { $_->[1] == 0 && ( $_->[0]{op} eq 'Assign' || $_->[0]{op} eq 'Subscript' && !defined $_->[0]{mem_in} ) } ( $g->{cons}{ $c->{id} } // [] )->@*;
            $self->_gap("a read through an element that is not there, which perl makes (autovivification) (in $name)");
        }
        return;
    }



    # A dereference pinned where it may die (of undef, under strict refs)
    # that nothing reads is not made by T2, and neither is its copy:
    # `my @l = @$r` of an undef $r, @l unused, did not die.
    method _unread_derefs($name) {
        my $g = $self->_graph($name);
        my @derefs = grep { $_->{op} eq 'PostfixDeref' && ( $self->_f( $_, 'sigil' ) // '' ) =~ /\A[\@%]\z/ } $g->{nodes}->@*;
        for my $n ( grep { $self->_pinned($_) && !( $g->{cons}{ $_->{id} } // [] )->@* } @derefs ) {
            my ($c) = $self->_inputs($n);
            my $of = $g->{by}{ $c // '' };
            next if defined $of && ( $of->{stamp} // '' ) =~ /\A(?:ArrayRef|HashRef)\z/;
            next if grep { $_->{id} != $n->{id} && ( ( $self->_inputs($_) )[0] // -1 ) == ( $c // -2 ) && ( $g->{cons}{ $_->{id} } // [] )->@* } @derefs;
            $self->_gap("a dereference nothing reads, which may still die (of undef, under strict refs) (in $name)");
        }
        return;
    }

    # ------------------------------------------------------------------
    # PROGRAM-WIDE RULES.
    # ------------------------------------------------------------------
    method _all_nodes() { return map { my $name = $_; map { [ $name, $_ ] } $self->_graph($name)->{nodes}->@* } sort keys $methods->%* }

    # W5. `$_[N]` IS THE CALLER'S VARIABLE. T2 hands a captured variable to
    # a call by value, so a sub that writes its argument wrote a copy.
    method _captured_arguments_written() {
        my @writers = grep {
            my $g = $self->_graph($_);
            grep {
                my $t = $g->{by}{ ( $self->_inputs($_) )[0] // '' };
                $IN_PLACE{ $_->{op} } && defined $t && $t->{op} eq 'Subscript'
                    && ( ( $g->{by}{ ( $self->_inputs($t) )[0] // '' } // {} )->{op} // '' ) eq 'ArgsSource'
            } $g->{nodes}->@*
        } sort keys $methods->%* or return;
        my %writer = map { ( $_ => 1 ) } @writers;
        for my $e ( grep { $self->_is_sub_call( $_->[1] ) } $self->_all_nodes ) {
            my ( $name, $n ) = $e->@*;
            my $g = $self->_graph($name);
            next unless grep { ( ( $g->{by}{ $_ // '' } // {} )->{op} // '' ) eq 'CellRead' } $self->_inputs($n);
            my $callee = $self->_f( $n, 'name' ) // '';
            next if ( $self->_f( $n, 'dispatch_kind' ) // '' ) eq 'direct' && exists $methods->{$callee} && !$writer{$callee};
            $self->_gap("a captured variable passed to a sub that writes its argument (\$_[N] is the caller's variable; the closure would not see the write) (the call in $name)");
        }
        return;
    }

    # W6 (narrowed, stage 8). A CALL THAT DIES UNDER A LIVE `local`, in a sub
    # with no eval of its own, leaves by no way on the wire: its die is the
    # callee's, and the restore B::SoN writes stands after it (a die of the
    # sub's own puts its locals back first; one in an eval has its edge).
    # `sub t { local $g = 2; u() } eval { t() }` left $g 2. Refused where an
    # eval is in the program, a sub call outside any eval of its graph, and a
    # store to a package variable the graph restores somewhere stands before
    # the call with no restore of it between (the plan's Q9: a rethrow that
    # restores first is its way out).
    method _calls_a_local_dies_through($name) {
        my $g = $self->_graph($name);
        my %restored;    # variable => { restore node id => 1 }
        for my $w ( grep { $_->{op} eq 'EntryWrite' } $g->{nodes}->@* ) {
            my $v   = $g->{by}{ ( $self->_inputs($w) )[1] // '' };
            my $var = $self->_written_pkg( $g, $w ) // next;
            next if $var eq '$main::@';    # (an eval puts $@ back itself)
            $restored{$var}{ $w->{id} } = 1
                if $self->_f( $w, 'binds' ) || defined $v && $v->{op} eq 'EntryDef' && defined $v->{mem_in} && ( $self->_pkg_name($v) // '' ) eq $var;
        }
        return unless %restored;
        # (A FAULT OF THE SUB'S OWN, a division or a dereference that names
        # where it dies, leaves by no way either: `sub f { local $g = 2; 1/$_[0]
        # } eval { f(0) }` left $g 2 -- re-audit 2026-11-23, class B.)
        for my $c ( grep {
                defined $_->{control_in} && !defined $self->_f( $_, 'eval_id' )
                && ( $self->_faults_itself($_) || $self->_is_sub_call($_) && $self->_call_may_die($_) )
            } $g->{nodes}->@* ) {
            my $what = $self->_faults_itself($c) ? "a $c->{op}" : 'a call';
            my ( %seen, @q );
            @q = $self->_preds( $g, $c );
            while ( defined( my $x = shift @q ) ) {
                next if $seen{ $x->{id} }++;
                my $var = $self->_written_pkg( $g, $x );
                if ( defined $var && $restored{$var} ) {
                    next if $restored{$var}{ $x->{id} };    # (put back before the call)
                    $self->_gap("$what that may die under a `local` ($var), in a sub with no eval (in $name)");
                }
                push @q, $self->_preds( $g, $x );
            }
        }
        return;
    }

    # _call_may_die($call) -> false only for a direct call of a sub of this
    # wire none of whose nodes may die: no die, no division or dereference
    # that names where it dies, no call but such calls.
    method _call_may_die($c) {
        my $name = $self->_f( $c, 'name' ) // '';
        return 1 unless ( $self->_f( $c, 'dispatch_kind' ) // '' ) eq 'direct' && exists $methods->{$name};
        return $self->_graph_may_die($name, {});
    }
    # _faults_itself($node) -> a division or a dereference that names where it
    # dies (B::SoN gives such a node its line).
    method _faults_itself($n) {
        return defined $self->_f( $n, 'line' ) && $n->{op} =~ /\A(?:Divide|Modulo|PostfixDeref|Ref)\z/ ? 1 : 0;
    }
    method _graph_may_die( $name, $seen ) {
        return 0 if $seen->{$name}++;
        for my $n ( $self->_graph($name)->{nodes}->@* ) {
            return 1 if $n->{op} eq 'Unwind' || $self->_faults_itself($n);
            next unless $self->_is_sub_call($n);
            my $callee = $self->_f( $n, 'name' ) // '';
            return 1 unless ( $self->_f( $n, 'dispatch_kind' ) // '' ) eq 'direct' && exists $methods->{$callee};
            return 1 if $self->_graph_may_die( $callee, $seen );
        }
        return 0;
    }

    # What control reaches a node from: its control_in, a Region's every way
    # in, an If's, Proj's or Loop's first input.
    method _preds( $g, $n ) {
        my @p = defined $n->{control_in} ? ( $n->{control_in} ) : ();
        my @in = $self->_inputs($n);
        push @p, $n->{op} eq 'Region' ? @in : $n->{op} =~ /\A(?:If|Proj|Loop|Exc)\z/ ? @in[ 0 .. ( @in ? 0 : -1 ) ] : ();
        my %seen;
        return grep { defined && !$seen{ $_->{id} }++ } map { defined $_ ? $g->{by}{$_} : undef } @p;
    }

    method check() {
        # W8. chalk frees nothing, so a DESTROY is never called: refused
        # where the program may bless into the DESTROY's package (a class
        # it names there, or one made at run time).
        # ANY CLASS MAY REACH IT: by @ISA, or through an AUTOLOAD perl calls
        # for DESTROY -- the match on the bless's own class name missed both
        # (audit 2026-11-22, W8). So any bless, in a program with either.
        for my $d ( grep { /::(?:DESTROY|AUTOLOAD)\z/ } sort keys $defined->%* ) {
            # (one that does nothing -- Config's `sub DESTROY { }` -- is not missed)
            next if $self->_inert($d);
            next unless grep { $self->_is_bless( $_->[1] ) } $self->_all_nodes;
            $self->_gap("a DESTROY method ($d), or an AUTOLOAD perl calls for one: chalk never destroys an object, so it would never run");
        }
        for my $name ( sort keys $methods->%* ) {
            $self->_shared_aggregate_read_before_a_call($name);
            $self->_autovivifying_reads($name);
            $self->_unread_derefs($name);
        }
        $self->_captured_arguments_written;
        if ( grep { defined $self->_f( $_->[1], 'eval_id' ) } $self->_all_nodes ) { $self->_calls_a_local_dies_through($_) for sort keys $methods->%* }
        return;
    }
}

1;
