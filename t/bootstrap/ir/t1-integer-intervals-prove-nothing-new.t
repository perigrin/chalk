# ABOUTME: T1's integer intervals, over the census corpus and t2-integer-intervals.t's programs, prove
# ABOUTME: nothing the recorded oracle (the Math::BigInt analysis) did not: no new int_is_iv, no new 2**53 bound.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempdir);
use Digest::MD5 qw(md5_hex);
use Encode ();

# THE ORACLE. T2 asks the intervals two questions, each an optimisation with
# a safe fallback: int_is_iv (a raw i64, else a %Slot) and int_within(x,
# -2**53, 2**53) (an i64 that may divide as a double). The analysis was
# rewritten from Math::BigInt bounds to native ones that saturate at the IV
# range; the old analysis's answers, node by node, are recorded in
# t/bootstrap/ir/data/integer-intervals-oracle.tsv. SOUND: the analysis now
# answers yes only where the oracle did. A proof the oracle had and the
# analysis no longer has is a lost optimisation, not a wrong answer: listed
# (note), and held to the count recorded below.
#
# Re-record (only with an analysis known sound, and say why in the commit):
#   CHALK_RECORD_INTERVALS=1 prove -l -It/lib t/bootstrap/ir/t1-integer-intervals-prove-nothing-new.t
#
# LOST, 9 (2026-11-18, bounds saturating at the IV range): all in own:edges,
# each a value that leaves the IV range and comes back -- (IV_MAX + 1) - 1,
# (IV_MAX + 1) - IV_MAX, 0 - (IV_MAX + 1), -(IV_MAX + 1), (IV_MAX + 1) * -1,
# (IV_MAX + IV_MAX + 1) - (IV_MAX + 1), IV_MIN + IV_MIN * -1. The oracle
# bounded the UV between exactly; the analysis keeps no bound past IV_MAX,
# so T2 takes perl's general path for them (as perl, still). None in the
# census corpus.
#
# LOST, 17 (2026-11-26, length is Maybe[Int]: perl's length(undef) is undef,
# audit 3 N12): 8 more, each a Length whose operand's type may be undef -- a
# method call's result (chalk-found-gaps:22, twice), $_[0] (:30, :149), an
# array element (:65), a `my` from @_ (:89), $@ (:145), a string after a
# call (:164). The oracle proved them on `length` always being an Int, which
# is not perl's; T1 proves Int only for an operand that cannot be undef.
my $LOST_ALLOWED = 17;

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::IR::Serialize::JSON;
require Chalk::IR::Analysis;
require Chalk::IR::Graph;
require Chalk::CodeGen::Harness::T2Case;

my $ORACLE = 't/bootstrap/ir/data/integer-intervals-oracle.tsv';
my $EXACT  = '9007199254740992';    # 2**53

# t2-integer-intervals.t's programs, by name
my %OWN = (
    'own:counter' => 'my $s = 0; my $i = 0; while ($i < 10) { $s = $s + $i; $i = $i + 1 } my $m = ($ENV{X} // 7) & 255; my $l = length($ENV{X} // "ab"); print "$s $i $m $l\n";',
    'own:unknown-bound' => 'my $n = $ENV{X} // 5; my $s = 0; my $i = 0; while ($i < $n) { $s = $s + $i; $i = $i + 1 } print "$s $i\n";',
    'own:for-range' => 'my $s = 0; for my $i (1 .. 10) { $s = $s + $i * 2 } my $j = 0; while ($j < 5) { $j = $j + 1 } print "$s $j\n";',
    'own:for-unknown' => 'my $n = $ENV{X} // 5; my $s = 0; for my $i (1 .. $n) { $s = $s + $i } print "$s\n";',
    'own:product-past' => 'my $x = 4611686018427387904; my $r = $x * 2; print "$r\n";',
    'own:doubling' => <<'PL',
my $p = 1; my $q = -1; my @d;
for my $i (1 .. 66) { $p = $p * 2; $q = $q * 2; push @d, "$i:$p:$q" if $i >= 61 }
print "@d\n";
my $s = 1; $s *= 2 for 1 .. 63; print "$s ", $s - 1, " ", $s + $s - 1, " ", $s * 2, "\n";
my $w = 9223372036854775806; ++$w; ++$w; print "$w\n";
my $i = 0; my $x = 9223372036854775800; while ($i < 10) { $x++; $i++ } print "$x\n";
my $f = 1; $f = $f * $_ for 1 .. 25; print "$f\n";
PL
);
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
    $OWN{'own:edges'} = join '', map { my ( $v, $e ) = @$_; "{ my \$x = $v; my \$r = $e; print '$e: ', \$r, \"\\n\"; }\n" } @e;
}

# (one file for every program: a node's id carries its file's name, less $DIR)
my $DIR = tempdir( CLEANUP => 1 );
sub wire ($src) {
    my $pl = "$DIR/p.pl";
    open my $fh, '>', $pl or die "$pl: $!";
    print $fh $src; close $fh;
    return scalar qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $pl 2>/dev/null);
}

# answers($src) -> { node => 'iv' | 'e53' | 'iv,e53' } for each node
# proven anything, or a string: why there are no answers.
sub answers ($src) {
    my $json = wire($src);
    return 'NOJSON' unless $json =~ /\S/;
    my $graphs = eval { Chalk::IR::Serialize::JSON::from_json($json) } or return 'LOADFAIL';
    # (a node's id is structural -- two nodes may share one -- so a node is
    # named by its graph, its id and which of that id it is in the walk)
    my ( %seen, %out, %nth );
    for my $name ( sort grep { $graphs->{$_} } keys $graphs->%* ) {
        for my $n ( map { Chalk::IR::Graph::program_nodes($_) } $graphs->{$name}->returns->@* ) {
            next if $seen{ refaddr($n) }++;
            ( my $id = $n->id ) =~ s/\Q$DIR\E//g;
            # (a read's memory version, its last input when the oracle was
            # recorded, is its mem_in since wire v2: `...|mem=Call#5` in the
            # id where it was `...|Call#5`. The same node, named as recorded.)
            $id =~ s/\|mem=/|/g;
            my $k = "$name|$id#" . $nth{$name}{$id}++;
            my @a = ( Chalk::IR::Analysis::int_is_iv($n) ? 'iv' : (), Chalk::IR::Analysis::int_within( $n, "-$EXACT", $EXACT ) ? 'e53' : () );
            $out{$k} = join ',', @a if @a;
        }
    }
    return \%out;
}

my @cases = ( ( map { [ $_, $OWN{$_} ] } sort keys %OWN ), map { [ $_->{id}, $_->{src} ] } Chalk::CodeGen::Harness::T2Case::cases() );

if ( $ENV{CHALK_RECORD_INTERVALS} ) {
    open my $o, '>', $ORACLE or die "$ORACLE: $!";
    for my $c (@cases) {
        my ( $id, $src ) = @$c;
        my $a = answers($src);
        # a case line (its source's digest: a case whose source changed is not judged)
        print $o join( "\t", 'case', $id, md5_hex( Encode::encode_utf8($src) ), ref $a ? 'OK' : $a ), "\n";
        next unless ref $a;
        print $o join( "\t", 'node', $id, $_, $a->{$_} ), "\n" for sort keys $a->%*;
    }
    close $o;
    pass "recorded $ORACLE";
    done_testing;
    exit;
}

open my $fh, '<', $ORACLE or die "$ORACLE: $!";
my ( %digest, %status, %old );
while (<$fh>) {
    chomp;
    my @f = split /\t/;
    if ( $f[0] eq 'case' ) { $digest{ $f[1] } = $f[2]; $status{ $f[1] } = $f[3] }
    else                   { $old{ $f[1] }{ $f[2] } = $f[3] }
}
close $fh;

my ( $judged, @new, @lost ) = (0);
for my $c (@cases) {
    my ( $id, $src ) = @$c;
    next unless defined $digest{$id} && $digest{$id} eq md5_hex( Encode::encode_utf8($src) ) && $status{$id} eq 'OK';
    my $a = answers($src);
    unless ( ref $a ) { fail "$id: $a (the oracle loaded it)"; next }
    $judged++;
    my $o = $old{$id} // {};
    for my $k ( sort keys $a->%* ) {
        my %was = map { ( $_ => 1 ) } split /,/, $o->{$k} // '';
        push @new, "$id\t$k\t$_" for grep { !$was{$_} } split /,/, $a->{$k};
    }
    for my $k ( sort keys $o->%* ) {
        my %is = map { ( $_ => 1 ) } split /,/, $a->{$k} // '';
        push @lost, "$id\t$k\t$_" for grep { !$is{$_} } split /,/, $o->{$k};
    }
}
cmp_ok $judged, '>=', 400, "the oracle's cases judged ($judged)";
is scalar(@new), 0, 'no answer proven that the oracle did not prove (sound)' or diag join "\n", 'NEW:', @new;
note "LOST $_" for @lost;
cmp_ok scalar(@lost), '<=', $LOST_ALLOWED, "proofs the oracle had and the analysis lost: " . scalar(@lost) . " (allowed $LOST_ALLOWED)";

done_testing;
