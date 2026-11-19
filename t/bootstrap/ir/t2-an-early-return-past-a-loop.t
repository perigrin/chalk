# ABOUTME: An arm that returns early in an inner if, where the merge it reaches is past a
# ABOUTME: loop after the outer if: it waits there, the walk going on from the other arm.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

for my $case (
    [ q{sub walk { my ($op, $items) = @_; my @chain;
          if ($op eq "If" || $op eq "S") { push @chain, $op; return "stopped at @chain" if $op eq "If" }
          for my $item (@$items) { push @chain, $item }
          return "@chain" }
        print walk("If", [1]), " | ", walk("S", [2, 3]), " | ", walk("X", [4]), "\n";}, 'a return in an inner if, a foreach after' ],
    [ q{sub f { my ($n) = @_; my $s = "";
          if ($n > 0) { $s .= "p"; if ($n > 5) { return "big$s" } $s .= "q" }
          my $i = 0; while ($i < $n) { $s .= $i; $i++ }
          return $s }
        print f(7), " ", f(3), " ", f(0), "\n";}, 'a return in an inner if, a while after' ],
    [ q{sub f { my ($n) = @_; my @s = ("a");
          if ($n) { if ($n % 2) { push @s, "o" } else { return "even @s" } push @s, "x" }
          for my $k (1 .. 2) { push @s, $k }
          "@s" }
        print f(2), " ", f(3), " ", f(0), "\n";}, 'a return in the else arm' ],
) {
    my $r = tap("$case->[0]\n");
    is $r->{verdict}, 'SAME', $case->[1] or diag $r->{why} // explain $r;
}

done_testing;
