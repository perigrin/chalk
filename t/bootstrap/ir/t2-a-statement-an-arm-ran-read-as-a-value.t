# ABOUTME: A push an arm ran, read after the join by the && of the if's own condition (a sub's
# ABOUTME: last statement `push @p, $v if $c`), is the count the arm gave, carried to the join.
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

my @same = (
    [ q{sub f { my @p = (1); my $add = sub { push @p, $_[0] + 1 if $_[0] < 4 }; my $out = ""; for my $x (@p) { $add->($x); $out .= $x } return $out } print f(), "\n";},
      'a closure pushing onto the array its caller\'s foreach walks' ],
    [ q{my @p = (1); sub f { push @p, $_[0] if $_[0] > 1 } my $x = f(1); my $y = f(5); print "[$x][$y] @p\n";},
      'a push\'s count or the condition\'s false, returned' ],
    [ q{my @p; sub f { unshift @p, $_[0] unless $_[0] } my $x = f(0); my $y = f(3); print "[$x][$y] @p\n";},
      'an unshift\'s count or the condition\'s true, returned' ],
    [ q{sub c { $a <=> $b } my @r = @ARGV && sort c 3,1,2; print scalar(@r), "\n";},
      'a sort an arm ran, read as a list (the choice of lists makes its own)' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

done_testing;
