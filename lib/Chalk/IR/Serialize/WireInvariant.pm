# ABOUTME: The memory invariant of a wire v2 (the plan's L1-L6), checked on the raw wire before
# ABOUTME: any graph is made: every edge names a version, every version is reached from the end.
use 5.42.0;
use utf8;
use experimental 'class';

# WIRE V2, STAGE 5 (docs/plans/2026-11-20-wire-v2.md, section 8.3). Wire v2
# names its memory edges; chalk reads them as they come. Structural only: no
# kind table beyond the ops it names. A v1 wire is upgraded (WireUpgrade) and
# not held to it: what v1 left to inference is decided there.
#
#   L1  every mem_in names MemStart, a memory Phi, or a node with mem_out
#   L2  a node with mem_out has mem_in and control_in
#   L3  every Return and Unwind has mem_in
#   L4  every node with mem_out is reached backwards (over mem_in and memory
#       Phi inputs) from the roots: each Return's and Unwind's mem_in, and the
#       memory Phi of a Loop no exit Region names (SoN::Verify's V3, V4)
#   L5  an Assign is a record, or has control_in, mem_in and mem_out; a sub
#       Call has all three
#   L6  a Phi has as many inputs as its Region has ways in (a Loop: two); a
#       memory Phi's inputs are versions
#
#   Chalk::IR::Serialize::WireInvariant->new( profile => ['mem'] )->check($name, $graph);
#
# check() returns nothing, or dies "GAP: wire invariant Ln: GRAPH: ...\n".
class Chalk::IR::Serialize::WireInvariant {
    field $profile :param = ['mem'];

    my %SUB_CALL = map { $_ => 1 } qw(direct method dynamic_method indirect);

    # check($name, $graph): the graph $name of a v2 wire ({ nodes => [...] }).
    method check( $name, $g ) {
        return unless grep { $_ eq 'mem' } $profile->@*;
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
        for my $n (@nodes) {
            my $f = $n->{fields} // {};
            my $sub_call = $n->{op} eq 'Call' && $SUB_CALL{ $f->{dispatch_kind} // '' };
            next unless $n->{op} eq 'Assign' && !$f->{record} || $sub_call;
            my @lack = grep { !( $_ eq 'mem_out' ? $n->{mem_out} : defined $n->{$_} ) } qw(control_in mem_in mem_out);
            $gap->( 'L5', $n, ( $sub_call ? 'is a sub call' : 'is no record' ) . ' with no ' . join( ' or ', @lack ) ) if @lack;
        }
        for my $n ( grep { $_->{op} eq 'Phi' } @nodes ) {
            my $f = $n->{fields} // {};
            my $r = $by{ $f->{region} // '' };
            $gap->( 'L6', $n, 'has no Region or Loop (region ' . $say->( $f->{region} ) . ')' )
                unless $r && $r->{op} =~ /\A(?:Region|Loop)\z/;
            my $want = $r->{op} eq 'Loop' ? 2 : scalar grep { defined } ( $r->{inputs} // [] )->@*;
            my $have = scalar( ( $n->{inputs} // [] )->@* );
            # (AN EVAL'S JOIN: its value Phi has one input more than its
            # Region has ways in -- the exceptional edge it lacks is stage 8's)
            $gap->( 'L6', $n, "has $have inputs for $want ways into $r->{op}#$r->{id}" )
                if $have != $want && !( defined( ( $r->{fields} // {} )->{eval_id} ) && !$f->{memory} );
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
