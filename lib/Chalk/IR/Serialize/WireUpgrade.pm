# ABOUTME: Rewrites a decoded v1 B::SoN wire, in place, into wire v2's `mem` shape: memory
# ABOUTME: named by mem_in / mem_out instead of a trailing input, Phis and records flagged.
use 5.42.0;
use utf8;
use experimental 'class';

# WIRE V2, STAGE 2 (docs/plans/2026-11-20-wire-v2.md, sections 3.2-3.4 and 7).
# chalk's graph takes the v2 shape before the producer writes it, so the loader
# has ONE reader: a v1 wire is upgraded here first. What v1 left to inference,
# this decides once, from the wire, the way chalk's node classes decided it on
# every question until now:
#
#   - a read's memory version stops being its last input and is its `mem_in`
#     (%MEMORY_SLOT: the producer's positional table, which chalk's classes
#     each restated as a `memory_operand`);
#   - a pinned node chalk took for a memory version says so, `mem_out`;
#   - each pinned version with no memory input of its own, each sub call,
#     Return and Unwind names the version before it on its control chain (what
#     "follows" meant on v1) as its `mem_in`;
#   - a Phi's `memory` flag is what Phi::is_memory inferred from its inputs
#     (the inference lives here now, and only here, until v1 is deleted);
#   - a graph with no MemStart gets one;
#   - an unpinned Assign of SSA `my` scalars, or of @_ into `my` aggregates,
#     is a `record` (SoN::Verify's allowed:record / allowed:param-bind).
#
# DELETED WITH V1 (stage 6). Nothing here may be needed by a v2 wire.

class Chalk::IR::Serialize::WireUpgrade {

    # The input that is a read's or a write's memory version, by op: [index,
    # the input count that has it]. B::SoN's %MEM_MIN_INPUTS
    # (lib/SoN/Deparse.pm), where it is always the last input.
    my %MEMORY_SLOT = (
        EntryWrite => 2, Delete => 2, ElemRestore => 4, Exists => 2, Subscript => 2,
        Count => 1, RefType => 1, PostfixDeref => 1, Ref => 1, EntryDef => 0, PadAccess => 0,
        FieldAccess => 0, Transliterate => 1, MakeCell => 1, CellRead => 1, CellWrite => 2,
    );

    # The kinds chalk took for a memory version wherever they stood (their
    # class said so); and those it took for one only where pinned.
    my %ALWAYS_A_VERSION = map { $_ => 1 } qw(Assign EntryWrite CellWrite Delete ElemRestore);
    my %A_VERSION_PINNED = map { $_ => 1 }
        qw(Call Subscript Count Exists PostfixDeref Match RegexMatch RegexSubst Transliterate);

    my %SUB_CALL = map { $_ => 1 } qw(direct method dynamic_method indirect);

    # upgrade($data) -> $data, a decoded v1 wire rewritten as v2 (profile mem).
    sub upgrade ($data) {
        my $v = $data->{version} // 1;
        die "GAP: wire version $v is not one the loader upgrades\n" unless $v == 1;
        for my $name ( sort keys +( $data->{methods} // {} )->%* ) {
            upgrade_graph( $data->{methods}{$name}, $name );
        }
        upgrade_graph( $_, 'a ' . ( $_->{phase} // 'phase' ) . ' block' ) for ( $data->{phase_blocks} // [] )->@*;
        $data->{version} = 2;
        $data->{profile} = ['mem'];
        return $data;
    }

    # upgrade_graph($method_data, $name) -> $method_data, one graph of a v1
    # wire (or a graph chalk wrote in v1's shape: a regex's) made v2.
    sub upgrade_graph ( $g, $name = 'a graph' ) {
        my $nodes = $g->{nodes} // [];
        die "GAP: wire upgrade: $name keeps its nodes by id, not in order\n" unless ref $nodes eq 'ARRAY';
        for my $i ( 0 .. $#$nodes ) {
            die "GAP: wire upgrade: $name: node $i has id " . ( $nodes->[$i]{id} // 'none' ) . "\n"
                unless ( $nodes->[$i]{id} // -1 ) == $i;
        }
        _insert_memstart($g) unless grep { $_->{op} eq 'MemStart' } @$nodes;
        $nodes = $g->{nodes};
        my %by = map { ( $_->{id} => $_ ) } @$nodes;

        # WHAT CHALK CALLED A VERSION, decided on the wire as it came: a memory
        # Phi first (it asks of its inputs as v1 has them), then the rest.
        my %phi_memo;
        my %phi_memory = map { ( $_->{id} => _phi_is_memory( $_, \%by, \%phi_memo, {} ) ) }
            grep { $_->{op} eq 'Phi' } @$nodes;
        my %version;
        for my $n (@$nodes) {
            my $op = $n->{op};
            $version{ $n->{id} } = $op eq 'MemStart' ? 1
                : $op eq 'Phi' ? $phi_memory{ $n->{id} }
                : _was_a_version( $n, \%by );
        }

        # THE MEMORY INPUT, moved to mem_in.
        for my $n (@$nodes) {
            my $mi = _memory_slot( $n, \%by, \%version, $name ) // next;
            $n->{mem_in} = splice( $n->{inputs}->@*, $mi, 1 );
            delete $n->{fields}{memory_input} if $n->{fields};
            delete $n->{fields} if $n->{fields} && !$n->{fields}->%*;
        }

        # A PINNED VERSION says so.
        for my $n (@$nodes) {
            $n->{mem_out} = 1
                if defined $n->{control_in} && $version{ $n->{id} } && $n->{op} !~ /\A(?:MemStart|Phi)\z/;
        }

        # WHAT FOLLOWS THE CHAIN names the version before it.
        my ($ms) = grep { $_->{op} eq 'MemStart' } @$nodes;
        for my $n (@$nodes) {
            next if defined $n->{mem_in};
            my $op = $n->{op};
            my $sub_call = $op eq 'Call' && $SUB_CALL{ ( $n->{fields} // {} )->{dispatch_kind} // '' };
            next unless defined $n->{control_in}
                && ( $n->{mem_out} || $sub_call || $op eq 'Return' || $op eq 'Unwind' );
            my $m = _version_before( $n, \%by, \%version, $ms->{id} );
            $n->{mem_in} = $m if defined $m;
        }

        # THE PHI'S FLAG is what was inferred: a memory Phi is flagged, a
        # value Phi is not, either way.
        for my $n ( grep { $_->{op} eq 'Phi' } @$nodes ) {
            $n->{fields} //= {};
            if   ( $phi_memory{ $n->{id} } ) { $n->{fields}{memory} = 1 }
            else                             { delete $n->{fields}{memory} }
        }

        # A RECORD: an Assign off the chain that binds and stores nothing.
        for my $n ( grep { $_->{op} eq 'Assign' && !defined $_->{control_in} } @$nodes ) {
            ( $n->{fields} //= {} )->{record} = 1 if _is_record( $n, \%by );
        }
        return $g;
    }

    # _insert_memstart($g): a MemStart right after Start, every later id one
    # up -- in every place a wire names a node by its id.
    sub _insert_memstart ($g) {
        my $nodes = $g->{nodes};
        my $at = ( $g->{start} // 0 ) + 1;
        my $up = sub ($i) { defined $i && !ref $i && $i >= $at ? $i + 1 : $i };
        for my $n (@$nodes) {
            $n->{id} = $up->( $n->{id} );
            $n->{inputs} = [ map { ref $_ eq 'ARRAY' ? [ map { $up->($_) } @$_ ] : $up->($_) } ( $n->{inputs} // [] )->@* ];
            $n->{$_} = $up->( $n->{$_} ) for grep { defined $n->{$_} } qw(control_in head);
            my $f = $n->{fields} or next;
            $f->{$_} = $up->( $f->{$_} ) for grep { defined $f->{$_} } qw(region eval_entry);
            $f->{predecessors} = [ map { $up->($_) } $f->{predecessors}->@* ] if ref $f->{predecessors} eq 'ARRAY';
        }
        $g->{start} = $up->( $g->{start} );
        $g->{returns} = [ map { $up->($_) } ( $g->{returns} // [] )->@* ];
        splice @$nodes, $at, 0, { id => $at, op => 'MemStart', inputs => [] };
        return;
    }

    # _memory_slot($n, \%by, \%version, $name) -> the index of $n's memory input,
    # or undef where it has none.
    sub _memory_slot ( $n, $by, $version, $name ) {
        my ( $op, $in, $f ) = ( $n->{op}, $n->{inputs} // [], $n->{fields} // {} );
        if ( $op eq 'Call' || $op eq 'Unwind' ) {
            return undef unless $f->{memory_input};
            die "GAP: wire upgrade: $name: a $op with memory_input and no input\n" unless @$in;
            return $#$in;
        }
        # A s///: its target, its pattern where an input, a replacement made
        # of values where there is one, then its memory: the last of those
        # inputs where it is a version (as T2 told them apart).
        if ( $op eq 'RegexSubst' ) {
            my @rest = 1 + ( $f->{pattern_is_input} ? 1 : 0 ) .. $#$in;
            die "GAP: wire upgrade: $name: a RegexSubst of " . scalar(@$in) . " inputs\n" if @rest > 2;
            return $rest[-1] if @rest == 2 || @rest == 1 && $version->{ $in->[ $rest[0] ] // '' };
            return undef;
        }
        my $k = $MEMORY_SLOT{$op} // return undef;
        return undef unless @$in > $k;
        die "GAP: wire upgrade: $name: a $op of " . scalar(@$in) . " inputs (its memory is input $k)\n"
            if @$in > $k + 1;
        # (a `my` scalar's own declaration is no memory: an older wire's)
        return undef if $op eq 'PadAccess' && ( ( $by->{ $in->[0] // '' } // {} )->{op} // '' ) eq 'VarDecl';
        return $k;
    }

    # _was_a_version($n, \%by) -> true where chalk's class called the node a
    # memory version (Phi and MemStart aside).
    sub _was_a_version ( $n, $by ) {
        my $op = $n->{op};
        return 1 if $ALWAYS_A_VERSION{$op};
        my $pinned = defined $n->{control_in};
        return $pinned if $A_VERSION_PINNED{$op};
        # (a reference to an element taken where it stands: it reads memory)
        return $pinned && ( $n->{inputs} // [] )->@* > 1 if $op eq 'Ref';
        return 0;
    }

    # _version_before($n, \%by, \%version, $memstart) -> the id of the nearest
    # version back along $n's control chain: a pinned version, a Region's or
    # Loop's memory Phi (else its first way in's), MemStart at Start.
    sub _version_before ( $n, $by, $version, $ms ) {
        my %seen;
        my $x = $by->{ $n->{control_in} };
        while ( $x && !$seen{ $x->{id} }++ ) {
            my $op = $x->{op};
            return $x->{id} if $x->{mem_out};
            return $ms if $op eq 'Start';
            if ( $op eq 'Region' || $op eq 'Loop' ) {
                my ($phi) = sort { $a <=> $b } map { $_->{id} } grep {
                    $_->{op} eq 'Phi' && $version->{ $_->{id} } && ( ( $_->{fields} // {} )->{region} // -1 ) == $x->{id}
                } values %$by;
                return $phi if defined $phi;
                $x = $by->{ ( $x->{inputs} // [] )->[0] // '' };
                next;
            }
            $x = $by->{ $op =~ /\A(?:If|Proj)\z/ && !defined $x->{control_in} ? ( $x->{inputs} // [] )->[0] // '' : $x->{control_in} // '' };
        }
        return undef;
    }

    # _phi_is_memory($phi, \%by, \%memo, \%seen) -> 1 for a memory Phi:
    # Phi::is_memory's inference on v1's shape, the producer's flag where it
    # says what the inputs cannot.
    sub _phi_is_memory ( $phi, $by, $memo, $seen ) {
        return $memo->{ $phi->{id} } if exists $memo->{ $phi->{id} };
        return 0 if $seen->{ $phi->{id} }++;    # a loop's phis reach each other
        my $f = $phi->{fields} // {};
        # (the flag as the loader read it: set, unset where stamped, else unsaid)
        my $flag = $f->{memory} ? 1 : defined $phi->{stamp} ? 0 : undef;
        my $is = 0;
        for my $in ( map { $by->{$_} // () } grep { defined && !ref } ( $phi->{inputs} // [] )->@* ) {
            my ( $op, $inf, $iin ) = ( $in->{op}, $in->{fields} // {}, $in->{inputs} // [] );
            my $pinned = defined $in->{control_in};
            if ( $op eq 'MemStart' ) { $is = 1; last }
            if ( $op eq 'Assign' ) {
                # an element store, a field's, a location's, one through a reference
                if ( grep { ( ( $by->{ $_ // '' } // {} )->{op} // '' ) eq 'Subscript' } @$iin ) { $is = 1; last }
                my $lhs = $by->{ $iin->[0] // '' } // {};
                my $lop = $lhs->{op} // '';
                if ( $lop eq 'FieldAccess' || $lop eq 'PadAccess' && _is_location( $lhs, $by )
                     || $lop eq 'PostfixDeref' && ( ( $lhs->{fields} // {} )->{sigil} // '' ) eq '$' ) { $is = 1; last }
                # a list assignment the producer merges as memory
                if ( ( $in->{stamp} // '' ) eq 'List' && $flag ) { $is = 1; last }
            }
            if ( $op eq 'EntryWrite' ) { $is = 1; last }
            if ( $op eq 'Call' && $SUB_CALL{ $inf->{dispatch_kind} // '' } && !( defined $flag && !$flag ) ) { $is = 1; last }
            if ( $op eq 'Call' && ( $inf->{dispatch_kind} // '' ) eq 'builtin' && $flag ) { $is = 1; last }
            if ( $op =~ /\A(?:Subscript|Exists|PostfixDeref|Count|Ref)\z/ && $pinned && $flag ) { $is = 1; last }
            if ( $op eq 'Phi' && _phi_is_memory( $in, $by, $memo, $seen ) ) { $is = 1; last }
        }
        return $memo->{ $phi->{id} } = $is;
    }

    # _is_location($PadAccess, \%by) -> a `my` scalar kept in memory: shared,
    # or its input (on v1) a memory version and not its declaration.
    sub _is_location ( $p, $by ) {
        my $f = $p->{fields} // {};
        return 0 unless ( $f->{sigil} // '' ) eq '$';
        return 1 if $f->{shared};
        my $in = ( $p->{inputs} // [] )->[0];
        return defined $in && ( ( $by->{$in} // {} )->{op} // '' ) ne 'VarDecl' ? 1 : 0;
    }

    # _is_record($Assign, \%by) -> an Assign that is a binding, not a store
    # (SoN::Verify's record and param-bind): every target a `my` scalar
    # bound as a value (or undef in a list); or @_ into `my` aggregates.
    sub _is_record ( $n, $by ) {
        my $in = $n->{inputs} // [];
        my %class;
        for my $t ( @$in[ 0 .. ( ( $n->{fields} // {} )->{targets} // 1 ) - 1 ] ) {
            my $x = $by->{ $t // '' } or next;
            my $f = $x->{fields} // {};
            my $c = $x->{op} eq 'Constant' ? 'skip'
                : $x->{op} ne 'PadAccess'  ? 'other'
                : ( $f->{sigil} // '$' ) ne '$' ? 'my-aggregate'
                : ( defined $x->{mem_in} || ( $x->{inputs} // [] )->@* || $f->{shared} ) ? 'my-scalar-in-memory'
                : 'ssa-scalar';
            $class{$c} = 1;
        }
        my @mem = grep { $_ ne 'ssa-scalar' && $_ ne 'skip' } sort keys %class;
        return 1 unless @mem;
        my $args = ( ( $by->{ $in->[-1] // '' } // {} )->{op} // '' ) eq 'ArgsSource';
        return $args && "@mem" eq 'my-aggregate' ? 1 : 0;
    }
}

1;
