# ABOUTME: A loop condition that is an effect and a test (`while (my $n = shift @w)`): the
# ABOUTME: effect runs in the header each pass, before the test reads it, as perl's.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
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

for my $case (
    [ q{my @w = (1, 2, 3); my $s = ""; while (my $n = shift @w) { $s .= "<$n>" } print "$s|@w\n";}, 'a shift tested' ],
    [ q{sub g { "<$_[0]>" } sub f { my @w = (1, 2); my $s = ""; while (my $n = shift @w) { $s .= g($n) } $s } print f(), "\n";}, 'in a sub, a call in the body' ],
    [ q{my @w = (1, 2, 0, 4); my $s = ""; while (my $n = pop @w) { $s .= $n; push @w, 7 if $n == 4 } print "$s|@w\n";}, 'a pop, the body pushing' ],
    [ q{sub f { my ($x) = @_; my @l = ($x); my $s = ""; while (my $n = pop @l) { $s .= $n; push @l, $n - 1 if $n > 1 } $s } print f(3), f(1), "\n";},
      'an array made of an argument, popped in the header and pushed in the body' ],
    [ q{my @w = (5, 6); my $s = ""; while (shift @w) { $s .= scalar(@w) } print "$s\n";}, 'a bare shift' ],
) {
    my $r = tap("$case->[0]\n");
    is $r->{verdict}, 'SAME', $case->[1] or diag $r->{why} // explain $r;
}

done_testing;
