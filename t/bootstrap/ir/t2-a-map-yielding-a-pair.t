# ABOUTME: A map whose block yields more than one value (`map { $k => $v }`) appends
# ABOUTME: each, in order: B::SoN's ListAppend is [list so far, contribution...].
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

for my $src (
    q{my @F = ({name => "a"}, {name => "b"}); sub ff { return @F } my %I = do { my $i = 0; map { $_->{name} => $i++ } @F }; sub ix { $I{$_[0]} } print ix("a"), ix("b"), scalar(ff()), "\n";},
    q{my @l = map { ($_, $_ * 2) } 1, 2; print "@l\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
