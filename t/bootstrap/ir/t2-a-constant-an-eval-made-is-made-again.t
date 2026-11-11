# ABOUTME: a constant one eval's body made is made again where it is next read,
# ABOUTME: even when that first read is inside an arm (the arm's copy was lost).
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# The 1 the first eval ends with is read first in `or $err = 1`'s arm; the
# next evals read it again (Test::More's `eval { ...; 1 } or $err = $@`).
my $r = tap(<<'EOT');
my ($base, $err);
eval { $base->a(); 1 } or $err = 1;
eval { $base->b(); 1 } or $err = 2;
eval { $base->c(); 1 } or $err = 3;
print "$err\n";
EOT
is $r->{verdict}, 'SAME', 'three evals reading one constant: as perl through T2' or diag $r->{why} // explain $r;

done_testing;
