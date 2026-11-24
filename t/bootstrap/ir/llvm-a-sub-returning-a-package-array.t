# ABOUTME: A sub whose value is a package array (`sub z { @a }`, or B::SoN's read of @a after
# ABOUTME: `@a = LIST`) gives its elements in a list and its count in a scalar. -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

# T2 took only a `my` array, a literal or a field array as an array return,
# and refused "returns a list as one value" for a package one. B::SoN now
# gives `sub z { @a = () }` the read of @a its store made (probe rea12, whose
# Return read the stored literal at no version), so that is this case too.
for my $case (
    [ q{our @a=(1,2); sub z { @a } my @r=z(); my $n = z(); print "@r $n\n";}, 'a package array' ],
    [ q{our @a=(1,2,3); sub z { @a=(4,5) } my @r = z(); my $n = z(); print "@r $n\n";}, 'a list assign to one' ],
    [ q{our @a=(1,2,3); sub z { @a=() } my $n=0; for (@a) { $n++; } z(); print "$n ".scalar(@a)."\n";}, 'rea12' ],
) {
    my ( $src, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'SAME', "$what: perl's output" ) or diag "$v $why";
}

done_testing;
