# ABOUTME: The audit-probe harness names the refusal of a program B::SoN skips, from B::SoN's
# ABOUTME: own words, rather than "no program graph" -- so a refusal that changes cause is seen.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# RE-AUDIT 2026-11-23, section 5: 48 gated refusals were recorded as "no
# program graph", with no name, so a refusal that changed cause was not seen.
my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print $fh q{my @s; for my $i (1..3) { push @s, sub { $i } } print join(",", map { $_->() } @s), "\n";};
close $fh;
my ( $v, $why ) = run_probe($pl)->@*;
is $v, 'REFUSED', 'refused';
like $why, qr/\AB::SoN: GAP: an anonymous sub closing over \$i is not yet lowered/, 'by the GAP B::SoN gave';

# (A PROGRAM PERL DOES NOT COMPILE has no graph either -- st3 uses `isa` with
# no feature for it. Audit 2: still "no program graph". Said by perl.)
( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print $fh q{my $o = {}; my $a = ($o isa K) ? 1 : 0; print "$a\n";};
close $fh;
( $v, $why ) = run_probe($pl)->@*;
is $v, 'REFUSED', 'a program perl does not compile: refused';
like $why, qr/\Aperl: the program does not compile: .*"isa"/, 'by what perl said';

done_testing;
