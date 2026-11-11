# ABOUTME: A constant regex as its own graph: the matcher sub (subject in, match
# ABOUTME: offsets out) compiled from the pattern into Sea-of-Nodes wire -- a state machine.
package Chalk::Regex::Graph;
use 5.42.0;
use utf8;
use Chalk::Regex::Parse;

# REGEXES ARE GRAPHS (perigrin, 2026-11-11). A constant regex is not run by a
# regex engine: each pattern is compiled, here, into the graph of its own sub
#
#     sub { my ($s) = @_; ...; return $found ? [start, end, g1s, g1e, ...] : undef }
#
# built of what any Perl sub is built of -- substr, string compares, loops,
# ifs, an array -- so a backend lowers it like any other sub (T2 calls it where
# the match is). The graph is written as B::SoN wire (nodes by index), so the
# one loader reads it as it reads a program's subs.
#
# HOW: the pattern's tree (Chalk::Regex::Parse) becomes a small program --
#   set S        the character at pos is in S: pos+1, else fail
#   split A B    go on at A; on failure come back to B (perl's order: A first)
#   jmp A
#   save K       slot K = pos (captures: 2g, 2g+1; progress marks after them)
#   check K      fail if pos == slot K (a loop body that matched nothing)
#   assert KIND  ^ $ \A \z \Z \b \B (and /m's ^ $)
#   look I ... lookend I    a lookaround, its body run where it stands
#   match
# -- and the program is compiled, instruction by instruction, into ONE graph:
#
#     while (found < 0 && start <= last) {
#         pc = 0; pos = start; slots = -1; run = 1
#         while (run) {
#             (pc's instruction, by a tree of ifs on pc) -- sets pc, pos, fail
#             if (fail) { pop the backtrack stack to the next choice, or run = 0 }
#         }
#         start++
#     }
#
# The backtrack stack is an array of pairs: (pc, pos) a choice to come back
# to; (-1-K, old) slot K's value to restore; (-1-NSLOTS-I, pos) lookaround I's
# barrier. The choices are made in perl's order, so the first match found is
# perl's. Characters are substr($s, pos, 1) compared as strings: perl's
# character semantics; every position read is within 0..length.
#
# matcher($pattern, $flags) -> { nodes => [...], start => 0, returns => [i], ngroups => N }
# Dies GAP for a construct it does not build (never a silent wrong match).
my $MAX_COPIES = 64;    # {n,m}: a body copied m times; past this, refused

# FLAVORS -- one graph per pattern and use:
#   scalar  [start, end, g1s, g1e, ...] or undef        a match's truth, its captures
#   list    an array ref: the groups (undef where one took no part), or (1)
#           with none; empty where it does not match    a match in list context
#   all     an array ref: each match's groups, or each whole match with none  m//g in list context
#   gscalar as scalar, from a position: arguments (subject, from, noempty) --
#           where pos() is (undef: 0) and where an empty match may not be;
#           \G matches at from                          m//g in scalar context
#   split   an array ref: the fields (and groups), by perl's split rules;
#           a second argument, the limit; %o: awk => 1 for split ' '
#   subst   [the new string, how many were replaced]     s/// (/g: each match)
#           %o: replacement => its text ($1.. in it), or computed => 1 (a
#           second argument, made by the program)
sub matcher ( $pattern, $flags, $flavor = 'scalar', %o ) {
    ( $pattern, $flags ) = ( '\\s+', '' ) if $o{awk};             # split ' ': fields between whitespace
    $flags .= 'm' if $flavor eq 'split' && $pattern eq '^';        # split /^/ is /^/m
    my $p = Chalk::Regex::Parse::parse( $pattern, $flags );
    die "Chalk::Regex::Graph: no flavor $flavor" unless $flavor =~ /\A(?:scalar|gscalar|list|all|subst|split)\z/;
    my $g = bless { n => [], const => {}, var => {}, stamp => {}, uniq => 0, prog => [], looks => [], nslots => 2 + 2 * $p->{ngroups} }, __PACKAGE__;
    $g->{ascii} = _any_ascii( $p->{tree} );
    $g->{ng}    = $p->{ngroups};
    $g->emit_prog( $p->{tree} );
    push @{ $g->{prog} }, ['match'];
    $g->{flavor} = $flavor;
    $g->{awk}    = $o{awk} ? 1 : 0;
    $g->{nrlit}  = $o{rlits} // 0;    # literals known at run time: arguments after the others
    $g->{global} = ( $flags // '' ) =~ /g/ ? 1 : 0;
    $g->{segs} = $o{computed} ? [ { kind => 'val' } ] : replacement( $o{replacement} // '', $p->{ngroups} ) if $flavor eq 'subst';
    $g->build($p);
    $g->prune;
    return { nodes => $g->{n}, start => 0, returns => [ $g->{ret} ], ngroups => $p->{ngroups} };
}

# translit($from, $to, $flags) -> the wire of tr/FROM/TO/'s graph: a sub of
# the subject giving [the new string, how many characters it matched]; each
# character looked up in FROM (the first place it is), TO's in its place (TO's
# last past its end; FROM's own with TO empty). /c /d /s die GAP.
sub translit ( $from, $to, $flags ) {
    die "GAP: tr///$1 is not lowered\n" if ( $flags // '' ) =~ /([cds])/;
    my @f = _tr_chars($from);
    my @t = _tr_chars($to);
    @t = @f unless @t;
    push @t, ( $t[-1] ) x ( @f - @t ) if @t < @f;
    my %seen;
    my @map = grep { !$seen{ $_->[0] }++ } map { [ $f[$_], $t[$_] ] } 0 .. $#f;
    my $g = bless { n => [], const => {}, var => {}, stamp => {} }, __PACKAGE__;
    $g->{ctl} = $g->node('Start');
    $g->{s}   = $g->node( 'PadAccess', f => { sigil => '$', symbol => 's' }, stamp => 'Str' );
    $g->node( 'Assign', in => [ $g->{s}, $g->node( 'ArgsSource', stamp => 'Array' ) ], f => { targets => 1 }, stamp => 'List' );
    $g->{len} = $g->node( 'Length', in => [ $g->{s} ], stamp => 'Int' );
    $g->set( acc => $g->str_(''), 'Str' );
    $g->set( count => $g->int_(0) );
    $g->set( i => $g->int_(0) );
    $g->while_( sub { $g->lt_( $g->get('i'), $g->{len} ) }, sub {
        my $c = $g->char( $g->get('i') );
        $g->set( out => $c, 'Str' );
        my $chain;
        $chain = sub ($k) {
            return if $k > $#map;
            $g->if_( $g->op2( 'StrEq', $c, $g->str_( $map[$k][0] ) ),
                sub { $g->set( out => $g->str_( $map[$k][1] ) ); $g->set( count => $g->add( $g->get('count'), $g->int_(1) ) ) },
                sub { $chain->( $k + 1 ) } );
        };
        $chain->(0);
        $g->set( acc => $g->cat( $g->get('acc'), $g->get('out') ) );
        $g->set( i => $g->add( $g->get('i'), $g->int_(1) ) );
        delete $g->{var}{out};
    } );
    my $a = $g->stmt( 'ArrayLiteral', in => [ $g->get('acc'), $g->get('count') ], stamp => 'ArrayRef' );
    $g->{ret} = $g->node( 'Return', in => [$a], ctl => $g->{ctl} );
    $g->prune;
    return { nodes => $g->{n}, start => 0, returns => [ $g->{ret} ] };
}

# _tr_chars($spec) -> its characters: ranges (a-z) expanded, escapes read.
sub _tr_chars ($spec) {
    my @c = split //, $spec // '';
    my @out;
    for ( my $i = 0; $i <= $#c; $i++ ) {
        my $ch = $c[$i];
        if ( $ch eq '\\' && $i < $#c ) {
            my $e = $c[ ++$i ];
            $ch = { n => "\n", t => "\t", r => "\r", f => "\f", e => "\e", a => "\a", 0 => "\0" }->{$e} // ( $e =~ /[A-Za-z0-9]/ ? die "GAP: tr escape \\$e is not lowered\n" : $e );
        }
        if ( ( $c[ $i + 1 ] // '' ) eq '-' && $i + 2 <= $#c ) {
            my $hi = $c[ $i + 2 ];
            die "GAP: tr range ending in an escape is not lowered\n" if $hi eq '\\';
            die "invalid tr range $ch-$hi\n" if ord $hi < ord $ch;
            push @out, map { chr } ord($ch) .. ord($hi);
            $i += 2;
            next;
        }
        push @out, $ch;
    }
    die "GAP: a tr character past ASCII is not lowered\n" if grep { ord > 127 } @out;
    return @out;
}

sub _any_ascii ($n) {
    return 1 if $n->{ascii} || ( $n->{t} eq 'assert' && $n->{kind} =~ /\A[bB]\z/ );
    return scalar grep { _any_ascii($_) } ( @{ $n->{items} // [] }, @{ $n->{alts} // [] }, $n->{body} // () );
}

# --- the program -------------------------------------------------------------

sub here ($g) { return scalar @{ $g->{prog} } }
sub ins ( $g, @i ) { push @{ $g->{prog} }, [@i]; return $#{ $g->{prog} } }

sub emit_prog ( $g, $n ) {
    my $t = $n->{t};
    if ( $t eq 'seq' ) { $g->emit_prog($_) for @{ $n->{items} }; return }
    if ( $t eq 'set' )    { $g->ins( 'set', $n ); return }
    if ( $t eq 'rlit' )   { $g->ins( 'rlit', $n->{k} ); return }
    if ( $t eq 'assert' ) {
        $g->{uses_G} = 1 if $n->{kind} eq 'G';
        $g->ins( 'assert', $n->{kind} );
        return;
    }
    if ( $t eq 'group' ) {
        $g->ins( 'save', 2 * $n->{cap} ) if defined $n->{cap};
        $g->emit_prog( $n->{body} );
        $g->ins( 'save', 2 * $n->{cap} + 1 ) if defined $n->{cap};
        return;
    }
    if ( $t eq 'alt' ) {
        my @jumps;
        my @alts = @{ $n->{alts} };
        for my $i ( 0 .. $#alts ) {
            if ( $i < $#alts ) {
                my $sp = $g->ins( 'split', undef, undef );
                $g->{prog}[$sp][1] = $g->here;
                $g->emit_prog( $alts[$i] );
                push @jumps, $g->ins( 'jmp', undef );
                $g->{prog}[$sp][2] = $g->here;
            }
            else { $g->emit_prog( $alts[$i] ) }
        }
        $g->{prog}[$_][1] = $g->here for @jumps;
        return;
    }
    if ( $t eq 'quant' ) {
        my ( $min, $max, $greedy, $body ) = @{$n}{qw(min max greedy body)};
        die "GAP: a quantifier of more than $MAX_COPIES copies is not lowered as a graph\n"
            if $min > $MAX_COPIES || ( defined $max && $max > $MAX_COPIES );
        $g->emit_prog($body) for 1 .. $min;
        if ( !defined $max ) {
            # L: split B E; B: [save mark] body [check mark]; jmp L; E:
            my $empty = _may_be_empty($body);
            my $mark  = $empty ? $g->{nslots}++ : undef;
            my $L     = $g->ins( 'split', undef, undef );
            my $B     = $g->here;
            $g->ins( 'save', $mark ) if $empty;
            $g->emit_prog($body);
            $g->ins( 'check', $mark ) if $empty;
            $g->ins( 'jmp', $L );
            my $E = $g->here;
            @{ $g->{prog}[$L] }[ 1, 2 ] = $greedy ? ( $B, $E ) : ( $E, $B );
            return;
        }
        # up to max-min more, each optional: split B E; B: body; split B2 E; ...
        my @splits;
        for ( 1 .. $max - $min ) {
            push @splits, $g->ins( 'split', undef, undef );
            $g->{prog}[ $splits[-1] ][1] = $g->here;
            $g->emit_prog($body);
        }
        my $E = $g->here;
        for my $sp (@splits) {
            my $B = $g->{prog}[$sp][1];
            @{ $g->{prog}[$sp] }[ 1, 2 ] = $greedy ? ( $B, $E ) : ( $E, $B );
        }
        return;
    }
    if ( $t eq 'look' ) {
        die "GAP: a capture inside a negative lookaround is not lowered as a graph\n" if $n->{neg} && _has_group( $n->{body} );
        push @{ $g->{looks} }, { neg => $n->{neg}, ahead => $n->{ahead}, width => $n->{width} };
        my $id = $#{ $g->{looks} };
        $g->ins( 'look', $id );
        $g->emit_prog( $n->{body} );
        $g->ins( 'lookend', $id );
        $g->{looks}[$id]{after} = $g->here;
        return;
    }
    die "GAP: a regex node $t is not lowered as a graph\n";
}

sub _may_be_empty ($n) {
    my $t = $n->{t};
    return 0 if $t eq 'set';
    return 1 if $t eq 'rlit';
    return 1 if $t eq 'assert' || $t eq 'look';
    return !grep { !_may_be_empty($_) } @{ $n->{items} } if $t eq 'seq';
    return scalar grep { _may_be_empty($_) } @{ $n->{alts} } if $t eq 'alt';
    return _may_be_empty( $n->{body} ) if $t eq 'group';
    return $n->{min} == 0 || _may_be_empty( $n->{body} ) if $t eq 'quant';
    return 1;
}
sub _has_group ($n) {
    return 1 if $n->{t} eq 'group' && defined $n->{cap};
    return scalar grep { _has_group($_) } ( @{ $n->{items} // [] }, @{ $n->{alts} // [] }, $n->{body} // () );
}

# --- the wire, a node at a time ---------------------------------------------

sub node ( $g, $op, %a ) {
    my $n = { id => scalar @{ $g->{n} }, op => $op, inputs => $a{in} // [] };
    $n->{fields}     = $a{f}     if $a{f};
    $n->{control_in} = $a{ctl}   if defined $a{ctl};
    $n->{head}       = $a{head}  if defined $a{head};
    $n->{stamp}      = $a{stamp} if $a{stamp};
    push @{ $g->{n} }, $n;
    return $n->{id};
}
# stmt(...): a node on the control chain, which goes on from it.
sub stmt ( $g, $op, %a ) { return $g->{ctl} = $g->node( $op, %a, ctl => $g->{ctl} ) }

sub int_ ( $g, $v ) {
    return $g->{const}{"i$v"} //= $g->node( 'Constant', f => { const_type => 'integer', value => "$v" }, stamp => 'Int' );
}
sub str_ ( $g, $v ) {
    die "Chalk::Regex::Graph: a constant past ASCII" if $v =~ /[^\x00-\x7f]/;   # (T2's strings are bytes)
    return $g->{const}{"s$v"} //= $g->node( 'Constant', f => { const_type => 'string', value => $v }, stamp => 'Str' );
}
sub undef_ ($g) { return $g->{const}{u} //= $g->node( 'Constant', f => { const_type => 'undef', value => '' }, stamp => 'Undef' ) }

sub op2  ( $g, $op, $a, $b, $stamp = 'Boolean' ) { return $g->node( $op, in => [ $a, $b ], stamp => $stamp ) }
sub add  ( $g, $a, $b ) { return $g->op2( 'Add', $a, $b, 'Int' ) }
sub sub_ ( $g, $a, $b ) { return $g->op2( 'Subtract', $a, $b, 'Int' ) }
sub and_ ( $g, @c )     { my $x = shift @c; $x = $g->op2( 'And', $x, $_ ) for @c; return $x }
sub or_  ( $g, @c )     { my $x = shift @c; $x = $g->op2( 'Or', $x, $_ ) for @c; return $x }
sub not_ ( $g, $x )     { return $g->node( 'Not', in => [$x], stamp => 'Boolean' ) }
sub eq_  ( $g, $a, $b ) { return $g->op2( 'NumEq', $a, $b ) }
sub lt_  ( $g, $a, $b ) { return $g->op2( 'NumLt', $a, $b ) }
sub char ( $g, $pos ) {
    return $g->node( 'Call', in => [ $g->{s}, $pos, $g->int_(1) ],
        f => { dispatch_kind => 'builtin', name => 'substr', param_names => [] }, stamp => 'Str' );
}

# --- variables (SSA: a name's current node; merges make phis) ----------------

sub set ( $g, $name, $v, $stamp = 'Int' ) { $g->{var}{$name} = $v; $g->{stamp}{$name} //= $stamp }
sub get ( $g, $name ) { return $g->{var}{$name} // die "Chalk::Regex::Graph: no variable $name" }

# while_(cond_cb, body_cb): a loop; its condition is the node cond_cb makes
# (fresh: the Loop is its control). A variable live at entry has a phi.
sub while_ ( $g, $cond_cb, $body_cb ) {
    my $L = $g->node( 'Loop', in => [ $g->{ctl} ], ctl => $g->{ctl}, f => { bound => 'each' } );
    my %entry = %{ $g->{var} };
    my %phi;
    for my $v ( sort keys %entry ) {
        $phi{$v} = $g->node( 'Phi', in => [ $entry{$v}, undef ], f => { region => $L }, stamp => $g->{stamp}{$v} );
        $g->{var}{$v} = $phi{$v};
    }
    my $c = $cond_cb->();
    die "Chalk::Regex::Graph: a loop condition already placed" if defined $g->{n}[$c]{control_in};
    $g->{n}[$c]{control_in} = $L;
    $g->{ctl} = $g->node( 'Proj', in => [$L], f => { index => 0 } );
    $body_cb->();
    $g->{n}[ $phi{$_} ]{inputs}[1] = $g->{var}{$_} // $phi{$_} for keys %phi;
    my $exit = $g->node( 'Proj', in => [$L], f => { index => 1 } );
    $g->{ctl} = $g->node( 'Region', in => [$exit], head => $L );
    $g->{var} = { map { ( $_ => $phi{$_} ) } keys %entry };   # (after it: the header's)
}

# if_(cond, then_cb, else_cb?): arms meet at a Region; a variable the arms
# leave differently gets a phi there.
sub if_ ( $g, $cond, $then_cb, $else_cb = undef ) {
    my $I = $g->node( 'If', in => [ $g->{ctl}, $cond ], ctl => $g->{ctl} );
    my %before = %{ $g->{var} };
    my @end;
    for my $arm ( [ 0, $then_cb ], [ 1, $else_cb ] ) {
        $g->{var} = {%before};
        my $pj = $g->{ctl} = $g->node( 'Proj', in => [$I], f => { index => $arm->[0] } );
        $arm->[1]->() if $arm->[1];
        push @end, [ $pj, $g->{ctl}, { %{ $g->{var} } } ];
    }
    my $R = $g->{ctl} = $g->node( 'Region', in => [ map { $_->[1] } @end ], head => $I );
    $g->{var} = {};
    for my $v ( sort keys %before ) {
        my ( $t, $e ) = map { $_->[2]{$v} } @end;
        $g->{var}{$v} = $t == $e ? $t
          : $g->node( 'Phi', in => [ $t, $e ], f => { region => $R, predecessors => [ map { $_->[0] } @end ] }, stamp => $g->{stamp}{$v} );
    }
}

# switch_(var, lo, hi, cb): cb->(k) for the value k (lo..hi) var holds, by a
# tree of ifs (its depth the log of the cases).
sub switch_ ( $g, $var, $lo, $hi, $cb ) {
    return $cb->($lo) if $lo == $hi;
    my $mid = int( ( $lo + $hi + 1 ) / 2 );
    $g->if_( $g->lt_( $g->get($var), $g->int_($mid) ), sub { $g->switch_( $var, $lo, $mid - 1, $cb ) }, sub { $g->switch_( $var, $mid, $hi, $cb ) } );
}

# --- the stack ----------------------------------------------------------------

sub push_ ( $g, $code, $val ) {
    $g->stmt( 'Call', in => [ $g->{stack}, $code, $val ], f => { dispatch_kind => 'builtin', name => 'push', param_names => [] }, stamp => 'Int' );
}
sub pop_ ($g) {
    return $g->stmt( 'Call', in => [ $g->{stack} ], f => { dispatch_kind => 'builtin', name => 'pop', param_names => [] }, stamp => 'Scalar' );
}
sub depth ($g) { return $g->node( 'Count', in => [ $g->{stack} ], stamp => 'Int' ) }

# --- the matcher ---------------------------------------------------------------

sub build ( $g, $p ) {
    $g->{ctl} = $g->node('Start');
    $g->{s}   = $g->node( 'PadAccess', f => { sigil => '$', symbol => 's' }, stamp => 'Str' );
    my @params = ( $g->{s} );
    push @params, $g->{limit} = $g->node( 'PadAccess', f => { sigil => '$', symbol => 'limit' }, stamp => 'Int' ) if $g->{flavor} eq 'split';
    if ( $g->{flavor} eq 'gscalar' ) {
        push @params, $g->{pfrom} = $g->node( 'PadAccess', f => { sigil => '$', symbol => 'from' }, stamp => 'Scalar' ),
                      $g->{pnoempty} = $g->node( 'PadAccess', f => { sigil => '$', symbol => 'noempty' }, stamp => 'Scalar' );
    }
    push @params, $g->{rv} = $g->node( 'PadAccess', f => { sigil => '$', symbol => 'rv' }, stamp => 'Scalar' )
        if $g->{segs} && grep { $_->{kind} eq 'val' } @{ $g->{segs} };
    push @params, map { $g->{rlit}[$_] = $g->node( 'PadAccess', f => { sigil => '$', symbol => "lit$_" }, stamp => 'Str' ) } 0 .. $g->{nrlit} - 1;
    $g->node( 'Assign', in => [ @params, $g->node( 'ArgsSource', stamp => 'Array' ) ], f => { targets => scalar @params }, stamp => 'List' );
    $g->{len}   = $g->node( 'Length', in => [ $g->{s} ], stamp => 'Int' );
    $g->{stack} = $g->node( 'ArrayLiteral', stamp => 'Array' );
    $g->ascii_only if $g->{ascii};
    # A ^ OR \A FIRST (no /m): a match starts at 0 only.
    my $first = $p->{tree}{t} eq 'seq' ? $p->{tree}{items}[0] : $p->{tree};
    $g->{last} = $first && $first->{t} eq 'assert' && $first->{kind} =~ /\A(?:bol|A)\z/ ? $g->int_(0) : $g->{len};
    $g->set( "r$_" => $g->int_(-1) ) for 0 .. 1 + 2 * $g->{ng};
    $g->set( found => $g->int_(-1) );
    my $f = $g->{flavor};
    die "GAP: \\G in a match not in scalar context with /g\n" if $g->{uses_G} && $f !~ /\A(?:gscalar|all)\z/;
    if ( $f eq 'scalar' || $f eq 'gscalar' ) {
        if ( $f eq 'gscalar' ) {
            # (pos() undef: from 0; no empty match to avoid: -1)
            $g->set( gf => $g->int_(0) );
            $g->set( gz => $g->int_(-1) );
            $g->if_( $g->node( 'Defined', in => [ $g->{pfrom} ], stamp => 'Boolean' ), sub { $g->set( gf => $g->{pfrom} ) } );
            $g->if_( $g->node( 'Defined', in => [ $g->{pnoempty} ], stamp => 'Boolean' ), sub { $g->set( gz => $g->{pnoempty} ) } );
            $g->search( $g->get('gf'), $g->get('gz') );
        }
        else { $g->search( $g->int_(0), $g->int_(-1) ) }
        $g->set( res => $g->undef_, 'Maybe[ArrayRef]' );
        $g->if_( $g->op2( 'NumGe', $g->get('found'), $g->int_(0) ), sub {
            $g->set( res => $g->stmt( 'ArrayLiteral', in => [ map { $g->get("r$_") } 0 .. 1 + 2 * $g->{ng} ], stamp => 'ArrayRef' ) );
        } );
        $g->{ret} = $g->node( 'Return', in => [ $g->get('res') ], ctl => $g->{ctl} );
        return;
    }
    if ( $f eq 'subst' ) { return $g->build_subst }
    if ( $f eq 'split' ) { return $g->build_split }
    $g->{out} = $g->node( 'ArrayLiteral', stamp => 'Array' );
    if ( $f eq 'list' ) {
        $g->search( $g->int_(0), $g->int_(-1) );
        $g->if_( $g->op2( 'NumGe', $g->get('found'), $g->int_(0) ), sub { $g->push_groups( $g->{ng} ? () : $g->int_(1) ) } );
    }
    else {    # all: from where the last match ended; not empty again where it was
        $g->set( from => $g->int_(0) );
        $g->set( noempty => $g->int_(-1) );
        $g->set( done => $g->int_(0) );
        $g->while_( sub { $g->eq_( $g->get('done'), $g->int_(0) ) }, sub {
            $g->search( $g->get('from'), $g->get('noempty') );
            $g->if_( $g->lt_( $g->get('found'), $g->int_(0) ), sub { $g->set( done => $g->int_(1) ) }, sub {
                $g->push_groups( $g->{ng} ? () : $g->text( $g->get('r0'), $g->get('r1') ) );
                $g->if_( $g->eq_( $g->get('r0'), $g->get('r1') ), sub { $g->set( noempty => $g->get('r1') ) }, sub { $g->set( noempty => $g->int_(-1) ) } );
                $g->set( from => $g->get('r1') );
            } );
        } );
    }
    $g->{ret} = $g->node( 'Return', in => [ $g->node( 'Ref', in => [ $g->{out} ], stamp => 'ArrayRef' ) ], ctl => $g->{ctl} );
}

# build_subst(): s/// -- the subject copied around each match (each, with
# /g), the replacement in its place; [the new string, how many].
sub build_subst ($g) {
    $g->set( acc => $g->str_(''), 'Str' );
    $g->set( last => $g->int_(0) );
    $g->set( count => $g->int_(0) );
    $g->set( from => $g->int_(0) );
    $g->set( noempty => $g->int_(-1) );
    $g->set( done => $g->int_(0) );
    $g->while_( sub { $g->eq_( $g->get('done'), $g->int_(0) ) }, sub {
        $g->search( $g->get('from'), $g->get('noempty') );
        $g->if_( $g->lt_( $g->get('found'), $g->int_(0) ), sub { $g->set( done => $g->int_(1) ) }, sub {
            $g->set( acc => $g->cat( $g->get('acc'), $g->text( $g->get('last'), $g->get('r0') ) ) );
            for my $seg ( @{ $g->{segs} } ) {
                if    ( $seg->{kind} eq 'lit' ) { $g->set( acc => $g->cat( $g->get('acc'), $g->str_( $seg->{text} ) ) ) }
                elsif ( $seg->{kind} eq 'val' ) { $g->set( acc => $g->cat( $g->get('acc'), $g->{rv} ) ) }
                else {    # $N: its text, "" where it took no part
                    my $k = $seg->{n};
                    $g->set( gv => $g->str_(''), 'Str' );
                    $g->if_( $g->op2( 'NumGe', $g->get( 'r' . 2 * $k ), $g->int_(0) ),
                        sub { $g->set( gv => $g->text( $g->get( 'r' . 2 * $k ), $g->get( 'r' . ( 2 * $k + 1 ) ) ) ) } );
                    $g->set( acc => $g->cat( $g->get('acc'), $g->get('gv') ) );
                    delete $g->{var}{gv};
                }
            }
            $g->set( last => $g->get('r1') );
            $g->set( count => $g->add( $g->get('count'), $g->int_(1) ) );
            $g->if_( $g->eq_( $g->get('r0'), $g->get('r1') ), sub { $g->set( noempty => $g->get('r1') ) }, sub { $g->set( noempty => $g->int_(-1) ) } );
            $g->set( from => $g->get('r1') );
            $g->set( done => $g->int_(1) ) unless $g->{global};
        } );
    } );
    $g->set( acc => $g->cat( $g->get('acc'), $g->text( $g->get('last'), $g->{len} ) ) );
    my $a = $g->stmt( 'ArrayLiteral', in => [ $g->get('acc'), $g->get('count') ], stamp => 'ArrayRef' );
    $g->{ret} = $g->node( 'Return', in => [$a], ctl => $g->{ctl} );
}
sub cat ( $g, $a, $b ) { return $g->op2( 'Concat', $a, $b, 'Str' ) }

# build_split(): perl's split -- a field before each match (and its groups,
# undef where one took no part), the rest after the last; no empty match where
# a field starts or at the end; a positive LIMIT caps the fields, 0 drops the
# empty ones at the end; ' ' (awk) skips leading whitespace. "" gives none.
sub build_split ($g) {
    $g->{out} = $g->node( 'ArrayLiteral', stamp => 'Array' );
    my $push = sub ($v) { $g->stmt( 'Call', in => [ $g->{out}, $v ], f => { dispatch_kind => 'builtin', name => 'push', param_names => [] }, stamp => 'Int' ) };
    $g->if_( $g->lt_( $g->int_(0), $g->{len} ), sub {
        $g->set( last => $g->int_(0) );
        if ( $g->{awk} ) {
            $g->while_( sub { $g->and_( $g->lt_( $g->get('last'), $g->{len} ), $g->in_set( { ranges => [ [ 9, 13 ], [ 32, 32 ] ], neg => 0 }, $g->char( $g->get('last') ) ) ) },
                sub { $g->set( last => $g->add( $g->get('last'), $g->int_(1) ) ) } );
        }
        $g->set( fields => $g->int_(1) );
        $g->set( done => $g->int_(0) );
        $g->while_( sub { $g->eq_( $g->get('done'), $g->int_(0) ) }, sub {
            $g->if_( $g->and_( $g->lt_( $g->int_(0), $g->{limit} ), $g->op2( 'NumGe', $g->get('fields'), $g->{limit} ) ), sub { $g->set( done => $g->int_(1) ) }, sub {
                $g->search( $g->get('last'), $g->get('last') );
                # (an empty match at the end splits nothing)
                $g->if_( $g->or_( $g->lt_( $g->get('found'), $g->int_(0) ), $g->and_( $g->eq_( $g->get('r0'), $g->get('r1') ), $g->eq_( $g->get('r0'), $g->{len} ) ) ),
                    sub { $g->set( done => $g->int_(1) ) }, sub {
                        $push->( $g->text( $g->get('last'), $g->get('r0') ) );
                        for my $k ( 1 .. $g->{ng} ) {
                            $g->set( gv => $g->undef_, 'Maybe[Str]' );
                            $g->if_( $g->op2( 'NumGe', $g->get( 'r' . 2 * $k ), $g->int_(0) ), sub { $g->set( gv => $g->text( $g->get( 'r' . 2 * $k ), $g->get( 'r' . ( 2 * $k + 1 ) ) ) ) } );
                            $push->( $g->get('gv') );
                            delete $g->{var}{gv};
                        }
                        $g->set( last => $g->get('r1') );
                        $g->set( fields => $g->add( $g->get('fields'), $g->int_(1) ) );
                    } );
            } );
        } );
        $g->if_( $g->or_( $g->lt_( $g->get('last'), $g->{len} ), $g->op2( 'NumNe', $g->{limit}, $g->int_(0) ) ), sub { $push->( $g->text( $g->get('last'), $g->{len} ) ) } );
        # LIMIT 0: the empty fields at the end are dropped
        $g->if_( $g->eq_( $g->{limit}, $g->int_(0) ), sub {
            $g->set( trim => $g->int_(1) );
            $g->while_( sub { $g->and_( $g->eq_( $g->get('trim'), $g->int_(1) ), $g->lt_( $g->int_(0), $g->node( 'Count', in => [ $g->{out} ], stamp => 'Int' ) ) ) }, sub {
                my $x = $g->stmt( 'Call', in => [ $g->{out} ], f => { dispatch_kind => 'builtin', name => 'pop', param_names => [] }, stamp => 'Scalar' );
                $g->if_( $g->and_( $g->node( 'Defined', in => [$x], stamp => 'Boolean' ), $g->lt_( $g->int_(0), $g->node( 'Length', in => [$x], stamp => 'Int' ) ) ),
                    sub { $push->($x); $g->set( trim => $g->int_(0) ) } );
            } );
            delete $g->{var}{trim};
        } );
        delete $g->{var}{$_} for qw(last fields done);
    } );
    $g->{ret} = $g->node( 'Return', in => [ $g->node( 'Ref', in => [ $g->{out} ], stamp => 'ArrayRef' ) ], ctl => $g->{ctl} );
}

# replacement($text, $ngroups) -> [segments]: an s/// replacement's literal
# runs ({lit, text}) and $N references ({cap, n}). The parser has cooked its
# double-quotish escapes; only \$ and punctuation escapes are left.
sub replacement ( $repl, $ngroups ) {
    my ( @segs, $lit ) = ();
    $lit = '';
    my @c = split //, $repl;
    my $flush = sub { push @segs, { kind => 'lit', text => $lit } if length $lit; $lit = '' };
    for ( my $i = 0; $i <= $#c; $i++ ) {
        my $ch = $c[$i];
        if ( $ch eq '\\' && $i < $#c ) {
            die "GAP: s/// replacement escape \\$c[$i+1] is not lowered\n" if $c[ $i + 1 ] =~ /[A-Za-z0-9]/;
            $lit .= $c[ ++$i ];
            next;
        }
        if ( $ch eq '$' && $i < $#c ) {
            my $n = $c[ $i + 1 ];
            die "GAP: s/// replacement \$$n is not lowered (only \$1..\$9)\n" unless $n =~ /\A[1-9]\z/;
            die "GAP: s/// replacement \$$n$c[$i+2] (a group past 9) is not lowered\n" if ( $c[ $i + 2 ] // '' ) =~ /\A\d\z/;
            die "GAP: s/// replacement \$$n of a pattern of $ngroups group(s)\n" if $n > $ngroups;
            $flush->();
            push @segs, { kind => 'cap', n => 0 + $n };
            $i++;
            next;
        }
        $lit .= $ch;
    }
    $flush->();
    return \@segs;
}

# text($a, $b) -> substr($s, a, b - a)
sub text ( $g, $a, $b ) {
    return $g->node( 'Call', in => [ $g->{s}, $a, $g->sub_( $b, $a ) ], f => { dispatch_kind => 'builtin', name => 'substr', param_names => [] }, stamp => 'Str' );
}

# push_groups(@instead): push each group's text (undef where it took no
# part) onto the out array -- or, with no groups, @instead.
sub push_groups ( $g, @instead ) {
    if ( !$g->{ng} ) { $g->stmt( 'Call', in => [ $g->{out}, @instead ], f => { dispatch_kind => 'builtin', name => 'push', param_names => [] }, stamp => 'Int' ); return }
    for my $k ( 1 .. $g->{ng} ) {
        $g->set( gv => $g->undef_, 'Maybe[Str]' );
        $g->if_( $g->op2( 'NumGe', $g->get("r" . 2 * $k), $g->int_(0) ), sub { $g->set( gv => $g->text( $g->get( "r" . 2 * $k ), $g->get( "r" . ( 2 * $k + 1 ) ) ) ) } );
        $g->stmt( 'Call', in => [ $g->{out}, $g->get('gv') ], f => { dispatch_kind => 'builtin', name => 'push', param_names => [] }, stamp => 'Int' );
        delete $g->{var}{gv};
    }
}

# search($from, $noempty): the first match starting at from or after (not an
# empty one at noempty): found = its end, r0.. its offsets; found -1 for none.
sub search ( $g, $from, $noempty ) {
    $g->set( found => $g->int_(-1) );
    $g->set( "r$_" => $g->int_(-1) ) for 0 .. 1 + 2 * $g->{ng};
    $g->set( start => $from );
    $g->set( noempty_at => $noempty );
    $g->{gstart} = $from;    # where \G matches
    $g->while_(
        sub { $g->and_( $g->lt_( $g->get('found'), $g->int_(0) ), $g->op2( 'NumLe', $g->get('start'), $g->{last} ) ) },
        sub { $g->attempt; $g->set( start => $g->add( $g->get('start'), $g->int_(1) ) ) },
    );
    delete $g->{var}{$_} for qw(start noempty_at);
}

# attempt(): run the program from `start`; a match sets found and r0...
sub attempt ($g) {
    my $NS = $g->{nslots};
    my $last = $#{ $g->{prog} };
    $g->set( pc => $g->int_(0) );
    $g->set( pos => $g->get('start') );
    $g->set( run => $g->int_(1) );
    $g->set( "k$_" => $g->int_(-1) ) for 0 .. $NS - 1;
    $g->while_(
        sub { $g->eq_( $g->get('run'), $g->int_(1) ) },
        sub {
            $g->set( fail => $g->int_(0) );
            $g->switch_( 'pc', 0, $last, sub ($k) { $g->step($k) } );
            $g->if_( $g->eq_( $g->get('fail'), $g->int_(1) ), sub { $g->backtrack } );
            delete $g->{var}{fail};
        },
    );
    # (the stack is not left with this start's choices: emptied on a match)
    $g->while_( sub { $g->lt_( $g->int_(0), $g->depth ) }, sub { $g->pop_ } );
    delete $g->{var}{$_} for qw(pc pos run), map {"k$_"} 0 .. $NS - 1;
}

sub fail ($g) { $g->set( fail => $g->int_(1) ) }
sub next_ ( $g, $k ) { $g->set( pc => $g->int_( $k + 1 ) ) }

# step($k): instruction k.
sub step ( $g, $k ) {
    my ( $op, @a ) = @{ $g->{prog}[$k] };
    my $pos = $g->get('pos');
    if ( $op eq 'set' ) {
        $g->if_( $g->and_( $g->lt_( $pos, $g->{len} ), $g->in_set( $a[0], $g->char($pos) ) ),
            sub { $g->set( pos => $g->add( $pos, $g->int_(1) ) ); $g->next_($k) }, sub { $g->fail } );
    }
    elsif ( $op eq 'rlit' ) {
        # a literal known at run time: the subject has it here, character for character
        my $lit = $g->{rlit}[ $a[0] ] // die "Chalk::Regex::Graph: no run-time literal $a[0]";
        my $n = $g->node( 'Length', in => [$lit], stamp => 'Int' );
        my $end = $g->add( $pos, $n );
        $g->if_( $g->and_( $g->op2( 'NumLe', $end, $g->{len} ),
                           $g->op2( 'StrEq', $g->node( 'Call', in => [ $g->{s}, $pos, $n ], f => { dispatch_kind => 'builtin', name => 'substr', param_names => [] }, stamp => 'Str' ), $lit ) ),
            sub { $g->set( pos => $end ); $g->next_($k) }, sub { $g->fail } );
    }
    elsif ( $op eq 'split' ) { $g->push_( $g->int_( $a[1] ), $pos ); $g->set( pc => $g->int_( $a[0] ) ) }
    elsif ( $op eq 'jmp' ) { $g->set( pc => $g->int_( $a[0] ) ) }
    elsif ( $op eq 'save' ) {
        $g->push_( $g->int_( -1 - $a[0] ), $g->get("k$a[0]") );
        $g->set( "k$a[0]" => $pos );
        $g->next_($k);
    }
    elsif ( $op eq 'check' ) { $g->if_( $g->eq_( $pos, $g->get("k$a[0]") ), sub { $g->fail }, sub { $g->next_($k) } ) }
    elsif ( $op eq 'assert' ) { $g->if_( $g->assertion( $a[0] ), sub { $g->next_($k) }, sub { $g->fail } ) }
    elsif ( $op eq 'look' ) {
        my $L = $g->{looks}[ $a[0] ];
        my $bar = $g->int_( -1 - $g->{nslots} - $a[0] );
        if ( $L->{ahead} ) { $g->push_( $bar, $pos ); $g->next_($k) }
        else {
            # BEHIND: its body from pos - width, which must end where it began
            $g->if_( $g->lt_( $pos, $g->int_( $L->{width} ) ), sub { $g->fail_look( $a[0] ) }, sub {
                $g->push_( $bar, $pos );
                $g->set( pos => $g->sub_( $pos, $g->int_( $L->{width} ) ) );
                $g->next_($k);
            } );
        }
    }
    elsif ( $op eq 'lookend' ) {
        my $L = $g->{looks}[ $a[0] ];
        my $bar = -1 - $g->{nslots} - $a[0];
        # its body matched: back to its barrier (the body's choices dropped),
        # pos where the lookaround stands
        $g->set( c => $g->int_(0) );
        $g->set( v => $g->int_(0) );
        $g->while_( sub { $g->op2( 'NumNe', $g->get('c'), $g->int_($bar) ) },
            sub { $g->set( v => $g->pop_, 'Scalar' ); $g->set( c => $g->pop_, 'Scalar' ) } );
        $g->set( pos => $g->get('v') );
        delete $g->{var}{$_} for qw(c v);
        $L->{neg} ? $g->fail : $g->set( pc => $g->int_( $L->{after} ) );
    }
    elsif ( $op eq 'match' ) {
        # (m//g: not an empty match where the last one was)
        $g->if_( $g->and_( $g->eq_( $pos, $g->get('start') ), $g->eq_( $pos, $g->get('noempty_at') ) ), sub { $g->fail }, sub { $g->accept } );
    }
    else { die "Chalk::Regex::Graph: no instruction $op" }
}

sub accept ($g) {
    my $pos = $g->get('pos');
    {
        $g->set( found => $pos );
        $g->set( r0 => $g->get('start') );
        $g->set( r1 => $pos );
        $g->set( "r$_" => $g->get("k$_") ) for 2 .. 1 + 2 * $g->{ng};
        $g->set( run => $g->int_(0) );
    }
}

# a lookbehind that cannot start: as its body failing
sub fail_look ( $g, $id ) {
    my $L = $g->{looks}[$id];
    $L->{neg} ? $g->set( pc => $g->int_( $L->{after} ) ) : $g->fail;
}

# backtrack(): pop to the latest choice -- restoring slots on the way; a
# lookaround's barrier ends its body's choices -- or, none left, stop.
sub backtrack ($g) {
    my $NS = $g->{nslots};
    my $nl = scalar @{ $g->{looks} };
    $g->while_(
        sub { $g->and_( $g->eq_( $g->get('fail'), $g->int_(1) ), $g->lt_( $g->int_(0), $g->depth ) ) },
        sub {
            my $v = $g->pop_;
            my $c = $g->pop_;
            $g->set( c => $c, 'Scalar' );
            $g->if_( $g->op2( 'NumGe', $c, $g->int_(0) ),
                sub { $g->set( pc => $c ); $g->set( pos => $v ); $g->set( fail => $g->int_(0) ) },
                sub {
                    $g->if_( $g->op2( 'NumGt', $c, $g->int_( -1 - $NS ) ),
                        sub { $g->switch_( 'c', -$NS, -1, sub ($j) { $g->set( 'k' . ( -1 - $j ) => $v ) } ) },
                        sub {
                            return unless $nl;
                            # a lookaround's barrier: its body failed
                            $g->switch_( 'c', -$NS - $nl, -1 - $NS, sub ($j) {
                                my $L = $g->{looks}[ -1 - $NS - $j ];
                                if ( $L->{neg} ) { $g->set( pc => $g->int_( $L->{after} ) ); $g->set( pos => $v ); $g->set( fail => $g->int_(0) ) }
                            } );
                        } );
                } );
            delete $g->{var}{c};
        },
    );
    $g->if_( $g->eq_( $g->get('fail'), $g->int_(1) ), sub { $g->set( run => $g->int_(0) ) } );
}

# in_set($set, $char) -> a Boolean: the character is in the set.
sub in_set ( $g, $s, $c ) {
    my @in = map {
        my ( $lo, $hi ) = @$_;
        $lo == $hi ? $g->op2( 'StrEq', $c, $g->str_( chr $lo ) )
          : $g->and_( $g->op2( 'StrGe', $c, $g->str_( chr $lo ) ), $g->op2( 'StrLe', $c, $g->str_( chr( $hi > 127 ? 127 : $hi ) ) ) )
    } grep { $_->[0] <= 127 } @{ $s->{ranges} };
    die "GAP: a character class past ASCII is not lowered as a graph\n" if grep { $_->[0] > 127 || ( $_->[1] > 127 && $_->[1] != 0x10FFFF ) } @{ $s->{ranges} };
    my $x = @in ? $g->or_(@in) : $g->op2( 'NumLt', $g->int_(1), $g->int_(0) );
    # (a range reaching 0x10FFFF -- `.` under /s -- takes every character past ASCII too)
    $x = $g->or_( $x, $g->op2( 'StrGt', $c, $g->str_("\x7f") ) ) if grep { $_->[1] == 0x10FFFF } @{ $s->{ranges} };
    return $s->{neg} ? $g->and_( $g->op2( 'StrNe', $c, $g->str_('') ), $g->not_($x) ) : $x;
}

# is_word($i) -> a Boolean: position i (which may be -1 or length) holds a
# \w character. Guarded: substr there is not read outside the string.
sub is_word ( $g, $i ) {
    $g->set( w => $g->int_(0) );
    $g->if_( $g->and_( $g->op2( 'NumGe', $i, $g->int_(0) ), $g->lt_( $i, $g->{len} ) ),
        sub { $g->if_( $g->in_set( { ranges => [ [ 48, 57 ], [ 65, 90 ], [ 97, 122 ], [ 95, 95 ] ], neg => 0 }, $g->char($i) ), sub { $g->set( w => $g->int_(1) ) } ) } );
    my $w = $g->get('w');
    delete $g->{var}{w};
    return $w;
}

# assertion($kind) -> a Boolean: it holds at pos.
sub assertion ( $g, $kind ) {
    my ( $pos, $len ) = ( $g->get('pos'), $g->{len} );
    my $nl = sub ($i) { $g->op2( 'StrEq', $g->char($i), $g->str_("\n") ) };
    return $g->eq_( $pos, $g->int_(0) ) if $kind eq 'bol' || $kind eq 'A';
    return $g->eq_( $pos, $g->{gstart} ) if $kind eq 'G';
    return $g->eq_( $pos, $len ) if $kind eq 'z';
    if ( $kind eq 'eol' || $kind eq 'Z' ) {
        return $g->or_( $g->eq_( $pos, $len ), $g->and_( $g->eq_( $g->add( $pos, $g->int_(1) ), $len ), $nl->($pos) ) );
    }
    if ( $kind eq 'meol' ) { return $g->or_( $g->eq_( $pos, $len ), $nl->($pos) ) }
    if ( $kind eq 'mbol' ) {
        # pos 0, or after a newline (guarded: substr($s, -1) is the last character)
        $g->set( m => $g->int_(0) );
        $g->if_( $g->eq_( $pos, $g->int_(0) ), sub { $g->set( m => $g->int_(1) ) },
            sub { $g->if_( $nl->( $g->sub_( $pos, $g->int_(1) ) ), sub { $g->set( m => $g->int_(1) ) } ) } );
        my $m = $g->get('m');
        delete $g->{var}{m};
        return $g->eq_( $m, $g->int_(1) );
    }
    if ( $kind eq 'b' || $kind eq 'B' ) {
        my $before = $g->is_word( $g->sub_( $pos, $g->int_(1) ) );
        my $after  = $g->is_word($pos);
        return $g->op2( $kind eq 'b' ? 'NumNe' : 'NumEq', $before, $after );
    }
    die "GAP: the assertion $kind is not lowered as a graph\n";
}

# ascii_only(): \d \w \s, /i and posix classes here are ASCII's; perl's rules
# for a character past ASCII are Unicode's. A subject with one STOPS the
# program (a message to STDERR, exit 255) -- never a match perl would not make.
sub ascii_only ($g) {
    $g->set( i => $g->int_(0) );
    $g->while_(
        sub { $g->and_( $g->lt_( $g->get('i'), $g->{len} ), $g->op2( 'StrLe', $g->char( $g->get('i') ), $g->str_("\x7f") ) ) },
        sub { $g->set( i => $g->add( $g->get('i'), $g->int_(1) ) ) },
    );
    $g->if_( $g->lt_( $g->get('i'), $g->{len} ), sub {
        my $p = $g->stmt( 'Print', in => [ $g->node( 'Constant', f => { const_type => 'glob', value => 'STDERR' }, stamp => 'Glob' ),
            $g->str_("T2: a regex's \\d \\w \\s, /i or posix class against a character past ASCII (perl's rules there are Unicode's)\n") ],
            f => { has_filehandle => 1 }, stamp => 'Maybe[Boolean]' );
        $g->stmt( 'Call', in => [ $g->int_(255) ], f => { dispatch_kind => 'builtin', name => 'exit', param_names => [] }, stamp => 'Unknown' );
    } );
    delete $g->{var}{i};
}

# --- prune: a phi whose ways in are all one value is that value ---------------

sub prune ($g) {
    my $N = $g->{n};
    my %to;
    my $find = sub ($x) { $x = $to{$x} while defined $x && defined $to{$x}; $x };
    my $changed = 1;
    while ($changed) {
        $changed = 0;
        for my $n (@$N) {
            next if $n->{op} ne 'Phi' || $to{ $n->{id} };
            my %u = map { ( $_ => 1 ) } grep { $_ != $n->{id} } map { $find->($_) } @{ $n->{inputs} };
            next unless keys %u == 1;
            $to{ $n->{id} } = ( keys %u )[0];
            $changed = 1;
        }
    }
    return unless %to;
    my @keep = grep { !$to{ $_->{id} } } @$N;
    my %new;
    $new{ $keep[$_]{id} } = $_ for 0 .. $#keep;
    my $map = sub ($x) { defined $x ? $new{ $find->($x) } // die "Chalk::Regex::Graph: pruned node $x still used" : undef };
    for my $n (@keep) {
        $n->{inputs} = [ map { $map->($_) } @{ $n->{inputs} } ];
        $n->{control_in} = $map->( $n->{control_in} ) if defined $n->{control_in};
        $n->{head} = $map->( $n->{head} ) if defined $n->{head};
        if ( my $f = $n->{fields} ) {
            $f->{region} = $map->( $f->{region} ) if defined $f->{region};
            $f->{predecessors} = [ map { $map->($_) } @{ $f->{predecessors} } ] if $f->{predecessors};
        }
    }
    $g->{ret} = $map->( $g->{ret} );
    $_->{id} = $new{ $_->{id} } for @keep;
    $g->{n} = \@keep;
}

1;
