# ABOUTME: A coercion retired as a vacuous widening clears its consumer's type only where the join
# ABOUTME: rule can derive it again: a builtin's type (join's Str) stays. B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Fifth final audit, vo05: `my @a = (1,2,3); my @l = ((@a[0,1] = (7,8)),
# "$a[0]"); print "@l\n"` failed to load: "IR: analysis finished with untyped
# Value node(s)". The Coerce[Unknown -> Str] of `"$a[0]"`, an operand of the
# join `"@l"` folds to, was retired; the join's stamp was cleared for the join
# rule to derive again, and a builtin's type is no join of its operands.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $src (
    q{my @a = (1,2,3); my @l = ((@a[0,1] = (7,8)), "$a[0]"); print "@l\n";},   # vo05
) {
    my ( $v, $why ) = verdict($src)->@*;
    unlike( $why, qr/untyped Value node/, "no internal error: $src" );
    like( $v, qr/\A(?:SAME|REFUSED)\z/, '...perl\'s answer, or refused by name' ) or diag "$v $why";
}

done_testing;
