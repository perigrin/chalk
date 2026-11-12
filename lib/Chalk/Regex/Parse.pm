# ABOUTME: Reads a constant regex into a tree (sequences, alternations, groups,
# ABOUTME: quantifiers, character sets, assertions, lookaround) for the graph builder.
package Chalk::Regex::Parse;
use 5.42.0;
use utf8;
use Chalk::Regex::Pattern;

# parse($pattern, $flags) -> { tree => NODE, ngroups => N, flags => {i m s x} }
#
# The graph builder's reader (Chalk::Regex::Graph); G6's flat atoms
# (Chalk::Regex::Pattern::compile) stay Context's. A NODE is one of
#
#   { t => 'seq',    items => [NODE...] }
#   { t => 'alt',    alts  => [NODE...] }                 a|b|c, tried in order
#   { t => 'group',  cap => K|undef, body => NODE }        (...) / (?:...)
#   { t => 'quant',  min, max (undef: no bound), greedy => 0|1, body => NODE }
#   { t => 'set',    ranges => [[lo,hi]...], neg => 0|1, ascii => 0|1 }
#                    one character in (or not in) the ranges; ascii: its
#                    meaning past ASCII is Unicode's (\d \w \s, /i, posix)
#   { t => 'assert', kind => bol|eol|mbol|meol|A|z|Z|b|B|G }
#   { t => 'look',   ahead => 0|1, neg => 0|1, body => NODE, width => W (behind) }
#   { t => 'rlit',   k => K }      the Kth literal known only at run time (\Q$x\E):
#                    the character chr($RLIT + K) in the pattern stands for it
#   { t => 'code',   n => N }      the Nth `(?{ ... })` block: zero-width
#
# Flags: i m s x (u is dropped -- see `ascii`); g c o r e are the OP's, not
# the pattern's, and pass through untouched. Anything else dies GAP: never a
# silent wrong match.

my %SHORT = (
    d => [ [ 48, 57 ] ],
    w => [ [ 48, 57 ], [ 65, 90 ], [ 97, 122 ], [ 95, 95 ] ],
    s => [ [ 9, 13 ], [ 32, 32 ] ],
);
my %POSIX = (
    alpha => [ [ 65, 90 ], [ 97, 122 ] ], digit => [ [ 48, 57 ] ], alnum => [ [ 48, 57 ], [ 65, 90 ], [ 97, 122 ] ],
    space => [ [ 9, 13 ], [ 32, 32 ] ], upper => [ [ 65, 90 ] ], lower => [ [ 97, 122 ] ],
    punct => [ [ 33, 47 ], [ 58, 64 ], [ 91, 96 ], [ 123, 126 ] ], word => $SHORT{w},
    xdigit => [ [ 48, 57 ], [ 65, 70 ], [ 97, 102 ] ], blank => [ [ 9, 9 ], [ 32, 32 ] ],
    cntrl => [ [ 0, 31 ], [ 127, 127 ] ], print => [ [ 32, 126 ] ], graph => [ [ 33, 126 ] ], ascii => [ [ 0, 127 ] ],
);

our $RLIT = 0xFDD0;    # (a noncharacter: never a pattern's own)
sub parse ( $pattern, $flags = '' ) {
    my %f = map { ( $_ => 1 ) } split //, $flags // '';
    my @bad = grep { !/[imsxugcoreal]/ } sort keys %f;
    die "GAP: regex flags '@bad' are not lowered as a graph\n" if @bad;
    die "GAP: regex flag /$_ (a character set) is not lowered as a graph\n" for grep { $f{$_} } qw(a l);
    my $st = { c => [ split //, $pattern ], i => 0, p => $pattern, f => \%f, ng => 0, nc => 0 };
    my $tree = _alt($st);
    die "GAP: unbalanced ')' in regex pattern '$pattern'\n" if $st->{i} <= $#{ $st->{c} };
    return { tree => $tree, ngroups => $st->{ng}, ncode => $st->{nc}, flags => { map { ( $_ => $f{$_} // 0 ) } qw(i m s x) } };
}

sub _peek ( $st, $k = 0 ) { return $st->{c}[ $st->{i} + $k ] }
sub _gap  ( $st, $what ) { die "GAP: $what in regex pattern '$st->{p}' is not lowered as a graph\n" }

sub _alt ($st) {
    my @alts = _seq($st);
    while ( ( _peek($st) // '' ) eq '|' ) { $st->{i}++; push @alts, _seq($st) }
    return @alts == 1 ? $alts[0] : { t => 'alt', alts => \@alts };
}

sub _seq ($st) {
    my @items;
    while ( defined( my $c = _peek($st) ) ) {
        last if $c eq '|' || $c eq ')';
        if ( $st->{f}{x} ) {    # /x: blanks and #-comments are not the pattern's
            if ( $c =~ /\s/ ) { $st->{i}++; next }
            if ( $c eq '#' ) { $st->{i}++ while defined _peek($st) && _peek($st) ne "\n"; next }
        }
        my $atom = _atom($st);
        push @items, _quant( $st, $atom );
    }
    return { t => 'seq', items => \@items };
}

sub _quant ( $st, $atom ) {
    my $c = _peek($st) // return $atom;
    my ( $min, $max );
    if    ( $c eq '*' ) { ( $min, $max ) = ( 0, undef ); $st->{i}++ }
    elsif ( $c eq '+' ) { ( $min, $max ) = ( 1, undef ); $st->{i}++ }
    elsif ( $c eq '?' ) { ( $min, $max ) = ( 0, 1 );     $st->{i}++ }
    elsif ( $c eq '{' && ( join '', @{ $st->{c} }[ $st->{i} .. $#{ $st->{c} } ] ) =~ /\A\{[ \t]*(?:(\d+)[ \t]*(,[ \t]*(\d*))?|,[ \t]*(\d+))[ \t]*\}/ ) {
        ( $min, $max ) = defined $4 ? ( 0, $4 ) : ( $1, defined $2 ? ( length( $3 // '' ) ? $3 : undef ) : $1 );
        die "regex {n,m} with m < n in pattern '$st->{p}'\n" if defined $max && $max < $min;
        $st->{i} += length $&;
    }
    else { return $atom }
    _gap( $st, 'a quantifier on an assertion' ) if $atom->{t} eq 'assert' || $atom->{t} eq 'look';
    my $greedy = 1;
    if    ( ( _peek($st) // '' ) eq '?' ) { $greedy = 0; $st->{i}++ }
    elsif ( ( _peek($st) // '' ) eq '+' ) { _gap( $st, 'a possessive quantifier' ) }
    _gap( $st, 'a quantifier on a quantifier' ) if ( _peek($st) // '' ) =~ /\A[*+?]\z/;
    return { t => 'quant', min => 0 + $min, max => defined $max ? 0 + $max : undef, greedy => $greedy, body => $atom };
}

sub _atom ($st) {
    my $c = $st->{c}[ $st->{i}++ ];
    my $f = $st->{f};
    if ( $c eq '(' ) {
        my ( $node, $cap );
        if ( ( _peek($st) // '' ) eq '?' ) {
            my $k = _peek( $st, 1 ) // '';
            if ( $k eq ':' ) { $st->{i} += 2 }
            elsif ( $k eq '=' || $k eq '!' ) {
                $st->{i} += 2;
                my $body = _alt($st);
                _close($st);
                return { t => 'look', ahead => 1, neg => $k eq '!' ? 1 : 0, body => $body };
            }
            elsif ( $k eq '<' && ( _peek( $st, 2 ) // '' ) =~ /\A[=!]\z/ ) {
                my $neg = _peek( $st, 2 ) eq '!' ? 1 : 0;
                $st->{i} += 3;
                my $body = _alt($st);
                _close($st);
                my $w = _width($body) // _gap( $st, 'a lookbehind of no one width' );
                return { t => 'look', ahead => 0, neg => $neg, body => $body, width => $w };
            }
            elsif ( $k eq '<' || $k eq 'P' || $k eq "'" ) { _gap( $st, 'a named capture' ) }
            # A CODE BLOCK: zero-width, the Nth body B::SoN lifted (Graph calls it).
            elsif ( $k eq '{' ) {
                $st->{i} = Chalk::Regex::Pattern::code_block_end( $st->{c}, $st->{i} + 2 );
                return { t => 'code', n => $st->{nc}++ };
            }
            elsif ( $k eq '?' ) { _gap( $st, 'a postponed subexpression (??{...})' ) }
            elsif ( $k eq '#' ) { $st->{i}++ while defined _peek($st) && _peek($st) ne ')'; $st->{i}++; return { t => 'seq', items => [] } }
            elsif ( $k eq '|' ) { _gap( $st, 'a branch reset (?|...)' ) }
            elsif ( $k eq '>' ) { _gap( $st, 'an atomic group (?>...)' ) }
            else { _gap( $st, "a (?$k...) construct" ) }
        }
        else { $cap = ++$st->{ng} }
        my $body = _alt($st);
        _close($st);
        return { t => 'group', cap => $cap, body => $body };
    }
    if ( $c eq '[' )  { return _class($st) }
    if ( $c eq '.' )  { return { t => 'set', ranges => $f->{s} ? [ [ 0, 0x10FFFF ] ] : [ [ 10, 10 ] ], neg => $f->{s} ? 0 : 1 } }
    if ( $c eq '^' )  { return { t => 'assert', kind => $f->{m} ? 'mbol' : 'bol' } }
    if ( $c eq '$' )  { return { t => 'assert', kind => $f->{m} ? 'meol' : 'eol' } }
    if ( $c eq '\\' ) {
        my $e = _peek($st) // die "regex pattern '$st->{p}' ends with a bare backslash\n";
        if ( $e =~ /\A[dwsDWS]\z/ ) { $st->{i}++; return { t => 'set', ranges => $SHORT{ lc $e }, neg => $e =~ /[DWS]/ ? 1 : 0, ascii => 1 } }
        if ( $e =~ /\A[AzZbBG]\z/ ) { $st->{i}++; return { t => 'assert', kind => $e } }
        if ( $e =~ /\A[1-9gk]\z/ )  { _gap( $st, 'a backreference' ) }
        if ( $e =~ /\A[hHvVRXKpPNC]\z/ ) { _gap( $st, "the escape \\$e" ) }
        return _lit( $st, _escape($st) );
    }
    if ( ord($c) >= $RLIT && ord($c) < $RLIT + 32 ) {
        _gap( $st, 'a literal known at run time under /i' ) if $f->{i};
        _gap( $st, 'a quantifier after a literal known at run time (it is its last character\'s)' ) if ( _peek($st) // '' ) =~ /\A[*+?{]\z/;
        return { t => 'rlit', k => ord($c) - $RLIT };
    }
    if ( $c eq ')' ) { die "GAP: unbalanced ')' in regex pattern '$st->{p}'\n" }
    if ( $c =~ /\A[*+?]\z/ ) { die "regex quantifier '$c' with no preceding atom in pattern '$st->{p}'\n" }
    return _lit( $st, ord $c );
}

sub _close ($st) {
    die "GAP: unbalanced '(' in regex pattern '$st->{p}'\n" unless ( _peek($st) // '' ) eq ')';
    $st->{i}++;
}

# _escape($st) -> the character a backslash escape (not a class or an
# assertion) stands for; $st->{i} is at the character after the backslash.
sub _escape ($st) {
    if ( ( _peek($st) // '' ) eq 'x' && ( _peek( $st, 1 ) // '' ) eq '{' ) {
        my $rest = join '', @{ $st->{c} }[ $st->{i} .. $#{ $st->{c} } ];
        $rest =~ /\Ax\{([0-9A-Fa-f]+)\}/ or die "malformed \\x{} escape in regex pattern '$st->{p}'\n";
        $st->{i} += length $&;
        return hex $1;
    }
    my ( $byte, $used ) = Chalk::Regex::Pattern::escape_byte( $st->{c}, $st->{i}, $st->{p} );
    $st->{i} += $used;
    return $byte;
}

# A literal character; under /i, either case of an ASCII letter (past ASCII
# perl folds by Unicode's rules: ascii).
sub _lit ( $st, $o ) {
    return { t => 'set', ranges => [ [ $o, $o ] ], neg => 0 } unless $st->{f}{i};
    return { t => 'set', ranges => _fold( [ [ $o, $o ] ] ), neg => 0, ascii => 1 };
}

sub _fold ($r) {
    my @out = @$r;
    for my $x (@$r) {
        my ( $lo, $hi ) = @$x;
        for ( [ 65, 90, 32 ], [ 97, 122, -32 ] ) {
            my ( $a, $z, $d ) = @$_;
            my ( $l, $h ) = ( $lo > $a ? $lo : $a, $hi < $z ? $hi : $z );
            push @out, [ $l + $d, $h + $d ] if $l <= $h;
        }
    }
    return \@out;
}

sub _class ($st) {
    my ( @r, $ascii );
    my $neg = 0;
    if ( ( _peek($st) // '' ) eq '^' ) { $neg = 1; $st->{i}++ }
    my $first = 1;
    while (1) {
        my $c = _peek($st) // die "unterminated character class in regex pattern '$st->{p}'\n";
        last if $c eq ']' && !$first;
        $first = 0;
        if ( $c eq '[' && ( _peek( $st, 1 ) // '' ) eq ':' ) {
            my $rest = join '', @{ $st->{c} }[ $st->{i} .. $#{ $st->{c} } ];
            $rest =~ /\A\[:(\^?)(\w+):\]/ or _gap( $st, 'a [: in a class' );
            my $set = $POSIX{$2} // _gap( $st, "the posix class [:$2:]" );
            _gap( $st, 'a negated posix class' ) if $1;
            push @r, @$set;
            $ascii = 1;
            $st->{i} += length $&;
            next;
        }
        my $lo;
        if ( $c eq '\\' ) {
            $st->{i}++;
            my $e = _peek($st) // die "regex class in '$st->{p}' ends with a bare backslash\n";
            if ( $e =~ /\A[dws]\z/ ) { push @r, @{ $SHORT{$e} }; $ascii = 1; $st->{i}++; next }
            _gap( $st, "\\$e inside [...]" ) if $e =~ /\A[DWShHvVpPNRXbBAzZG1-9]\z/;
            $lo = _escape($st);
        }
        else { $lo = ord $c; $st->{i}++ }
        if ( ( _peek($st) // '' ) eq '-' && ( _peek( $st, 1 ) // ']' ) ne ']' ) {
            $st->{i}++;
            my $h = _peek($st);
            my $hi;
            if ( $h eq '\\' ) { $st->{i}++; _gap( $st, 'a class shorthand as a range end' ) if ( _peek($st) // '' ) =~ /\A[dwsDWS]\z/; $hi = _escape($st) }
            else { $hi = ord $h; $st->{i}++ }
            die "invalid [] range (lo > hi) in regex pattern '$st->{p}'\n" if $lo > $hi;
            push @r, [ $lo, $hi ];
            next;
        }
        push @r, [ $lo, $lo ];
    }
    $st->{i}++;    # the ]
    if ( $st->{f}{i} ) { @r = @{ _fold( \@r ) }; $ascii = 1 }
    return { t => 'set', ranges => \@r, neg => $neg, ( $ascii ? ( ascii => 1 ) : () ) };
}

# _width(NODE) -> the characters it always matches, or undef if it varies.
sub _width ($n) {
    my $t = $n->{t};
    return 1 if $t eq 'set';
    return 0 if $t eq 'assert' || $t eq 'look';
    if ( $t eq 'seq' ) { my $w = 0; for ( @{ $n->{items} } ) { my $x = _width($_) // return undef; $w += $x } return $w }
    if ( $t eq 'alt' ) { my @w = map { _width($_) } @{ $n->{alts} }; return undef if grep { !defined || $_ != $w[0] } @w; return $w[0] }
    return _width( $n->{body} ) if $t eq 'group';
    if ( $t eq 'quant' ) { return undef unless defined $n->{max} && $n->{max} == $n->{min}; my $w = _width( $n->{body} ) // return undef; return $w * $n->{min} }
    return undef;
}

1;
