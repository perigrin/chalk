# ABOUTME: L11 of the wire invariant: an alias carried as a value is private -- no callee stores the
# ABOUTME: variable before it reads @_, no pass stores the list before its item is used (SoN::Verify's V12).
use 5.42.0;
use utf8;
use experimental 'class';

# WHY THE LOADER HOLDS IT (third final audit, risk 5). SoN::Verify's V12
# (B::SoN's lib/SoN/Verify.pm, _alias_private) caught wrong wires the loader
# let through: chalk compiled nine programs whose wire said an argument, or
# a foreach/map/grep item, was a value read before a store that perl's alias
# sees (ya49: `123` for perl's `113`). The rule reads only the raw wire, as
# L1-L10 do, so it lives beside them: a port of V12, both halves, held to
# give the same answers (t/bootstrap/ir/loader-refuses-an-alias-that-is-not-private.t).
#
#   the call half   a sub call's input that is a read of a named variable at a
#                   version (not a `place`) must not be stored, in any callee
#                   the wire holds, before that callee reads @_ -- by its own
#                   store, or by a call whose subs store it or cannot be told.
#   the list half   a foreach, map or grep's per-pass item -- a Subscript of
#                   the list at the loop's memory Phi, not a place, not pinned
#                   -- must not be used after a store in that pass that may
#                   reach the list.
#
# WHOLE-WIRE, NOT PER GRAPH: a callee's stores are its graph's, and its
# callees', closed over the wire. A call of no sub known here (a code value)
# is not checked, as V12 does not.
#
#   Chalk::IR::Serialize::WireAliases->new->check($methods);
#
# check() returns nothing, or dies "GAP: wire invariant L11: GRAPH: ...\n".
class Chalk::IR::Serialize::WireAliases {
    my sub _f($n) { return $n->{fields} // {} }
    my sub sub_call($n) { return $n->{op} eq 'Call' && ( _f($n)->{dispatch_kind} // '' ) ne 'builtin' }

    # (a node's control predecessors: a Region's and a Loop's ways in, an
    # If's or a Proj's head, and its control_in)
    my sub control_preds($n) {
        my $in = $n->{inputs} // [];
        return grep { defined } @$in if $n->{op} eq 'Region' || $n->{op} eq 'Loop';
        my @p = $n->{op} =~ /\A(?:If|Proj)\z/ ? ( $in->[0] ) : ();
        push @p, $n->{control_in};
        return grep { defined } @p;
    }

    method check($methods) {
        my $m = $methods // {};
        my %by = map { my $g = $_; ( $g => { map { ( $_->{id} => $_ ) } ( $m->{$g}{nodes} // [] )->@* } ) } keys $m->%*;
        my $gap = sub ( $g, $n, $why ) { die "GAP: wire invariant L11: $g: $n->{op}#$n->{id} $why\n" };

        # src($g, $node) -> the variable an access names (an element: its container's), or undef
        my $src;
        $src = sub ( $g, $n ) {
            return undef unless $n;
            my ( $op, $f ) = ( $n->{op}, _f($n) );
            return '$' . ( $f->{package} // 'main' ) . "::$f->{symbol}" if $op eq 'EntryDef' && ( $f->{sigil} // '' ) eq '$';
            return 'agg:' . ( $f->{sigil} // '' ) . ( $f->{package} ? "$f->{package}::" : '' ) . $f->{symbol} if $op eq 'EntryDef';
            return 'my:' . ( $f->{sigil} // '' ) . $f->{symbol} if $op eq 'PadAccess' && $f->{shared};
            return 'agg:' . ( $f->{sigil} // '' ) . $f->{symbol} if $op =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && defined $f->{symbol};
            if ( $op eq 'Subscript' ) { my $c = $src->( $g, $by{$g}{ $n->{inputs}[0] // '' } ); return defined $c ? "elem:$c" : undef }
            return undef;
        };
        # the subs a call reaches, by the wire's graphs (undef: one not known here)
        my $callees = sub ( $g, $c ) {
            my ( $k, $name ) = ( _f($c)->{dispatch_kind} // '', _f($c)->{name} // '' );
            return [$name] if $k eq 'direct' && $m->{$name};
            if ( $k eq 'method' ) { my @t = sort grep { /::\Q$name\E\z/ } keys $m->%*; return @t ? \@t : undef }
            return undef;
        };
        # (A `local` IS A SAVE AND A RESTORE, by shape: a store to X that a
        # later store puts back with X read at the version before it -- of
        # another variable than the one $_[N] was bound to.)
        my %localish;
        for my $g ( keys $m->%* ) {
            my @w = grep { $_->{op} eq 'EntryWrite' } values $by{$g}->%*;
            for my $r (@w) {
                my $v = $by{$g}{ $r->{inputs}[1] // '' } or next;
                my $k = $src->( $g, $by{$g}{ $r->{inputs}[0] // '' } ) // next;
                next unless $v->{op} eq 'EntryDef' && defined $v->{mem_in} && ( $src->( $g, $v ) // '' ) eq $k;
                my @save = grep { ( $_->{mem_in} // -1 ) == $v->{mem_in} && ( $src->( $g, $by{$g}{ $_->{inputs}[0] // '' } ) // '' ) eq $k } @w;
                next unless @save;
                $localish{$g}{ $_->{id} } = 1 for ( $r, @save );
            }
        }
        my $skip = sub ( $g, $n ) { _f($n)->{local} || _f($n)->{restore} || $n->{op} eq 'ElemRestore' || $localish{$g}{ $n->{id} } };
        my $targets = sub ($n) {
            return $n->{inputs}->@[ 0 .. ( _f($n)->{targets} // 1 ) - 1 ] if $n->{op} eq 'Assign';
            return ( $n->{inputs}[0] ) if $n->{op} =~ /\A(?:EntryWrite|CellWrite|Delete|ElemRestore)\z/;
            return ();
        };
        my %own;
        for my $g ( keys $m->%* ) {
            for my $n ( values $by{$g}->%* ) {
                next if $skip->( $g, $n );
                next if $n->{op} eq 'Assign' && _f($n)->{record};
                for my $t ( grep { defined && !ref } $targets->($n) ) { my $k = $src->( $g, $by{$g}{$t} ); $own{$g}{$k} = 1 if defined $k }
            }
        }
        my ( %writes, $writes );
        $writes = sub ( $g, $seen = {} ) {
            return $writes{$g} if $writes{$g};
            return {} if $seen->{$g}++;
            my %w = ( $own{$g} // {} )->%*;
            for my $c ( grep { sub_call($_) } values $by{$g}->%* ) {
                my $t = $callees->( $g, $c ) or return $writes{$g} = { any => 1 };
                for my $h ( $t->@* ) { my $hw = $writes->( $h, $seen ); return $writes{$g} = { any => 1 } if $hw->{any}; %w = ( %w, $hw->%* ) }
            }
            return $writes{$g} = \%w;
        };
        # stores($g, $v, $key) -> the version $v of graph $g may store $key
        my $stores = sub ( $g, $v, $key ) {
            my $n = $by{$g}{$v} or return 0;
            if ( sub_call($n) ) {
                my $t = $callees->( $g, $n ) or return 1;
                return scalar grep { my $w = $writes->($_); $w->{any} || $w->{$key} } $t->@*;
            }
            return 0 if $skip->( $g, $n );
            return scalar grep { defined && !ref && ( $src->( $g, $by{$g}{$_} ) // '' ) eq $key } $targets->($n);
        };

        # THE CALL HALF.
        for my $g ( sort keys $m->%* ) {
            for my $c ( sort { $a->{id} <=> $b->{id} } grep { sub_call($_) } values $by{$g}->%* ) {
                my $t = $callees->( $g, $c ) or next;
                for my $i ( 0 .. $c->{inputs}->$#* ) {
                    my $a = $by{$g}{ $c->{inputs}[$i] // '' } or next;
                    next if _f($a)->{place} || !defined $a->{mem_in};
                    my $key = $src->( $g, $a ) // next;
                    for my $h ( $t->@* ) {
                        my %args = map { ( $_->{id} => 1 ) } grep { $_->{op} eq 'ArgsSource' } values $by{$h}->%*;
                        # (each read of @_ at a version: $_[N], a shift, a list assign of it)
                        for my $r ( grep { defined $_->{mem_in} && grep { defined && !ref && $args{$_} } ( $_->{inputs} // [] )->@* } values $by{$h}->%* ) {
                            my ( @q, %seen ) = ( $r->{mem_in} );
                            while ( defined( my $v = shift @q ) ) {
                                next if $seen{$v}++;
                                my $vn = $by{$h}{$v} or next;
                                last if $vn->{op} eq 'MemStart' && !@q;
                                $gap->( $g, $c, "hands argument $i ($key) as a value, and $h reads it after $vn->{op}#$v may store it (an alias that is not private)" )
                                    if $stores->( $h, $v, $key );
                                push @q, $vn->{op} eq 'Phi' ? grep { defined && !ref } $vn->{inputs}->@* : grep { defined } $vn->{mem_in};
                            }
                        }
                    }
                }
            }
        }

        # THE ALIAS-LIST HALF.
        for my $g ( sort keys $m->%* ) {
            my %cons;
            for my $n ( values $by{$g}->%* ) { push $cons{$_}->@*, $n for grep { defined && !ref } ( $n->{inputs} // [] )->@* }
            for my $r ( sort { $a->{id} <=> $b->{id} } grep { $_->{op} eq 'Subscript' && !_f($_)->{place} && defined $_->{mem_in} && !defined $_->{control_in} } values $by{$g}->%* ) {
                my $mphi = $by{$g}{ $r->{mem_in} } or next;
                my $loop = $by{$g}{ _f($mphi)->{region} // '' } or next;
                next unless $mphi->{op} eq 'Phi' && _f($mphi)->{memory} && $loop->{op} eq 'Loop';
                my $iphi = $by{$g}{ $r->{inputs}[1] // '' } or next;
                next unless $iphi->{op} eq 'Phi' && ( _f($iphi)->{region} // -1 ) == $loop->{id};
                # (the loop's own item: its test is `Count(list) > i` over this list and index)
                next unless grep {
                    my $t   = $by{$g}{ $_->{inputs}[1] // '' } // {};
                    my $cnt = $by{$g}{ $t->{inputs}[0] // '' } // {};
                    ( $t->{op} // '' ) eq 'NumGt' && ( $t->{inputs}[1] // -1 ) == $iphi->{id}
                        && ( $cnt->{op} // '' ) eq 'Count' && ( $cnt->{inputs}[0] // -1 ) == ( $r->{inputs}[0] // -2 )
                } grep { $_->{op} eq 'If' && ( $_->{control_in} // -1 ) == $loop->{id} } values $by{$g}->%*;
                my $key = $src->( $g, $r ) // next;
                # (a `my` array of this sub's own that no reference or call reaches: only its own stores)
                my $list = $by{$g}{ $r->{inputs}[0] // '' } // {};
                my $private = ( $list->{op} // '' ) =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && defined _f($list)->{symbol}
                    && _f($list)->{symbol} !~ /::/ && !_f($list)->{shared}
                    && !grep { $_->{op} eq 'Ref' || sub_call($_) } ( $cons{ $list->{id} // '' } // [] )->@*;
                # (the uses that run: through pure values to a node on a chain)
                my ( @anchor, %seen );
                my @q = ( $cons{ $r->{id} } // [] )->@*;
                while ( my $u = shift @q ) {
                    next if $seen{ $u->{id} }++;
                    if ( defined $u->{control_in} || $u->{op} =~ /\A(?:Return|If|Region|Phi|Unwind)\z/ ) { push @anchor, $u; next }
                    push @q, ( $cons{ $u->{id} } // [] )->@*;
                }
                for my $u (@anchor) {
                    my $rg = $u->{op} eq 'Phi' ? $by{$g}{ _f($u)->{region} // '' } : undef;
                    my ( @c, %cs ) = !$rg ? control_preds($u)
                        : $rg->{op} eq 'Loop' ? grep { defined } $rg->{inputs}[1]
                        : control_preds($rg);
                    while ( defined( my $v = shift @c ) ) {
                        next if $cs{$v}++ || $v == $loop->{id};
                        my $vn = $by{$g}{$v} or next;
                        $gap->( $g, $r, "is the per-pass item of $key, carried as a value, and $u->{op}#$u->{id} uses it after $vn->{op}#$v may store it (an alias that is not private)" )
                            if !( $private && sub_call($vn) ) && ( $stores->( $g, $v, $key ) || $stores->( $g, $v, $key =~ s/\Aelem://r ) );
                        push @c, control_preds($vn);
                    }
                }
            }
        }
        return;
    }
}

1;
