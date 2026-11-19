# ABOUTME: T1's integer intervals (Chalk::IR::Analysis::integer_intervals) prove where an Int
# ABOUTME: + - * stays an IV: there T2 emits a plain i64 op, elsewhere perl's IV, UV or NV -- never a stop.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Harness::TapDiff;
require Chalk::CodeGen::Pipeline;
require Chalk::IR::Serialize::JSON;
require Chalk::IR::Analysis;
require Chalk::IR::Graph;

sub wire ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return scalar qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $pl 2>/dev/null);
}

# graph($src) -> the program's nodes, T1 having run (the analysis is its last pass).
sub nodes ($src) {
    my $graphs = Chalk::IR::Serialize::JSON::from_json( wire($src) );
    return Chalk::IR::Graph::program_nodes( $graphs->{'main::__PROGRAM__'}->returns->[0] );
}

sub interval ($n) {
    my ( $lo, $hi ) = Chalk::IR::Analysis::int_interval($n) or return 'none';
    return ( $lo // '-inf' ) . '..' . ( $hi // '+inf' );
}

# the .ll T2 makes of a program
sub ll ($src) {
    my $select = sub ( $graphs, $mop ) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ( [ 'main::__PROGRAM__', $g->returns->[0] ] ) };
    my ($units) = Chalk::CodeGen::Pipeline->new->run_detail( wire($src), $select, program_mode => 1 );
    my $u = $units->[0];
    return ( $u->{path} // '' ) eq 't2' ? $u->{ll} : "REFUSED: " . ( $u->{path_why} // '' );
}
sub main_of ($ll) { my ($m) = $ll =~ /^(define i32 \@main.*?^\})/ms; $m // '' }

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# THE INTERVALS: constants are themselves; + - * of intervals; a loop's
# counter is bounded by its test in the body (`$i < 10`: $i in 0..9 there,
# $i + 1 in 1..10); an accumulator by the loop's trips (ten passes of + 0..9:
# $s in 0..90, $s + $i in 0..99); length and a mask.
{
    my @n = nodes('my $s = 0; my $i = 0; while ($i < 10) { $s = $s + $i; $i = $i + 1 } my $m = ($ENV{X} // 7) & 255; my $l = length($ENV{X} // "ab"); print "$s $i $m $l\n";');
    my ($ctr) = grep { $_->operation eq 'Add' && grep { blessed($_) && $_->operation eq 'Constant' && ( $_->value // '' ) eq '1' } $_->inputs->@* } @n;
    is interval($ctr), '1..10', 'a counter + 1, bounded by its loop test: 1..10';
    my ($iphi) = grep { $_->operation eq 'Phi' && grep { blessed($_) && $_ == $ctr } $_->inputs->@* } @n;
    is interval($iphi), '0..10', 'the counter merge: 0..10';
    my ($sum) = grep { $_->operation eq 'Add' && $_ != $ctr } @n;
    is interval($sum), '0..99', 'an accumulator, bounded by the loop\'s ten passes: 0..99';
    my ($and) = grep { $_->operation eq 'BitAnd' } @n;
    is interval($and), '0..255', '& 255: 0..255' if $and;
    my ($len) = grep { $_->operation eq 'Length' } @n;
    is interval($len), '0..9223372036854775807', 'a length: 0..IV_MAX' if $len && ( $len->stamp // '' ) eq 'Int';
    my ($k) = grep { $_->operation eq 'Constant' && ( $_->value // '' ) eq '10' } @n;
    is interval($k), '10..10', 'a constant: itself';
}

# A BOUND THAT IS NOT KNOWN bounds nothing: `$i < $n` of a scalar from
# outside leaves $i + 1 unbounded -- not guessed -- and so the passes, and an
# accumulator: widened, its lower bound kept.
{
    my @n = nodes('my $n = $ENV{X} // 5; my $s = 0; my $i = 0; while ($i < $n) { $s = $s + $i; $i = $i + 1 } print "$s $i\n";');
    my ($ctr) = grep { $_->operation eq 'Add' && grep { blessed($_) && $_->operation eq 'Constant' } $_->inputs->@* } @n;
    is interval($ctr), '1..+inf', 'a counter under an unknown bound: unbounded above';
    my ($sum) = grep { $_->operation eq 'Add' && $_ != $ctr } @n;
    is interval($sum), '0..+inf', 'an accumulator of unbounded passes: widened, its lower bound kept';
}

# THE IV RANGE'S EDGES: a bound is exact up to IV_MAX and down to IV_MIN
# (3037000499 ** 2 is the largest square an IV holds); one that would leave
# the range bounds nothing. (Past it a bound was kept to UV_MAX, in
# Math::BigInt: IV_MAX + 1 was 9223372036854775808..9223372036854775808. T2
# asks only whether a value is an IV and whether it is within 2**53, so a
# bound past IV_MAX answered nothing; it SATURATES now -- perl's UV or NV
# there is the general path's, as before.)
{
    my $vars = 'my $x = 9223372036854775807; my $y = -9223372036854775807 - 1; my $z = 3037000499; my $w = 3037000500;';
    for my $c ( [ '$x - 1', '9223372036854775806..9223372036854775806' ], [ '$y + 1', '-9223372036854775807..-9223372036854775807' ],
        [ '$x + $y', '-1..-1' ], [ '$z * $z', '9223372030926249001..9223372030926249001' ],
        [ '$x + 1', '-inf..+inf' ], [ '$y - 1', '-inf..+inf' ], [ '$x * 2', '-inf..+inf' ], [ '$y * -1', '-inf..+inf' ],
        [ '$w * $w', '-inf..+inf' ], [ '-$y', '-inf..+inf' ] ) {
        my ( $e, $want ) = @$c;
        my ($r) = grep { $_->operation =~ /\A(?:Add|Subtract|Multiply|Negate)\z/ } nodes("$vars my \$r = $e; print \$r;");
        is interval($r), $want, "$e: $want";
    }
}

# T2: AN i64 OP WHERE THE INTERVAL PROVES AN IV, the general path elsewhere,
# and no stop for overflow anywhere in what it emits.
{
    my $ll = ll('my $s = 0; for my $i (1 .. 10) { $s = $s + $i * 2 } my $j = 0; while ($j < 5) { $j = $j + 1 } print "$s $j\n";');
    my $m = main_of($ll);
    like $m, qr/= add i64 %v\d+, %v\d+\n  br label %loop/, 'the counter: a plain add i64';
    like $m, qr/= mul i64 /, '$i * 2 (2..20): a plain mul i64';
    unlike $m, qr/\@t2_slot_add/, 'the accumulator, bounded by ten passes: a plain add i64 too';
    $m = main_of( ll('my $n = $ENV{X} // 5; my $s = 0; for my $i (1 .. $n) { $s = $s + $i } print "$s\n";') );
    like $m, qr/call %Slot \@t2_slot_add/, 'an accumulator of unbounded passes: perl\'s general + (an IV, a UV or an NV)';
    unlike $ll, qr/\@t2_int_(?:add|sub|mul)\b|past what an i64 holds/, 'no checked op stops for overflow';
    $ll = ll('my $x = 4611686018427387904; my $r = $x * 2; print "$r\n";');
    unlike main_of($ll), qr/= mul i64 /, 'a product the interval puts past IV_MAX: not an i64 op';
}

# AS PERL at the edges, on what T1 types Int: an IV while one fits, a UV past
# IV_MAX, an NV past UV_MAX or below IV_MIN -- and back down to an IV.
{
    my $IVMAX = '9223372036854775807';
    my $IVMIN = '(-9223372036854775807 - 1)';
    my @e = ( [ $IVMAX, '$x + 1' ], [ $IVMAX, '$x + $x' ], [ $IVMAX, '$x + $x + 1' ], [ $IVMAX, '$x + $x + 2' ],
        [ $IVMAX, '$x - -1' ], [ $IVMIN, '1 - $x' ], [ $IVMIN, '0 - $x' ], [ $IVMIN, '$x * -1' ], [ $IVMIN, '-$x' ],
        [ '4611686018427387904', '$x * 2' ], [ '4611686018427387904', '$x * 4' ], [ '-4611686018427387904', '$x * -2' ],
        [ '3037000500', '$x * $x' ], [ '4294967296', '$x * $x' ], [ '4294967295', '$x * $x' ], [ '3037000499', '$x * $x' ],
        [ '-9223372036854775807', '$x - 2' ], [ '-9223372036854775807', '$x - 1' ], [ $IVMAX, '$x * -1 - 2' ], [ $IVMAX, '($x + 1) - 1' ],
        [ $IVMAX, '($x + 1) - $x' ], [ $IVMAX, '($x + 1) * 2' ], [ $IVMAX, '($x + $x + 1) - ($x + 1)' ], [ $IVMAX, '0 - ($x + 1)' ],
        [ $IVMAX, '-($x + 1)' ], [ $IVMAX, '-($x + 2)' ], [ $IVMAX, '($x + 1) * -1' ], [ $IVMIN, '($x - 1)' ], [ $IVMIN, '$x + ($x * -1)' ],
        [ '1e15', '$x * 10' ], [ '1e15', '$x + 1' ], [ '2.5', '$x * 2' ], [ '0.5', '$x * 3e15' ],
    );
    my $src = join '', map { my ( $v, $e ) = @$_; "{ my \$x = $v; my \$r = $e; print '$e: ', \$r, \"\\n\"; }\n" } @e;
    my $r = tap($src);
    is $r->{verdict}, 'SAME', '+ - * at the edges, on Int-typed values: as perl' or diag $r->{why} // '', "\n", explain $r;
}

# 2**63 AND 2**64 BY REPEATED DOUBLING (a loop's merge nothing bounds), up
# and down; and ++ to IV_MAX and past it.
{
    my $r = tap(<<'PL');
my $p = 1; my $q = -1; my @d;
for my $i (1 .. 66) { $p = $p * 2; $q = $q * 2; push @d, "$i:$p:$q" if $i >= 61 }
print "@d\n";
my $s = 1; $s *= 2 for 1 .. 63; print "$s ", $s - 1, " ", $s + $s - 1, " ", $s * 2, "\n";
my $w = 9223372036854775806; ++$w; ++$w; print "$w\n";
my $i = 0; my $x = 9223372036854775800; while ($i < 10) { $x++; $i++ } print "$x\n";
my $f = 1; $f = $f * $_ for 1 .. 25; print "$f\n";
PL
    is $r->{verdict}, 'SAME', 'doubling past IV_MAX and UV_MAX, ++ past IV_MAX, 25!: as perl' or diag $r->{why} // '', "\n", explain $r;
}

done_testing;
