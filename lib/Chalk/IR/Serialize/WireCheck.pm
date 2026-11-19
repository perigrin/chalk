# ABOUTME: Checks a B::SoN wire before it is loaded: an effect on no control chain, or a read at
# ABOUTME: no memory version beside a write, would be lowered wrong -- refused here, by name.
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
#   Chalk::IR::Serialize::WireCheck->new( methods => \%wire_graphs, defined => \@names )->check;
#
# `methods` is the wire's graphs the program may run (name => { nodes => [...] });
# `defined` names every sub the wire defines, run or not.
# check() returns nothing, or dies "GAP: ...\n" at the first rule broken.
class Chalk::IR::Serialize::WireCheck {
    field $methods :param;
    field $defined :param = [];    # every sub the wire defines, by name (run or not)
    field %index;    # graph name => { by => { id => node }, cons => { id => [[consumer, slot], ...] } }

    my %STRUCTURE = map { $_ => 1 } qw(Start Region Proj If Loop Return);
    # A store that is a node of its own (each takes memory as an input), a
    # print and a die: never off the chain.
    my %EFFECT_OP = map { $_ => 1 } qw(EntryWrite CellWrite Delete ElemRestore LocalAlias Print Unwind);
    # A change in place of its first operand.
    my %IN_PLACE = map { $_ => 1 } qw(Assign CompoundAssign RegexSubst Transliterate Chomp);
    # A read B::SoN pins to order it: it changes nothing.
    my %PINNED_READ = map { $_ => 1 } qw(Subscript Slice PostfixDeref Exists Ref PadAccess EntryDef Count CellRead FieldAccess RefType);

    method _gap($why) { die "GAP: $why\n" }

    method _graph($name) {
        return $index{$name} //= do {
            my $ns = $methods->{$name}{nodes} // [];
            my @nodes = ref $ns eq 'HASH' ? values $ns->%* : $ns->@*;
            my ( %by, %cons );
            for my $n (@nodes) {
                $by{ $n->{id} } = $n;
                my $slot = 0;
                for my $in ( $self->_inputs($n) ) {
                    push $cons{$in}->@*, [ $n, $slot ] if defined $in;
                    $slot++;
                }
            }
            { nodes => [ sort { $a->{id} <=> $b->{id} } @nodes ], by => \%by, cons => \%cons };
        };
    }

    method _inputs($n) { return map { ref $_ ? $_->@* : $_ } ( $n->{inputs} // [] )->@* }
    method _f( $n, $key ) { return ( $n->{fields} // {} )->{$key} }
    method _pinned($n) { return defined $n->{control_in} ? 1 : 0 }

    method _is_sub_call($n) { return $n->{op} eq 'Call' && ( $self->_f( $n, 'dispatch_kind' ) // '' ) ne 'builtin' ? 1 : 0 }

    method _builtin_fact( $n, $column ) {
        return undef unless $n->{op} eq 'Call' && ( $self->_f( $n, 'dispatch_kind' ) // '' ) eq 'builtin';
        return Chalk::Grammar::Perl::BuiltinTable::fact( $self->_f( $n, 'name' ), $column );
    }
    method _is_bless($n)   { return ( $self->_builtin_fact( $n, 'kind' ) // '' ) eq 'blesses' ? 1 : 0 }
    method _is_class_read($n) {
        return $n->{op} eq 'RefType' || ( $self->_builtin_fact( $n, 'kind' ) // '' ) eq 'class_name' ? 1 : 0;
    }

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

    # A package array or hash read as a value with no memory version: its
    # bare EntryDef, or the literal B::SoN names after it (`@main::st`).
    method _pkg_aggregate($n) {
        return undef unless defined $n;
        return $self->_pkg_name($n)
            if $n->{op} eq 'EntryDef' && ( $self->_f( $n, 'sigil' ) // '' ) =~ /\A[\@%]\z/ && !$self->_inputs($n);
        return $self->_f( $n, 'symbol' )
            if $n->{op} =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && ( $self->_f( $n, 'symbol' ) // '' ) =~ /\A[\@%].*::/;
        return undef;
    }

    # _place($g, $t) -> what kind of place in memory an assignment's target
    # is, in words; undef for one that is no store of this node's: an SSA
    # `my` scalar (the Assign is a record of its new value), a package scalar
    # an EntryWrite stores beside it, a `my` or package array or hash (T2
    # asks Assign::is_placed of those, and refuses by its own name).
    method _place( $g, $t ) {
        return undef unless defined $t;
        my $op = $t->{op};
        if ( $op eq 'PadAccess' ) {
            return undef if ( $self->_f( $t, 'sigil' ) // '$' ) ne '$';
            return $self->_inputs($t) || $self->_f( $t, 'shared' ) ? 'a variable kept in memory' : undef;
        }
        if ( $op eq 'EntryDef' ) {
            return undef if ( $self->_f( $t, 'sigil' ) // '$' ) ne '$';
            return ( grep { $_->[0]{op} eq 'EntryWrite' && $_->[1] == 0 } ( $g->{cons}{ $t->{id} } // [] )->@* )
                ? undef : 'a package variable';
        }
        return undef if $op eq 'Constant' || $op =~ /\A(?:ArrayLiteral|HashLiteral)\z/;
        return 'an element'                if $op eq 'Subscript';
        return 'a slice'                   if $op eq 'Slice';
        return 'a dereference'             if $op eq 'PostfixDeref';
        return 'a field'                   if $op eq 'FieldAccess';
        return 'a captured variable'       if $op =~ /\A(?:MakeCell|CellRead|CellParam)\z/;
        return 'the arguments (@_)'        if $op eq 'ArgsSource';
        return "a call's value"            if $op eq 'Call';
        return "a $op";
    }

    # ------------------------------------------------------------------
    # (a) AN EFFECT ON NO CONTROL CHAIN. T2 makes a floating node at its
    # value's first use, and one nothing uses never: a store there is lost,
    # a call runs late or not at all.
    # ------------------------------------------------------------------
    method _floating_effects($name) {
        my $g = $self->_graph($name);
        for my $n ( grep { !$self->_pinned($_) } $g->{nodes}->@* ) {
            my $op = $n->{op};
            my $at = "(node $n->{id} of $name)";
            if ( $EFFECT_OP{$op} ) { $self->_gap("a write B::SoN left off the control chain: a $op $at") }
            # (a floating Chomp, RegexSubst or Transliterate is B::SoN's value
            # form, of a copy: `chomp $e` of a catch's $e)
            elsif ( $op eq 'Assign' ) {
                my @in = $self->_inputs($n);
                my $nt = $self->_f( $n, 'targets' ) // 1;
                my @targets = map { defined $_ ? $g->{by}{$_} : undef } @in[ 0 .. $nt - 1 ];
                my @rhs     = map { defined $_ ? $g->{by}{$_} : undef } @in[ $nt .. $#in ];
                my %places  = map { ( $_ => 1 ) } grep { defined } map { $self->_place( $g, $_ ) } @targets;
                next unless %places;
                $self->_gap( "a write B::SoN left off the control chain: "
                        . ( defined $self->_f( $n, 'targets' ) ? 'a list assignment' : 'an assignment' )
                        . ' to ' . join( ' and ', sort keys %places ) . " $at" );
            }
            elsif ( $self->_is_sub_call($n) ) {
                next if $self->_is_a_stores_place( $g, $n ) || $self->_calls_only_inert( $g, $n );
                my $kind = $self->_f( $n, 'dispatch_kind' ) // '';
                $self->_gap( "a call B::SoN left off the control chain: "
                        . ( $kind eq 'dynamic_method' ? 'a method call by a name made at run time' : 'a call of ' . ( $self->_f( $n, 'name' ) // 'a sub' ) )
                        . " $at" );
            }
            elsif ( $self->_is_bless($n) ) {
                # A bless of a fresh hash or array only the bless holds, its
                # value taken (`return bless {}, $class`): nothing sees the
                # unblessed one, so when it runs cannot show.
                my $x = $g->{by}{ ( $self->_inputs($n) )[0] // '' };
                next if defined $x && $x->{op} =~ /\A(?:HashLiteral|ArrayLiteral)\z/ && !defined $self->_f( $x, 'symbol' )
                    && ( $g->{cons}{ $x->{id} } // [] )->@* == 1 && ( $g->{cons}{ $n->{id} } // [] )->@*;
                $self->_gap("a bless B::SoN left off the control chain: it runs at its value's first use, or never, and another read of what it blesses may come first $at");
            }
            elsif ( $self->_builtin_fact( $n, 'acts' ) ) {
                $self->_gap( "a call B::SoN left off the control chain: " . $self->_f( $n, 'name' ) . " $at" );
            }
        }
        return;
    }

    # An lvalue call (`slot() = 42`): the place of stores that are on the chain.
    method _is_a_stores_place( $g, $n ) {
        my @c = ( $g->{cons}{ $n->{id} } // [] )->@*;
        return @c && !grep { !( $_->[0]{op} eq 'Assign' && $_->[1] == 0 && !defined $self->_f( $_->[0], 'targets' ) && $self->_pinned( $_->[0] ) ) } @c;
    }

    # A call whose every possible callee reads no memory and has no effect:
    # where it runs cannot show.
    method _calls_only_inert( $g, $n ) {
        my $kind = $self->_f( $n, 'dispatch_kind' ) // '';
        my @names;
        if ( $kind eq 'direct' ) { @names = grep { exists $methods->{$_} } ( $self->_f( $n, 'name' ) // '' ) }
        else {
            my $m = $kind eq 'method' ? $self->_f( $n, 'name' ) : do {
                my $c = $g->{by}{ ( $self->_inputs($n) )[1] // '' };
                defined $c && $c->{op} eq 'Constant' && ( $self->_f( $c, 'const_type' ) // '' ) eq 'string' ? $self->_f( $c, 'value' ) : undef;
            };
            return 0 unless defined $m && $m =~ /\A\w+\z/;
            @names = grep { /::\Q$m\E\z/ } keys $methods->%*;
        }
        return 0 unless @names;
        return !grep { !$self->_inert($_) } @names;
    }

    method _inert($name) {
        my $g = $self->_graph($name);
        for my $n ( $g->{nodes}->@* ) {
            return 0 if $self->_pinned($n) && $n->{op} ne 'Return';
            return 0 if $n->{op} eq 'MemStart' && ( $g->{cons}{ $n->{id} } // [] )->@*;
            return 0 if $n->{op} eq 'Call' || $EFFECT_OP{ $n->{op} } || $IN_PLACE{ $n->{op} };
        }
        return 1;
    }

    # ------------------------------------------------------------------
    # W1. A PACKAGE SCALAR CARRIED ROUND A LOOP AS A VALUE (a Phi) is not
    # read from memory in the loop, so a sub the loop calls cannot change
    # it: `$g = $g + 1; bump()` lost bump's `$g += 10`.
    # ------------------------------------------------------------------
    method _loop_carried_package_scalars($name) {
        my $g = $self->_graph($name);
        for my $phi ( grep { $_->{op} eq 'Phi' && !$self->_f( $_, 'memory' ) } $g->{nodes}->@* ) {
            my $loop = $g->{by}{ $self->_f( $phi, 'region' ) // '' };
            next unless defined $loop && $loop->{op} eq 'Loop';
            # It carries $var where what comes round is what the loop stores
            # to $var, and what comes in is $var's value before the loop.
            my ( $in, $round ) = $self->_inputs($phi);
            next unless defined $in && defined $round;
            my @stores = grep { $_->{op} eq 'EntryWrite' } $g->{nodes}->@*;
            for my $w (@stores) {
                my ( $target, $value ) = $self->_inputs($w);
                next unless defined $value && $value == $round;
                my $var = $self->_written_pkg( $g, $w ) // next;
                next unless $var =~ /\A\$/;
                next unless ( $self->_pkg_name( $g->{by}{$in} ) // '' ) eq $var
                    || grep { ( $self->_written_pkg( $g, $_ ) // '' ) eq $var && ( ( $self->_inputs($_) )[1] // -1 ) == $in } @stores;
                next unless grep { $self->_is_sub_call($_) && $self->_in_loop( $g, $_, $loop ) } $g->{nodes}->@*;
                next unless $self->_written_elsewhere( $name, $var );
                $self->_gap("a package scalar ($var) carried round a loop as a value, where a sub the loop calls may write it: the loop would not see the write (in $name)");
            }
        }
        return;
    }

    method _in_loop( $g, $n, $loop ) {
        my ( %seen, @q );
        @q = $self->_preds( $g, $n );
        while ( defined( my $x = shift @q ) ) {
            next if $seen{ $x->{id} }++;
            return 1 if $x->{id} == $loop->{id};
            if ( $x->{op} eq 'Proj' && ( ( $self->_inputs($x) )[0] // -1 ) == $loop->{id} ) {
                return 1 if ( $self->_f( $x, 'index' ) // 0 ) == 0;
                push @q, $self->_preds( $g, $loop );    # the way out: on to what is before the loop
                $seen{ $loop->{id} }++;
                next;
            }
            push @q, $self->_preds( $g, $x );
        }
        return 0;
    }

    method _written_elsewhere( $name, $var ) {
        for my $other ( grep { $_ ne $name } sort keys $methods->%* ) {
            my $o = $self->_graph($other);
            return 1 if grep { ( $self->_written_pkg( $o, $_ ) // '' ) eq $var } $o->{nodes}->@*;
        }
        return 0;
    }

    # ------------------------------------------------------------------
    # W10. A PACKAGE ARRAY OR HASH FLATTENED INTO A LIST carries no memory
    # version, so the list is made at its first use -- after a later store
    # to the array: `my @c = (@st, 2); @st = ()` read @st empty.
    # ------------------------------------------------------------------
    method _flattened_package_aggregates($name) {
        my $g = $self->_graph($name);
        for my $list ( grep { $_->{op} =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && !$self->_pinned($_) } $g->{nodes}->@* ) {
            for my $x ( map { defined $_ ? $g->{by}{$_} : () } $self->_inputs($list) ) {
                my $var = $self->_pkg_aggregate($x) // next;
                my @writes = grep {
                    my @in = $self->_inputs($_);
                    $self->_is_sub_call($_)
                        || ( ( $self->_written_pkg( $g, $_ ) // '' ) eq $var && ( $in[1] // -1 ) != $x->{id} && ( $in[1] // -1 ) != $list->{id} )
                        || ( $self->_builtin_fact( $_, 'acts' ) && ( $self->_pkg_name( $g->{by}{ $in[0] // '' } ) // '' ) eq $var )
                } $g->{nodes}->@*;
                $self->_gap("a package array or hash ($var) flattened into a list at no memory version, where it is also written: the list would be made after the write (in $name)")
                    if @writes;
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
        for my $n ( grep { $_->{op} eq 'Subscript' && ( () = $self->_inputs($_) ) >= 3 } $g->{nodes}->@* ) {
            my $c = $g->{by}{ ( $self->_inputs($n) )[0] // '' } // next;
            $self->_gap("a read through an element that is not there, which perl makes (autovivification) (in $name)")
                if $c->{op} eq 'Subscript' && ( $c->{stamp} // '' ) eq 'Undef';
        }
        return;
    }

    # ------------------------------------------------------------------
    # HASH TRUTH. `if (%h)`, `!%h`, `%h ? :` and `my $n = %h` hand the hash
    # itself to what wants a scalar: no count node, no memory version.
    # ------------------------------------------------------------------
    method _hashes_read_as_scalars($name) {
        my $g = $self->_graph($name);
        state %scalar_slot = ( If => 1, TernaryExpr => 0, Not => 0, And => 0, Or => 0, Xor => 0, DefinedOr => 0, Coerce => 0 );
        for my $n ( $g->{nodes}->@* ) {
            my $is_hash = $n->{op} eq 'PadAccess' && ( $self->_f( $n, 'sigil' ) // '' ) eq '%'
                || $n->{op} eq 'HashLiteral' && ( $self->_f( $n, 'sigil' ) // '' ) eq '%'
                || $n->{op} eq 'EntryDef' && ( $self->_f( $n, 'sigil' ) // '' ) eq '%' && !$self->_inputs($n);
            next unless $is_hash;
            for my $c ( ( $g->{cons}{ $n->{id} } // [] )->@* ) {
                my ( $user, $slot ) = $c->@*;
                my $op = $user->{op};
                $self->_gap("a hash read as a scalar (its truth or its count) at no memory version (in $name)")
                    if $op =~ /\A(?:Concat|Add|Subtract|Multiply)\z/ || exists $scalar_slot{$op} && ( $op =~ /\A(?:And|Or|Xor)\z/ || $scalar_slot{$op} == $slot );
            }
        }
        return;
    }

    # ------------------------------------------------------------------
    # W7. A FAULT HAS NO PLACE IN THE GRAPH.
    # ------------------------------------------------------------------

    # A division floats, so it dies where its value is first used: refused
    # where its divisor may be zero and something happens between the last
    # of what it is computed from and that first use (`my $q = 1 / $d;
    # print "before\n"; print $q` printed "before" and then died).
    method _floating_divisions($name) {
        my $g = $self->_graph($name);
        for my $n ( grep { $_->{op} =~ /\A(?:Divide|Modulo)\z/ && !$self->_pinned($_) } $g->{nodes}->@* ) {
            my $d = $g->{by}{ ( $self->_inputs($n) )[1] // '' };
            $d = $g->{by}{ ( $self->_inputs($d) )[0] // '' } while defined $d && $d->{op} eq 'Coerce';
            next if defined $d && $d->{op} eq 'Constant' && ( $self->_f( $d, 'value' ) // 0 ) =~ /\A-?(?:\d*\.)?\d+\z/ && $self->_f( $d, 'value' ) != 0;
            $self->_gap( "a " . ( $n->{op} eq 'Divide' ? 'division' : 'modulus' ) . " whose divisor may be zero, on no control chain: it would die at its value's first use, after what perl never ran (in $name)" )
                if $self->_effect_before_first_use( $g, $n );
        }
        return;
    }

    # _effect_before_first_use($g, $n) -> true where control passes an effect
    # between the pinned nodes $n is computed from and where its value is
    # first taken: a pinned node, or the end of an arm a merge takes it from.
    method _effect_before_first_use( $g, $n ) {
        # What it is computed from, pinned.
        my ( %from, %seen, @q );
        @q = $self->_inputs($n);
        while ( defined( my $id = shift @q ) ) {
            next if $seen{$id}++;
            my $x = $g->{by}{$id} // next;
            $from{$id} = 1 if $self->_pinned($x) || $STRUCTURE{ $x->{op} };
            push @q, $self->_inputs($x);
        }
        # In an eval (B::SoN marks it): made after the eval is entered.
        if ( defined( my $eval = $self->_f( $n, 'eval_id' ) ) ) {
            $from{ $self->_f( $_, 'eval_entry' ) // '' } = 1
                for grep { $_->{op} eq 'Region' && ( $self->_f( $_, 'eval_id' ) // '' ) eq $eval } $g->{nodes}->@*;
        }
        # Where its value is taken: %users the pinned nodes, @ends the arms' ends.
        my ( %users, %seen_c, @ends );
        @q = ( [ $n->{id}, -1 ] );
        while ( defined( my $at = shift @q ) ) {
            my ( $id, $via ) = $at->@*;
            next if $seen_c{$id}++;
            for my $use ( ( $g->{cons}{$id} // [] )->@* ) {
                my ( $c, $slot ) = $use->@*;
                if ( $c->{op} eq 'Phi' ) {
                    my $r = $g->{by}{ $self->_f( $c, 'region' ) // '' } // return 1;
                    # (round a loop: the body's end is not on the wire)
                    return 1 if $r->{op} eq 'Loop' && $slot != 0;
                    my @ways = ( $self->_f( $c, 'predecessors' ) // [ $self->_inputs($r) ] )->@*;
                    # (an eval's merge has one way in on the wire: its block's end)
                    my $end = $g->{by}{ $ways[ defined $self->_f( $r, 'eval_id' ) ? 0 : $slot ] // '' } // return 1;
                    push @ends, $end;
                }
                elsif ( $self->_pinned($c) || $STRUCTURE{ $c->{op} } ) { $users{ $c->{id} } = $c }
                else                                                   { push @q, [ $c->{id}, $slot ] }
            }
        }
        my ( %walked, @w );
        @w = ( @ends, map { $self->_preds( $g, $_ ) } values %users );
        while ( defined( my $x = shift @w ) ) {
            next if $walked{ $x->{id} }++ || $from{ $x->{id} } || $users{ $x->{id} };
            return 1 unless $STRUCTURE{ $x->{op} } || $PINNED_READ{ $x->{op} }
                || ( $self->_written_pkg( $g, $x ) // '' ) eq '$main::@';    # (an eval's entry clears $@: a die there sets it)
            push @w, $self->_preds( $g, $x );
        }
        return 0;
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

    # W4. `ref` and `blessed` name no memory version, so two either side of a
    # bless are one node, read once: refused where the program blesses what
    # may already have been seen (anything but a fresh hash or array only
    # the bless holds).
    method _class_reads_beside_a_rebless() {
        my @all = $self->_all_nodes;
        # (a read of what is itself read from memory -- `ref($o)` of a
        # variable kept there -- is no safer: the bless changes the object,
        # not the variable, and the read still floats)
        my ($read) = grep { $self->_is_class_read( $_->[1] ) } @all or return;
        for my $e ( grep { $self->_is_bless( $_->[1] ) } @all ) {
            my ( $name, $n ) = $e->@*;
            my $g = $self->_graph($name);
            my $x = $g->{by}{ ( $self->_inputs($n) )[0] // '' };
            next if defined $x && $x->{op} =~ /\A(?:HashLiteral|ArrayLiteral)\z/ && ( $g->{cons}{ $x->{id} } // [] )->@* == 1;
            $self->_gap("ref() or blessed() in a program that blesses a reference it may already have read: the read names no memory version, so it may be made on the wrong side of the bless (the bless in $name, a read in $read->[0])");
        }
        return;
    }

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
    # back: `sub t { local $g = 2; die } eval { t() }` left $g 2.
    method _locals_a_die_skips() {
        return unless $self->_has_eval;
        my %memo;
        my $any_uncaught = grep { $_->[1]{op} eq 'Unwind' && !defined $self->_f( $_->[1], 'eval_id' ) } $self->_all_nodes;
        my $may_die;
        $may_die = sub ($name) {
            return $memo{$name} if exists $memo{$name};
            $memo{$name} = 0;    # (a sub calling itself adds nothing)
            my $g = $self->_graph($name);
            for my $n ( grep { !defined $self->_f( $_, 'eval_id' ) } $g->{nodes}->@* ) {
                return $memo{$name} = 1 if $n->{op} eq 'Unwind';
                next unless $self->_is_sub_call($n);
                my $callee = $self->_f( $n, 'name' ) // '';
                my $direct = ( $self->_f( $n, 'dispatch_kind' ) // '' ) eq 'direct' && exists $methods->{$callee};
                return $memo{$name} = 1 if $direct ? $may_die->($callee) : $any_uncaught;
            }
            return 0;
        };
        for my $name ( sort keys $methods->%* ) {
            my $g = $self->_graph($name);
            my $local = grep {
                my @in = $self->_inputs($_);
                my $v  = $g->{by}{ $in[1] // '' };
                $_->{op} eq 'ElemRestore'
                    || $_->{op} eq 'EntryWrite' && ( $self->_f( $_, 'binds' )
                        || defined $v && $v->{op} eq 'EntryDef' && $self->_inputs($v)
                           && $self->_pkg_name($v) eq ( $self->_written_pkg( $g, $_ ) // '' )
                           # (a try or an eval puts $@ back itself; a die sets it anyway)
                           && $self->_pkg_name($v) ne '$main::@' )
            } $g->{nodes}->@*;
            $self->_gap("a `local` in a sub a die may leave, under an eval: the die's way out restores nothing (in $name)")
                if $local && $may_die->($name);
        }
        return;
    }

    # A store to a package variable in an eval block that dies: the wire is
    # the same for `local $v = 3` there (its restore, which the die skips, is
    # not written) and for `$v = 3`, so which it is cannot be told.
    method _stores_in_a_dying_eval($name) {
        my $g = $self->_graph($name);
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
                    if defined $var && $var ne '$main::@';
                push @q, $self->_preds( $g, $x );
            }
        }
        return;
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
        # W8. chalk frees nothing, so a DESTROY is never called.
        if ( my ($d) = grep { /::DESTROY\z/ } sort $defined->@*, keys $methods->%* ) {
            $self->_gap("a DESTROY method ($d): chalk never destroys an object, so it would never run");
        }
        for my $name ( sort keys $methods->%* ) {
            $self->_floating_effects($name);
            $self->_loop_carried_package_scalars($name);
            $self->_flattened_package_aggregates($name);
            $self->_autovivifying_reads($name);
            $self->_hashes_read_as_scalars($name);
            $self->_floating_divisions($name);
            $self->_unread_derefs($name);
            $self->_stores_in_a_dying_eval($name);
        }
        $self->_class_reads_beside_a_rebless;
        $self->_captured_arguments_written;
        $self->_locals_a_die_skips;
        $self->_dies_of_references;
        return;
    }
}

1;
