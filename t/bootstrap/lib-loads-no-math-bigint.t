#!/usr/bin/env perl
# ABOUTME: Guard: nothing under lib/ loads Math::BigInt -- not the integer intervals (bounds saturate
# ABOUTME: at the IV range) nor T2's constant checks (exact on the decimal string) -- loaded or run.

use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Find;

# perigrin (2026-11-18): no file under lib/ loads Math::BigInt. T2 asks the
# intervals only whether a value is an IV and whether it is within 2**53 --
# each with a safe fallback -- so no bound past the IV range is ever needed.
my $LOADS = qr/\bMath::BigInt\b/;

my ( @files, @hits );
find( { no_chdir => 1, wanted => sub { push @files, $_ if /\.pm\z/ } }, 'lib' );
for my $f ( sort @files ) {
    open my $fh, '<:utf8', $f or die "$f: $!";
    while ( my $l = <$fh> ) {
        next if $l =~ /^\s*#/;    # (a comment may say why it is not used)
        push @hits, "$f:$.: " . ( $l =~ s/^\s+//r =~ s/\s+\z//r ) if $l =~ $LOADS;
    }
}
cmp_ok( scalar @files, '>', 100, 'lib/\'s modules were found' );
is( scalar @hits, 0, 'no module under lib/ names Math::BigInt' ) or diag join "\n", @hits;

# LOADED AND RUN: the analysis and T2, over a program with a UV constant, a
# product past IV_MAX and a counted loop.
require Chalk::IR::Analysis;
require Chalk::Target::LLVM;
require Chalk::Target::LLVM::Builder;
my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
if ( -f "$SON/B/SoN.pm" ) {
    require File::Temp;
    require Chalk::CodeGen::Pipeline;
    my ( $fh, $pl ) = File::Temp::tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh 'my $u = 18446744073709551615; my $x = 4611686018427387904; my $r = $x * 2; my $s = 0; for my $i (1 .. 10) { $s = $s + $i } print "$u $r $s\n";';
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $pl 2>/dev/null);
    my $select = sub ( $graphs, $mop ) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ( [ 'main::__PROGRAM__', $g->returns->[0] ] ) };
    my ($units) = Chalk::CodeGen::Pipeline->new->run_detail( $json, $select, program_mode => 1 );
    is( $units->[0]{path} // '', 't2', 'the program went through T2' );
}
my @big = grep { m{\AMath/BigInt} } sort keys %INC;
is( scalar @big, 0, 'Math::BigInt is not loaded' ) or diag join "\n", @big;

done_testing;
