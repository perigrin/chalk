# ABOUTME: Stevan's curly examples (t/corpus/curly) through B::SoN, T2 and lli against perl:
# ABOUTME: none may be WRONG, each keeps the verdict VERDICTS.tsv records, and .expected is perl's.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use Chalk::CodeGen::Harness::AuditProbe qw(run_all read_baseline write_baseline);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

my $DIR      = 't/corpus/curly';
my $VERDICTS = "$DIR/VERDICTS.tsv";
my @files    = sort glob "$DIR/*.pl";
ok( scalar @files, 'there are examples' );

# (EACH .expected IS PERL'S: the oracle the harness compares with is perl run
# now, and the file must agree with it, or the copy has drifted)
for my $f (@files) {
    ( my $e = $f ) =~ s/\.pl\z/.expected/;
    ( my $base = $f ) =~ s{.*/}{};
    my $perl = qx(cd $DIR && $^X $base 2>&1);
    my $want = do { local ( @ARGV, $/ ) = $e; <> };
    is( $perl, $want, "$base: .expected is perl's output" );
}

my $res = run_all( \@files );
if ( $ENV{CURLY_UPDATE} ) { write_baseline( $res, $VERDICTS ); diag "re-recorded $VERDICTS" }
my $base = read_baseline($VERDICTS);
for my $name ( sort keys $res->%* ) {
    my ( $v, $why ) = $res->{$name}->@*;
    ok( $v ne 'WRONG' && $v ne 'TIMEOUT', "$name: not a wrong answer" ) or diag "$v $why";
    is( $v, ( $base->{$name} // ['(not in VERDICTS.tsv)'] )->[0], "$name: the verdict VERDICTS.tsv records" ) or diag $why;
}
is( scalar( keys $res->%* ), scalar( keys $base->%* ), 'VERDICTS.tsv has a row for every example, and no other' );

done_testing;
