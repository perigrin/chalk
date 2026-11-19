#!/usr/bin/perl
# ABOUTME: Runs the IR audit's probes (t/data/audit-probes) through B::SoN, chalk T2 and lli
# ABOUTME: against perl; prints each verdict and the counts; --update rewrites BASELINE.tsv.
#
#   PERL5_SON_LIB=... perl -Ilib -It/lib tools/audit-probes.pl [--update] [--jobs N] [NAME ...]
#
# Exit 1 when any probe is WRONG (it printed something perl does not).
use v5.42.0;
use Getopt::Long;
use Chalk::CodeGen::Harness::AuditProbe qw(probes run_all read_baseline write_baseline $DIR);

my ( $update, $jobs ) = ( 0, 2 );
GetOptions( 'update' => \$update, 'jobs=i' => \$jobs ) or die "usage: $0 [--update] [--jobs N] [NAME ...]\n";
my @files = @ARGV ? map { "$DIR/$_.pl" } @ARGV : probes();
my $res   = run_all( \@files, jobs => $jobs );
my $base  = read_baseline();
my %n;
for my $name ( sort keys $res->%* ) {
    my ( $v, $why ) = $res->{$name}->@*;
    $n{$v}++;
    my $was = $base->{$name} ? $base->{$name}[0] : '';
    say sprintf '%-8s %-8s %s%s', $name, $v, ( $was && $was ne $v ? "(was $was) " : '' ), $why;
}
say join ' ', map { "$_=$n{$_}" } sort keys %n;
if ($update) {
    die "--update takes no probe names: the baseline is every probe\n" if @ARGV;
    write_baseline($res);
}
exit( $n{WRONG} ? 1 : 0 );
