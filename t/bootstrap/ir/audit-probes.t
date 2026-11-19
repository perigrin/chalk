# ABOUTME: every IR-audit probe (t/data/audit-probes) through B::SoN, T2 and lli against perl:
# ABOUTME: none may be WRONG, and each keeps the verdict BASELINE.tsv records for it.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use Chalk::CodeGen::Harness::AuditProbe qw(probes run_all read_baseline);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# A VERDICT THAT CHANGES FAILS THIS TEST, either way: a probe that went SAME
# -> REFUSED is a regression to look at, one that went REFUSED -> SAME is
# progress to record. Once looked at: tools/audit-probes.pl --update.
#
# WRONG, AND NOT CHALK'S TO REFUSE: for each of these B::SoN's wire is
# byte-for-byte the wire of a program chalk compiles right, so no check on
# chalk's side can tell them apart. They wait on the producer.
my %KNOWN_WRONG = (
    lo3  => 'a `local` in a loop body, left by `last`: the wire of the same loop without `local`',
    vp5  => "`\$a[0] + (\$a[0] = 10) + \$a[0]`, perl's late read of an operand: the wire of `my \$t = \$a[0]; \$a[0] = 10; \$t + 10 + \$a[0]`",
    fl14 => '`use warnings FATAL`: the wire carries no lexical warning bits',
);

my @files = probes();
my $res   = run_all( \@files );    # (two at a time, each under its own time limit)
my $base  = read_baseline();
ok( scalar @files, 'there are probes' );
for my $name ( sort keys $res->%* ) {
    my ( $v, $why ) = $res->{$name}->@*;
    if ( $KNOWN_WRONG{$name} ) { is( $v, 'WRONG', "$name: still wrong, and still listed ($KNOWN_WRONG{$name})" ) or diag "$v $why" }
    else {
        ok( $v ne 'WRONG' && $v ne 'TIMEOUT', "$name: not a wrong answer" ) or diag "$v $why";
        is( $v, ( $base->{$name} // ['(not in BASELINE.tsv)'] )->[0], "$name: the verdict BASELINE.tsv records" ) or diag $why;
    }
}
is( scalar( keys $res->%* ), scalar( keys $base->%* ), 'BASELINE.tsv has a row for every probe, and no other' );

done_testing;
