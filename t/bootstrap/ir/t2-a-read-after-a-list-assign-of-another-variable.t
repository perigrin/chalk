# ABOUTME: A variable kept in memory, read after a list assignment that does not assign it, is
# ABOUTME: read from its place (a try in a foreach, stevan/curly brainfuck.pl).
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# THE GAP: a read made after a list assignment, at its version, of a variable
# the assignment does not assign, took what the last list assignment of that
# variable gave -- and refused where there was none. A foreach variable read
# in a try's catch is kept in memory; the list assignment leaves it as it was.
for my $src (
    'use v5.42; sub r ($s) { die "bad\n" if $s eq "x"; return (1, 2) } for my $b ("a", "x") { try { my ($o, $s) = r($b); say "$b $s"; } catch ($e) { print "$b: $e"; } }',
    'use v5.42; my $k = 3; my $r = \$k; my ($p, $q) = (1, 2); print "$k $p $q\n";',
    'use v5.42; for my $b (1, 2) { my $c = eval { my ($x, $y) = ($b, $b * 2); $y }; print "$b $c\n" }',
    'use v5.42; sub r ($s) { return (1, 2) } try { my ($o, $s) = r("a"); say "$s"; } catch ($e) { print $e; }',
) {
    my $r = tap($src);
    is $r->{verdict}, 'SAME', "as perl through T2: $src" or diag $r->{why} // explain $r;
}
done_testing;
