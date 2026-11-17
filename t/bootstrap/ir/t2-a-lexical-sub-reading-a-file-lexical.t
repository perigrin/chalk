# ABOUTME: A `my sub` reading a variable of the file captures nothing: called directly, as a
# ABOUTME: named sub is, the variable reached as the named sub reaches it.
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

my @same = (
    [ q{use v5.36; my @arr = (1, 2); my sub t { scalar @arr } print t(), "\n";},
      'a my sub counting a file array' ],
    [ q{use v5.36; my $n = 5; my @a = (1, 2, 3); my sub t ($k) { $n + $k + @a } print t(1), " ", t(2), "\n";},
      'a my sub with a signature reading file lexicals' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

done_testing;
