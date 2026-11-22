# ABOUTME: Checks a B::SoN wire before it is loaded for what chalk would lower wrong -- a read at no
# ABOUTME: memory version beside a write, a DESTROY, a die skipping a local -- refused here, by name.
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
    # The wire's die has its way out (wire v2's `eval` profile): the restores
    # on it and the eval's $@ store are on the wire, and W6 is not needed.
    field $eval_edges :param = 0;
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

    # What control reaches a node from: its control_in, a Region's every way
    # in, an If's, Proj's or Loop's first input.
    method _preds( $g, $n ) {
        my @p = defined $n->{control_in} ? ( $n->{control_in} ) : ();
        my @in = $self->_inputs($n);
        push @p, $n->{op} eq 'Region' ? @in : $n->{op} =~ /\A(?:If|Proj|Loop)\z/ ? @in[ 0 .. ( @in ? 0 : -1 ) ] : ();
        my %seen;
        return grep { defined && !$seen{ $_->{id} }++ } map { defined $_ ? $g->{by}{$_} : undef } @p;
    }

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

    # W6. `local` IS PUT BACK ONLY ON THE WAYS OUT B::SoN WROTE A RESTORE FOR.
    method _has_eval() {
        return scalar grep { defined $self->_f( $_->[1], 'eval_id' ) || defined $self->_f( $_->[1], 'eval_entry' ) } $self->_all_nodes;
    }

    # A die leaves a sub by no way on the wire, so a `local` there is not put
    # back: `sub t { local $g = 2; die } eval { t() }` left $g 2. Refused
    # where an eval is in the program and a die of the sub's own stands
    # between a `local` store and its restore. (A die in a sub it calls
    # there is not seen: Test::Chalk's subtest, which every test would lose.)
    method _locals_a_die_skips($name) {
        my $g = $self->_graph($name);
        my %restored;    # variable => { restore node id => 1 }
        for my $w ( grep { $_->{op} eq 'EntryWrite' } $g->{nodes}->@* ) {
            my $v   = $g->{by}{ ( $self->_inputs($w) )[1] // '' };
            my $var = $self->_written_pkg( $g, $w ) // next;
            # (a try or an eval puts $@ back itself; a die sets it anyway)
            next if $var eq '$main::@';
            $restored{$var}{ $w->{id} } = 1
                if $self->_f( $w, 'binds' ) || defined $v && $v->{op} eq 'EntryDef' && defined $v->{mem_in} && $self->_pkg_name($v) eq $var;
        }
        return unless %restored;
        for my $u ( grep { $_->{op} eq 'Unwind' && !defined $self->_f( $_, 'eval_id' ) } $g->{nodes}->@* ) {
            my ( %seen, @q );
            @q = $self->_preds( $g, $u );
            while ( defined( my $x = shift @q ) ) {
                next if $seen{ $x->{id} }++;
                my $var = $self->_written_pkg( $g, $x );
                if ( defined $var && $restored{$var} ) {
                    next if $restored{$var}{ $x->{id} };    # (put back before the die)
                    $self->_gap("a `local` ($var) in a sub a die leaves, under an eval: the die's way out restores nothing (in $name)");
                }
                push @q, $self->_preds( $g, $x );
            }
        }
        return;
    }

    # A store to a package variable in an eval block that dies may be a
    # `local`'s, whose restore the die skips and the wire does not write.
    # B::SoN reads what a `local` is to put back at the memory version its
    # store replaces (an EntryDef of the variable there, which nothing takes
    # once the restore is gone), so a store with such a read beside it is
    # refused -- `$g = $g + 2` has the same read -- and one without is a
    # plain store. In a graph with a loop a `local` may save a value the
    # loop carries instead, with no read: refused there as before.
    method _stores_in_a_dying_eval($name) {
        my $g = $self->_graph($name);
        my $has_loop = grep { $_->{op} eq 'Loop' } $g->{nodes}->@*;
        for my $u ( grep { $_->{op} eq 'Unwind' && defined $self->_f( $_, 'eval_id' ) } $g->{nodes}->@* ) {
            my $id = $self->_f( $u, 'eval_id' );
            my ($join) = grep { $_->{op} eq 'Region' && ( $self->_f( $_, 'eval_id' ) // '' ) eq $id } $g->{nodes}->@*;
            my $entry = defined $join ? $self->_f( $join, 'eval_entry' ) : undef;
            next unless defined $entry;
            my ( %seen, @q );
            @q = $self->_preds( $g, $u );
            while ( defined( my $x = shift @q ) ) {
                next if $seen{ $x->{id} }++ || $x->{id} == $entry;
                my $var = $self->_written_pkg( $g, $x );
                $self->_gap("a store to a package variable ($var) in an eval block that dies: the wire does not say whether it is a `local`, whose restore the die would skip (in $name)")
                    if defined $var && $var ne '$main::@' && ( $has_loop || $self->_may_be_a_local( $g, $x, $var ) );
                push @q, $self->_preds( $g, $x );
            }
        }
        return;
    }

    # _may_be_a_local($g, $store, $var) -> true where a read of $var from
    # memory stands at the version $store replaces, or is taken by nothing:
    # the read a `local` saves its old value with.
    method _may_be_a_local( $g, $store, $var ) {
        my $replaced = $store->{mem_in};
        for my $r ( grep { $_->{op} eq 'EntryDef' && ( $self->_pkg_name($_) // '' ) eq $var } $g->{nodes}->@* ) {
            my $at = $r->{mem_in};
            next unless defined $at;    # (the variable's name, not a read of it)
            return 1 if defined $replaced && $at == $replaced;
            return 1 unless ( $g->{cons}{ $r->{id} } // [] )->@*;
        }
        return 0;
    }

    # W7. A DIE OF A REFERENCE: T2's $@ is the die's message, a string.
    method _dies_of_references() {
        return unless $self->_has_eval;
        for my $e ( grep { $_->[1]{op} eq 'Unwind' } $self->_all_nodes ) {
            my ( $name, $n ) = $e->@*;
            my $g = $self->_graph($name);
            for my $v ( map { $g->{by}{ $_ // '' } // () } $self->_inputs($n) ) {
                next if $v->{op} eq 'MemStart' || $v->{op} eq 'Constant';
                next if ( $v->{stamp} // '' ) =~ /\A(?:Str|Int|Num|Boolean)\z/;
                next if ( $self->_pkg_name($v) // '' ) eq '$main::@';
                $self->_gap("a die of what may be a reference, where an eval may catch it: \$@ would be its string, not the reference (in $name)");
            }
        }
        return;
    }

    method check() {
        # W8. chalk frees nothing, so a DESTROY is never called: refused
        # where the program may bless into the DESTROY's package (a class
        # it names there, or one made at run time).
        for my $d ( grep { /::DESTROY\z/ } sort keys $defined->%* ) {
            # (one that does nothing -- Config's `sub DESTROY { }` -- is not missed)
            next if $self->_inert($d);
            my $pkg = $d =~ s/::DESTROY\z//r;
            for my $e ( grep { $self->_is_bless( $_->[1] ) } $self->_all_nodes ) {
                my ( $name, $n ) = $e->@*;
                my @in = $self->_inputs($n);
                my $class = @in > 1 ? $self->_graph($name)->{by}{ $in[1] // '' } : undef;
                next if defined $class && $class->{op} eq 'Constant' && ( $self->_f( $class, 'value' ) // '' ) ne $pkg;
                $self->_gap("a DESTROY method ($d): chalk never destroys an object, so it would never run");
            }
        }
        for my $name ( sort keys $methods->%* ) {
            $self->_autovivifying_reads($name);
            $self->_unread_derefs($name);
            $self->_stores_in_a_dying_eval($name) unless $eval_edges;
        }
        $self->_captured_arguments_written;
        if ( $self->_has_eval && !$eval_edges ) { $self->_locals_a_die_skips($_) for sort keys $methods->%* }
        $self->_dies_of_references;
        return;
    }
}

1;
