# ABOUTME: The core test header through T2 -- BEGIN { chdir 't' if -d 't'; require
# ABOUTME: './test.pl' }: -d, chdir, and a require of a file compiled in (done: 1).
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile tempdir);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

my $dir = tempdir( CLEANUP => 1 );
mkdir "$dir/t";
open my $lib, '>', "$dir/t/lib.pl" or die $!; print $lib "sub tw { 2 * shift }\n1;\n"; close $lib;

for my $src (
    qq{print -d "$dir" ? "d" : "n", -d "$dir/none" ? "d" : "n", defined(-d "$dir/none") ? "D" : "U", -d "$dir/t/lib.pl" ? "d" : "n", "\\n";},
    qq{chdir "$dir"; print -d "t" ? "y\\n" : "n\\n";},
    qq{BEGIN { chdir "$dir"; chdir 't' if -d 't'; require './lib.pl'; } print tw(21), "\\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
