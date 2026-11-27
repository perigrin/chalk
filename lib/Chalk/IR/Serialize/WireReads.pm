# ABOUTME: L12-L14 of the wire invariant: a record binds `my` variables only, every read of changeable
# ABOUTME: state names a version, an effect runs on the control chain (SoN::Verify's V7, V6, V2b, ported).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Grammar::Perl::BuiltinTable;

# WHY THE LOADER HOLDS THEM (fifth final audit, section 3). 17 of the
# audit's 2576 wires broke a rule of SoN::Verify (B::SoN's lib/SoN/Verify.pm)
# and chalk loaded all but the one L11 holds: ten printed a wrong answer.
# `vf217`, `vq111`-`vq116` read a package `$t` for `substr($t,0,1)` at no
# version, so it was read before the call that stores it; `vo41`-`vo43` were
# a record (a binding, on no chain) of package scalars, whose stores then
# were never made. The loader held only L1-L11, the structural half of the
# memory invariant; these are the half that asks what a node reads. Each is
# a port of the verifier's rule, held to give its answers
# (t/bootstrap/ir/loader-refuses-what-the-verifier-rejects.t, and over every
# probe and chalk module, t/bootstrap/ir/wire-verify.t).
#
#   L12 (V7)  a record Assign is a binding: on no chain, and its targets are
#             SSA `my` scalars, or `my` aggregates bound from @_.
#   L13 (V6)  a read of changeable state -- a package variable, a field, a
#             cell, through a reference, @_, a `my` aggregate something
#             writes, a `my` scalar kept in memory, an object's class, a
#             builtin's state -- names a version (mem_in), unless every use of
#             it that runs is a place use (a store's target, a sub call's
#             argument, a container ...).
#   L14 (V2b) an effect runs where it stands: a Print, an Unwind, a Return,
#             a sub call, a builtin that writes, reads ordered state or is not
#             known, a division that may fault -- each has a control_in.
#
# WHAT A BUILTIN DOES is BuiltinTable's effect_* columns (B::SoN's EffectTable).
#
#   Chalk::IR::Serialize::WireReads->new->check($name, $graph);
#
# check() returns nothing, or dies "GAP: wire invariant Ln: GRAPH: ...\n".
class Chalk::IR::Serialize::WireReads {
    my sub _f($n) { return $n->{fields} // {} }
    my sub fact( $name, $col ) { return Chalk::Grammar::Perl::BuiltinTable::fact( $name, $col ) }

    # (EffectTable's known, writes, on_chain, is_version, over BuiltinTable's columns)
    my sub known($name) {
        return ( grep { fact( $name, $_ ) } qw(effect_writes effect_version effect_faults effect_reads effect_pure effect_own_handler effect_elsewhere) ) ? 1 : 0;
    }
    my sub writes($name) {
        return 1 if fact( $name, 'effect_own_handler' ) || !known($name);
        return fact( $name, 'effect_writes' ) ? 1 : 0;
    }
    my %ORDERED_READ = map { ( $_ => 1 ) } qw(handle stack variable clock);
    my sub on_chain($name) {
        return 1 if fact( $name, 'effect_writes' ) || fact( $name, 'effect_faults' );
        return $ORDERED_READ{ fact( $name, 'effect_reads' ) // '' } ? 1 : 0;
    }
    my sub is_version($name) { return fact( $name, 'effect_own_version' ) || fact( $name, 'effect_version' ) ? 1 : 0 }

    # (a Divide or Modulo whose divisor is not a constant known not to be zero)
    my sub may_fault( $n, $by ) {
        my $d = $by->{ ( $n->{inputs} // [] )->[1] // '' } or return 1;
        $d = $by->{ $d->{inputs}[0] // '' } // return 1 while $d->{op} eq 'Coerce';
        return 1 unless $d->{op} eq 'Constant' && ( _f($d)->{const_type} // '' ) =~ /\A(?:integer|number)\z/;
        my $v = _f($d)->{value} // 0;
        return ( $n->{op} eq 'Modulo' ? int($v) : $v ) == 0 ? 1 : 0;
    }

    # (what kind of place an Assign target is: ssa-scalar and skip are a record's)
    my sub target_class($t) {
        return 'skip' unless $t;
        my ( $op, $f ) = ( $t->{op}, _f($t) );
        return 'element' if $op eq 'Subscript';
        return 'slice'   if $op eq 'Slice';
        if ( $op eq 'PadAccess' ) {
            return 'my-aggregate' if ( $f->{sigil} // '$' ) ne '$';
            return 'my-scalar-in-memory' if ( $t->{inputs} // [] )->@* || $f->{shared} || defined $t->{mem_in};
            return 'ssa-scalar';
        }
        return 'package-var'     if $op eq 'EntryDef';
        return 'through-ref'     if $op eq 'PostfixDeref';
        return 'field'           if $op eq 'FieldAccess';
        return 'capture-cell'    if $op =~ /\A(?:MakeCell|CellRead|CellParam)\z/;
        return 'named-aggregate' if $op =~ /\A(?:ArrayLiteral|HashLiteral)\z/;
        return 'skip'            if $op eq 'Constant';
        return "other:$op";
    }

    # (a read, for a refusal: what it reads, as far as the wire names it)
    my sub describe( $n, $by ) {
        my $f = _f($n);
        my $s = $n->{op};
        $s .= " $f->{name}" if $n->{op} eq 'Call';
        $s .= ' ' . ( $f->{sigil} // '' ) . $f->{symbol} if defined $f->{symbol};
        my $c = $by->{ ( $n->{op} eq 'Slice' ? $n->{inputs}[-1] : $n->{inputs}[0] ) // '' };
        $s .= ' of ' . $c->{op} . ( defined _f($c)->{symbol} ? ' ' . ( _f($c)->{sigil} // '' ) . _f($c)->{symbol} : '' )
            if $c && $n->{op} ne 'Call';
        return $s;
    }

    method check( $name, $g ) {
        my $ns    = $g->{nodes} // [];
        my @nodes = sort { $a->{id} <=> $b->{id} } ref $ns eq 'HASH' ? values $ns->%* : $ns->@*;
        my %by    = map { ( $_->{id} => $_ ) } @nodes;
        my $gap   = sub ( $rule, $n, $why ) { die "GAP: wire invariant $rule: $name: $n->{op}#$n->{id} $why\n" };
        my %cons;
        for my $n (@nodes) {
            my $in = $n->{inputs} // [];
            for my $i ( 0 .. $#$in ) {
                push $cons{$_}->@*, [ $n, $i ] for grep { defined } ref $in->[$i] ? $in->[$i]->@* : $in->[$i];
            }
        }
        my $record   = sub ($n) { $n->{op} eq 'Assign' && _f($n)->{record} };
        my $targets  = sub ($n) { ( $n->{inputs} // [] )->@[ 0 .. ( _f($n)->{targets} // 1 ) - 1 ] };
        my $sub_call = sub ( $op, $f ) { $op eq 'Call' && ( $f->{dispatch_kind} // '' ) ne 'builtin' };

        # L12 (V7): A RECORD IS A BINDING, on no chain, of `my` variables.
        for my $n ( grep { $record->($_) } @nodes ) {
            $gap->( 'L12', $n, 'is a record (a binding) on a chain' ) if grep { defined $n->{$_} } qw(control_in mem_in mem_out);
            my %c   = map { ( target_class( $by{ $_ // '' } ) => 1 ) } $targets->($n);
            my @mem = grep { $_ ne 'ssa-scalar' && $_ ne 'skip' } sort keys %c;
            my $args = ( ( $by{ ( $n->{inputs} // [] )->[-1] // '' } // {} )->{op} // '' ) eq 'ArgsSource';
            next if !@mem || $args && "@mem" eq 'my-aggregate';
            $gap->( 'L12', $n, 'is a record (a binding, no store) of ' . join( '+', @mem ) . ': its stores would never be made' );
        }

        # L14 (V2b): AN EFFECT RUNS WHERE IT STANDS. (A place -- an Assign's
        # target -- is not run, but a sub call there is; nor is a division
        # whose value only an arm's merge takes: it runs in that arm.)
        my $place = sub ($n) { grep { $_->[0]{op} eq 'Assign' && $_->[1] < ( _f( $_->[0] )->{targets} // 1 ) } ( $cons{ $n->{id} } // [] )->@* };
        my $in_arm;
        $in_arm = sub ( $n, $d = 0 ) {
            $d < 8 && grep { $_->[0]{op} eq 'Phi' || $_->[0]{op} =~ /\A(?:TernaryExpr|And|Or|DefinedOr)\z/ && $_->[1] > 0
                             || $_->[0]{op} eq 'Coerce' && $in_arm->( $_->[0], $d + 1 ) } ( $cons{ $n->{id} } // [] )->@*;
        };
        for my $n ( grep { !defined $_->{control_in} } @nodes ) {
            my ( $op, $f ) = ( $n->{op}, _f($n) );
            next if $place->($n) && !$sub_call->( $op, $f );
            next if $op =~ /\A(?:Divide|Modulo)\z/ && $in_arm->($n);
            my $why = $op =~ /\A(?:Print|Unwind|Return)\z/ ? $op
                : $sub_call->( $op, $f ) ? 'a call of ' . ( $f->{name} // 'a sub' )
                : $op eq 'Call' && ( $f->{dispatch_kind} // '' ) eq 'builtin'
                    && ( on_chain( $f->{name} ) || is_version( $f->{name} ) || !known( $f->{name} ) ) ? "the builtin $f->{name}"
                : $op =~ /\A(?:Divide|Modulo)\z/ && may_fault( $n, \%by ) ? "a $op that may fault"
                : undef;
            $gap->( 'L14', $n, "is an effect ($why) on no control chain: it would run where its value is first used, or never" ) if defined $why;
        }

        # L13 (V6): READS NAME A VERSION, unless every use is a place use.
        # The `my` scalars kept in memory: some read of them names a version,
        # and no record binds the name.
        my %bound = map { ( '$' . ( _f( $by{$_} // {} )->{symbol} // '' ) => 1 ) } grep { defined && !ref } map { $targets->($_) } grep { $record->($_) } @nodes;
        my %in_memory = map { ( '$' . _f($_)->{symbol} => 1 ) }
            grep { $_->{op} eq 'PadAccess' && ( _f($_)->{sigil} // '$' ) eq '$' && defined $_->{mem_in} && defined _f($_)->{symbol} && !$bound{ '$' . _f($_)->{symbol} } } @nodes;
        my $name_of = sub ($n) {
            return undef unless $n && $n->{op} =~ /\A(?:PadAccess|ArrayLiteral|HashLiteral)\z/;
            my $f = _f($n);
            return defined $f->{symbol} ? ( $f->{sigil} // '' ) . $f->{symbol} : undef;
        };
        my $container = sub ($n) { $by{ ( $n->{op} eq 'Slice' ? $n->{inputs}[-1] : $n->{inputs}[0] ) // '' } };
        # WHAT IS USED: a value that reaches something that runs (a record is
        # used where its target is: `my ($p) = @_` and a read of $p).
        my %live;
        {
            my %record_of;
            for my $r ( grep { $record->($_) } @nodes ) {
                push $record_of{$_}->@*, $r->{id} for grep { defined && !ref } $targets->($r);
            }
            my @q = map { $_->{id} } grep { defined $_->{control_in} || $_->{op} =~ /\A(?:Start|Return|Unwind|Region|If|Loop|Proj)\z/ } @nodes;
            while ( defined( my $id = shift @q ) ) {
                next if $live{$id}++;
                push @q, ( $record_of{$id} // [] )->@*;
                my $x = $by{$id} or next;
                push @q, grep { defined && !ref } ( $x->{inputs} // [] )->@*;
                push @q, map { ref $_ ? @$_ : () } ( $x->{inputs} // [] )->@*;
                push @q, grep { defined } $x->{mem_in}, $x->{control_in}, _f($x)->{region};
            }
        }
        # (an alias list -- a foreach, map or grep's list, a merge of an
        # aggregate's bindings -- used only as a container: its items are places)
        my ( %alias_list, $is_place_use );
        $is_place_use = sub ( $c, $i ) {
            my ( $op, $f ) = ( $c->{op}, _f($c) );
            if ( $op eq 'ArrayLiteral' && !defined $f->{symbol} || $op eq 'Phi' && !$f->{memory} || $op eq 'TernaryExpr' && $i > 0 ) {
                return $alias_list{ $c->{id} } if exists $alias_list{ $c->{id} };
                $alias_list{ $c->{id} } = 0;
                my @u = grep { $live{ $_->[0]{id} } } ( $cons{ $c->{id} } // [] )->@*;
                return $alias_list{ $c->{id} } = ( @u && !grep { !$is_place_use->(@$_) } @u ) ? 1 : 0;
            }
            return $i < ( $f->{targets} // 1 ) if $op eq 'Assign';
            return 1 if $op =~ /\A(?:Loop|Region|Proj)\z/ || $op eq 'If' && $i == 0;
            return $i == $#{ $c->{inputs} } if $op eq 'Slice';
            return 1 if $op eq 'Call' && ( ( $f->{dispatch_kind} // '' ) ne 'builtin' || defined $c->{mem_in} );
            # (pos() names the variable whose position it is, not its value)
            return 1 if $op eq 'Call' && ( fact( $f->{name}, 'effect_reads' ) // '' ) eq 'variable';
            return 1 if $op =~ /\A(?:AnonSub|RegexSubst|Transliterate|Chomp)\z/;
            return $i == 0
                if $op =~ /\A(?:Subscript|Exists|Delete|Count|PostfixDeref|ElemRestore|Ref|LocalAlias|VarDecl|MakeCell|CellRead|EntryWrite|CellWrite)\z/;
            return 0;
        };
        my %mutated;
        for my $n ( grep { !$record->($_) } @nodes ) {
            my ( $op, $f, $in ) = ( $n->{op}, _f($n), $n->{inputs} // [] );
            my @written =
                  $op eq 'Assign' ? $targets->($n)
                : $op eq 'Call' ? ( ( $f->{dispatch_kind} // '' ) ne 'builtin' || writes( $f->{name} ) ? @$in : () )
                : $op =~ /\A(?:Ref|LocalAlias|Delete|ElemRestore|MakeCell|EntryWrite|CellWrite|Chomp)\z/ ? ( $in->[0] )
                : $op =~ /\A(?:AnonSub|RegexSubst|Transliterate)\z/ ? @$in
                :                                                   ();
            for my $t ( map { $by{$_} } grep { defined && !ref } @written ) {
                $t = $container->($t) while $t && $t->{op} =~ /\A(?:Subscript|Slice)\z/;
                my $k = $name_of->($t);
                $mutated{$k} = 1 if defined $k;
            }
        }
        # (a graph that stores into an element of @_ changes what @_ holds
        # after a copy of it: there a record of @_ has no version to be made at)
        my $stores_beyond_own = grep {
            my ( $op, $f, $in ) = ( $_->{op}, _f($_), $_->{inputs} // [] );
            $_->{mem_out} && !$record->($_) && grep {
                my ( $t, $elem ) = ( $by{$_}, 0 );
                ( $t, $elem ) = ( $container->($t), 1 ) while $t && $t->{op} =~ /\A(?:Subscript|Slice)\z/;
                $elem && $t && $t->{op} eq 'ArgsSource'
            } grep { defined && !ref } ( $op eq 'Assign' ? $targets->($_) : $op eq 'Call' ? @$in : () );
        } @nodes;
        my $place_class;
        $place_class = sub ($n) {
            return undef unless $n;
            my ( $op, $f ) = ( $n->{op}, _f($n) );
            return 'package'     if $op eq 'EntryDef';
            return 'field'       if $op eq 'FieldAccess';
            return 'cell'        if $op =~ /\A(?:CellRead|CellParam|MakeCell)\z/;
            return 'through-ref' if $op eq 'PostfixDeref';
            return 'args'        if $op eq 'ArgsSource';
            if ( $op eq 'PadAccess' && ( $f->{sigil} // '$' ) eq '$' ) {
                return 'my-shared' if $f->{shared};
                return $in_memory{ '$' . ( $f->{symbol} // '' ) } ? 'my-in-memory' : undef;
            }
            if ( defined( my $k = $name_of->($n) ) ) {
                return 'package' if $op ne 'PadAccess' && $f->{symbol} =~ /::/;
                return $mutated{$k} ? 'my-aggregate' : undef;
            }
            return undef if $op =~ /\A(?:ArrayLiteral|HashLiteral|Constant|Range)\z/;
            if ( $op =~ /\A(?:Subscript|Slice|Count)\z/ ) {
                my $c = $container->($n) or return undef;
                return 'through-ref' if $c->{op} =~ /\A(?:Subscript|Slice)\z/;
                return 'through-ref' if $c->{op} eq 'PadAccess' && ( _f($c)->{sigil} // '$' ) eq '$';
                return $place_class->($c);
            }
            return ( $n->{stamp} // '' ) =~ /\A(?:Array|List|Hash)\z/ ? undef : 'through-ref';
        };
        for my $n ( grep { !defined $_->{mem_in} && !_f($_)->{place} } @nodes ) {
            my ( $op, $f ) = ( $n->{op}, _f($n) );
            # (a list slice, `(f())[0]`, picks from values)
            next if $op eq 'Slice' && defined $f->{index_count};
            my $class;
            if    ( $op =~ /\A(?:Subscript|Slice|Count|PostfixDeref|CellRead|EntryDef|PadAccess|FieldAccess)\z/ ) { $class = $place_class->($n) }
            elsif ( $op eq 'RefType' ) { $class = 'object-class' }
            elsif ( $op eq 'ArgsSource' ) {
                $class = 'args' if $stores_beyond_own && grep { $live{ $_->[0]{id} } && $record->( $_->[0] ) } ( $cons{ $n->{id} } // [] )->@*;
            }
            elsif ( $op eq 'Call' && ( $f->{dispatch_kind} // '' ) eq 'builtin' ) { $class = fact( $f->{name}, 'effect_reads' ) }
            # (a package scalar in an alias list is read where the list is made)
            my $scalar_entry = $op eq 'EntryDef' && ( $f->{sigil} // '' ) eq '$';
            next unless $class && grep {
                $live{ $_->[0]{id} } && ( !$is_place_use->(@$_)
                    || $scalar_entry && $_->[0]{op} =~ /\A(?:ArrayLiteral|Phi|TernaryExpr)\z/ )
            } ( $cons{ $n->{id} } // [] )->@*;
            # (a list assign's target is what later reads are: its value is that Assign's, a version)
            next if $class eq 'my-in-memory' && grep { $_->[0]{op} eq 'Assign' && $_->[1] < ( _f( $_->[0] )->{targets} // 1 ) && $_->[0]{mem_out} } ( $cons{ $n->{id} } // [] )->@*;
            $gap->( 'L13', $n, "reads changeable state ($class: " . describe( $n, \%by ) . ') at no memory version: when it is read is not said' );
        }
        for my $n ( grep { $_->{op} =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && ( _f($_)->{symbol} // '' ) =~ /::/ } @nodes ) {
            my @uses = grep { $live{ $_->[0]{id} } && !( $_->[0]{op} eq 'EntryWrite' && $_->[1] == 1 ) && !$is_place_use->(@$_) } ( $cons{ $n->{id} } // [] )->@*;
            $gap->( 'L13', $n, 'reads changeable state (package-aggregate-literal: ' . _f($n)->{symbol} . ' read by '
                . join( ',', map { "$_->[0]{op}#$_->[0]{id}" } @uses ) . ') at no memory version: when it is read is not said' ) if @uses;
        }
        return;
    }
}

1;
