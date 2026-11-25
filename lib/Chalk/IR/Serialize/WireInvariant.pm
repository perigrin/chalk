# ABOUTME: The memory invariant of a wire v2 (the plan's L1-L8), checked on the raw wire before
# ABOUTME: any graph is made: every edge names a version, every version is reached from the end.
use 5.42.0;
use utf8;
use experimental 'class';

# WIRE V2, STAGE 5 (docs/plans/2026-11-20-wire-v2.md, section 8.3). Wire v2
# names its memory edges; chalk reads them as they come. Structural only: no
# kind table beyond the ops it names. (Wire v1, which named no memory edge,
# is gone: stage 6.)
#
#   L1  every mem_in names MemStart, a memory Phi, or a node with mem_out
#   L2  a node with mem_out has mem_in and control_in
#   L3  every Return and Unwind has mem_in
#   L4  every node with mem_out is reached backwards (over mem_in and memory
#       Phi inputs) from the roots: each Return's and Unwind's mem_in, and the
#       memory Phi of a Loop no exit Region names (SoN::Verify's V3, V4)
#   L5  an Assign is a record, or is on both chains: control_in, mem_in,
#       mem_out (hard since stage 6). A sub Call has all three too, an
#       :lvalue call an Assign stores through as well: it runs where it
#       stands (audit 3: off the chains, corpus 398's ran nowhere). And
#       every kind that
#       stores whenever it runs -- EntryWrite, CellWrite, Delete,
#       ElemRestore, MakeCell -- is a version on both chains (stage 10).
#   L6  a Phi has as many inputs as its Region has ways in (a Loop: its
#       own inputs); a memory Phi's inputs are versions. (An eval's join
#       too, since stage 8: its catch is a way in like the body's end.)
#   L7  every way into a catch Region leads back, by control_in, to an
#       Exc: the exceptional edges of what died, and only they, merge there.
#       An Exc outside an eval ends in an Unwind marked rethrow whose input
#       it is (design B1), and a rethrow is of its own edge's Exc. (Whether
#       what may die stands under a live `local` the wire cannot say -- a
#       value saved and put back by hand is the same shape -- so that every
#       such point HAS an edge is B::SoN's to make and SoN::Verify's V10 to
#       check.)
#   L8  a Loop has one or two inputs (the way in, and the way round where a
#       path goes round); the only forward references in a graph are a loop
#       Phi's back input and a Loop's inputs[1]. A Loop's Phis have as many
#       inputs as it (L6).
#   L9  inputs hold values only: MemStart and a memory Phi, which are
#       versions and no value, are named by mem_in and memory Phis alone
#       (stage 10).
#   L10 a place (fields.place, aliases-as-places) is storage: on no chain
#       (no mem_in, control_in, mem_out), of an access kind (PadAccess,
#       EntryDef, Subscript, FieldAccess, CellRead), used only where perl
#       binds an alias -- a sub call's input, or an item of an alias list
#       (an ArrayLiteral of no symbol). `vivify` is a Subscript place's.
#       (That an alias carried as a value is private is SoN::Verify's V12.)
#
# WHAT IT DOES NOT CHECK: that every read names a version. Telling a read
# from a place takes its uses and the effect table; that is SoN::Verify's V6,
# the one implementation (the plan's 8.2), run over chalk's lib and the
# probes by t/bootstrap/ir/wire-verify.t.
#
# Every rule holds on every wire: the parts of v2 a wire once listed in its
# `profile` (mem; eval: L7; loop: L8) are all of v2 since stage 10.
#
#   Chalk::IR::Serialize::WireInvariant->new->check($name, $graph);
#
# check() returns nothing, or dies "GAP: wire invariant Ln: GRAPH: ...\n".
class Chalk::IR::Serialize::WireInvariant {
    my %SUB_CALL = map { $_ => 1 } qw(direct method dynamic_method indirect);
    my %STORE    = map { $_ => 1 } qw(EntryWrite CellWrite Delete ElemRestore MakeCell);

    # _rethrow_edges(\@nodes, \%by, $gap): L7's part outside an eval (design B1).
    method _rethrow_edges( $nodes, $by, $gap ) {
        my $f   = sub ( $x, $k ) { ( $x->{fields} // {} )->{$k} };
        my %succ;
        push $succ{ $_->{control_in} }->@*, $_ for grep { defined $_->{control_in} } @$nodes;
        # (the nodes on an Exc's edge, in order, to where it ends)
        my $edge = sub ($x) {
            my ( @c, %seen );
            for ( my @s = ( $succ{ $x->{id} } // [] )->@*; @s == 1 && !$seen{ $s[0]{id} }++; @s = ( $succ{ $s[0]{id} } // [] )->@* ) { push @c, $s[0] }
            return @c;
        };
        my @exc = grep { $_->{op} eq 'Exc' } @$nodes;
        # (an Exc is an eval's by where its edge goes, into a catch: a die in a
        # sort block inlined in an eval carries no eval_id)
        my %into_catch = map { ( $_ => 1 ) } grep { defined && !ref } map { ( $_->{inputs} // [] )->@* }
            grep { $_->{op} eq 'Region' && $f->( $_, 'catch' ) } @$nodes;
        my $to_catch = sub ($x) { my @c = $edge->($x); $into_catch{ @c ? $c[-1]{id} : $x->{id} } };
        for my $u ( grep { $_->{op} eq 'Unwind' && $f->( $_, 'rethrow' ) } @$nodes ) {
            my $x = $by->{ $u->{inputs}[0] // '' };
            $gap->( 'L7', $u, 'is a rethrow not of its own edge\'s Exc' )
                unless $x && $x->{op} eq 'Exc' && grep { $_ == $u } $edge->($x);
        }
        for my $x ( grep { !$to_catch->($_) } @exc ) {
            my @c = $edge->($x);
            $gap->( 'L7', $x, 'is outside an eval and its way out ends in no rethrow' )
                unless @c && $c[-1]{op} eq 'Unwind' && $f->( $c[-1], 'rethrow' ) && ( $c[-1]{inputs}[0] // -1 ) == $x->{id};
        }
        return;
    }

    # check($name, $graph): the graph $name of a v2 wire ({ nodes => [...] }).
    method check( $name, $g ) {
        my $ns    = $g->{nodes} // [];
        my @nodes = sort { $a->{id} <=> $b->{id} } ref $ns eq 'HASH' ? values $ns->%* : $ns->@*;
        my %by    = map { ( $_->{id} => $_ ) } @nodes;
        my $gap   = sub ( $rule, $n, $why ) { die "GAP: wire invariant $rule: $name: $n->{op}#$n->{id} $why\n" };
        my $say   = sub ($id) { my $x = $by{ $id // '' }; $x ? "$x->{op}#$id" : 'nothing' };
        my $memphi  = sub ($x) { $x && $x->{op} eq 'Phi' && ( $x->{fields} // {} )->{memory} };
        my $version = sub ($id) {
            my $x = $by{ $id // '' } or return 0;
            return $x->{op} eq 'MemStart' || $memphi->($x) || $x->{mem_out};
        };

        for my $n (@nodes) {
            $gap->( 'L1', $n, 'has mem_in ' . $say->( $n->{mem_in} ) . ', which is no memory version' )
                if defined $n->{mem_in} && !$version->( $n->{mem_in} );
        }
        for my $n ( grep { $_->{mem_out} } @nodes ) {
            $gap->( 'L2', $n, 'is a memory version with no ' . join( ' or ', grep { !defined $n->{$_} } qw(mem_in control_in) ) )
                if !defined $n->{mem_in} || !defined $n->{control_in};
        }
        for my $n ( grep { $_->{op} eq 'Return' || $_->{op} eq 'Unwind' } @nodes ) {
            $gap->( 'L3', $n, 'names no memory (mem_in)' ) unless defined $n->{mem_in};
        }
        for my $c ( grep { $_->{op} eq 'Region' && ( $_->{fields} // {} )->{catch} } @nodes ) {
            for my $in ( grep { defined } ( $c->{inputs} // [] )->@* ) {
                my ( $x, %seen ) = ( $by{$in} );
                $x = $by{ $x->{control_in} // '' } while $x && $x->{op} ne 'Exc' && defined $x->{control_in} && !$seen{ $x->{id} }++;
                $gap->( 'L7', $c, 'has a way in (' . $say->($in) . ') no Exc leads to' ) unless $x && $x->{op} eq 'Exc';
            }
        }
        $self->_rethrow_edges( \@nodes, \%by, $gap );
        for my $n (@nodes) {
            my $in = $n->{inputs} // [];
            $gap->( 'L8', $n, 'has ' . scalar(@$in) . ' inputs (a Loop has one or two)' )
                if $n->{op} eq 'Loop' && ( @$in < 1 || @$in > 2 );
            my $back = $n->{op} eq 'Loop' || $n->{op} eq 'Phi' && ( ( $by{ ( $n->{fields} // {} )->{region} // '' } // {} )->{op} // '' ) eq 'Loop';
            for my $i ( 0 .. $#$in ) {
                next if $back && $i == 1;
                $gap->( 'L8', $n, "names $_, made after it" ) for grep { $_ >= $n->{id} } grep { defined && !ref } $in->[$i];
            }
            $gap->( 'L8', $n, "follows $_ (mem_in or control_in), made after it" )
                for grep { defined && $_ >= $n->{id} } $n->{mem_in}, $n->{control_in};
        }
        my %uses;    # id -> [ [user, input index] ... ]
        for my $u (@nodes) {
            my $in = $u->{inputs} // [];
            push $uses{ $in->[$_] }->@*, [ $u, $_ ] for grep { defined $in->[$_] && !ref $in->[$_] } 0 .. $#$in;
        }
        for my $n ( grep { $STORE{ $_->{op} } } @nodes ) {
            $gap->( 'L5', $n, 'is a store and no memory version (mem_out)' ) unless $n->{mem_out};
        }
        for my $n ( grep { ( $_->{fields} // {} )->{place} || ( $_->{fields} // {} )->{vivify} } @nodes ) {
            my $f = $n->{fields};
            $gap->( 'L10', $n, 'is a place of no access kind' ) unless $n->{op} =~ /\A(?:PadAccess|EntryDef|Subscript|FieldAccess|CellRead)\z/;
            $gap->( 'L10', $n, 'vivifies and is no element place' ) if $f->{vivify} && !( $f->{place} && $n->{op} eq 'Subscript' );
            $gap->( 'L10', $n, "is a place with $_" ) for grep { defined $n->{$_} } qw(mem_in control_in mem_out);
            for my $u ( ( $uses{ $n->{id} } // [] )->@* ) {
                my ( $x, $xf ) = ( $u->[0], $u->[0]{fields} // {} );
                $gap->( 'L10', $n, "is a place $x->{op}#$x->{id} uses, where perl binds no alias" )
                    unless $x->{op} eq 'Call' && $SUB_CALL{ $xf->{dispatch_kind} // '' }
                        || $x->{op} eq 'ArrayLiteral' && !defined $xf->{symbol};
            }
        }
        for my $n ( grep { !$memphi->($_) } @nodes ) {
            for my $in ( grep { defined && !ref } ( $n->{inputs} // [] )->@* ) {
                my $x = $by{$in} or next;
                $gap->( 'L9', $n, "names $x->{op}#$in as a value (an input): it is a memory version, no value" )
                    if $x->{op} eq 'MemStart' || $memphi->($x);
            }
        }
        for my $n (@nodes) {
            my $f = $n->{fields} // {};
            my $sub_call = $n->{op} eq 'Call' && $SUB_CALL{ $f->{dispatch_kind} // '' };
            next unless $n->{op} eq 'Assign' && !$f->{record} || $sub_call;
            my $what = $sub_call ? 'is a sub call' : 'is no record';
            $gap->( 'L5', $n, "$what that names no memory (mem_in)" ) unless defined $n->{mem_in};
            $gap->( 'L5', $n, "$what and on no control chain (control_in)" ) unless defined $n->{control_in};
            $gap->( 'L5', $n, "$what and no memory version (mem_out)" ) unless $n->{mem_out};
        }
        for my $n ( grep { $_->{op} eq 'Phi' } @nodes ) {
            my $f = $n->{fields} // {};
            my $r = $by{ $f->{region} // '' };
            $gap->( 'L6', $n, 'has no Region or Loop (region ' . $say->( $f->{region} ) . ')' )
                unless $r && $r->{op} =~ /\A(?:Region|Loop)\z/;
            my $want = $r->{op} eq 'Loop' ? scalar( ( $r->{inputs} // [] )->@* ) : scalar grep { defined } ( $r->{inputs} // [] )->@*;
            my $have = scalar( ( $n->{inputs} // [] )->@* );
            $gap->( 'L6', $n, "has $have inputs for $want ways into $r->{op}#$r->{id}" )
                if $have != $want;
            if ( $f->{memory} ) {
                $gap->( 'L6', $n, 'is a memory Phi with input ' . $say->($_) . ', which is no memory version' )
                    for grep { !$version->($_) } grep { defined } ( $n->{inputs} // [] )->@*;
            }
        }

        # L4: backwards from the roots, over mem_in and memory Phi inputs.
        my @roots = map { $_->{mem_in} } grep { $_->{op} eq 'Return' || $_->{op} eq 'Unwind' } @nodes;
        my %exit_head = map { ( $_->{head} // -1 ) => 1 } grep { $_->{op} eq 'Region' } @nodes;
        for my $loop ( grep { $_->{op} eq 'Loop' && !$exit_head{ $_->{id} } } @nodes ) {
            push @roots, map { $_->{id} } grep { $memphi->($_) && ( ( $_->{fields} // {} )->{region} // -1 ) == $loop->{id} } @nodes;
        }
        my %seen;
        my @q = grep { defined } @roots;
        while ( defined( my $id = shift @q ) ) {
            next if $seen{$id}++;
            my $x = $by{$id} or next;
            push @q, $x->{mem_in} if defined $x->{mem_in};
            push @q, grep { defined } ( $x->{inputs} // [] )->@* if $memphi->($x);
        }
        for my $n ( grep { $_->{mem_out} && !$seen{ $_->{id} } } @nodes ) {
            $gap->( 'L4', $n, 'is a memory version no Return or Unwind reaches backwards' );
        }
        return;
    }
}

1;
