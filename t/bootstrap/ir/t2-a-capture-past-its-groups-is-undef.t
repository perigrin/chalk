# ABOUTME: A capture of a group its match does not have is undef: the match before it does
# ABOUTME: not lend it its groups (final audit 2026-11-24, class I, q07).
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

for my $src (
    q{"ab"=~/(a)(b)/; "c"=~/(c)/; print defined $2 ? 1 : 0, "\n";},
    q{"c"=~/(c)/; print defined $2 ? 1 : 0, defined $1 ? 1 : 0, "\n";},
    q{"ab"=~/(a)(b)/; print "$1$2\n";},
) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    my ( $v, $why ) = run_probe($pl)->@*;
    is( $v, 'SAME', "perl's answer: $src" ) or diag $why;
}

done_testing;
