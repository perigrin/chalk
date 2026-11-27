# ABOUTME: A reference to a `my` scalar B::SoN says is made anew each pass (Ref fresh_each_pass)
# ABOUTME: is to that pass's own variable: a new cell where the pass reaches its `my`.
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
    [ q{use v5.42; sub g ($x) { "g$x" } sub f ($c) { $c = g($c); return g($c) } sub h ($x) { my $r = \$x; my @l; for (1..2) { my $x = $_; push @l, \$x } $$r = 0; join ",", $x, map { $$_ } @l } print f(1), " ", h(5), "\n";},
      'refs to a body `my`, and to a parameter' ],
    [ q{my @l; for my $i (1..3) { my $x = $i; push @l, \$x; $x .= "a"; ${$l[-1]} .= "b"; print $x } print " ", join(",", map { $$_ } @l), "\n";},
      'written by its name and through its reference' ],
    [ q{my @l; my $i = 0; while ($i < 2) { my $x = $i++; push @l, \$x } print join(",", map { $$_ } @l), "\n";},
      'in a while body' ],
    [ q{my @l; for my $i (1..2) { for my $j (1..2) { my $x = "$i$j"; push @l, \$x } } print join(",", map { $$_ } @l), "\n";},
      'in an inner loop' ],
    [ q{sub f { my @l; for my $i (1..2) { my $x; $x = $i * 2; push @l, \$x } return @l } my @a = f(); my @b = f(); ${$a[0]} = 9; print join(",", map { $$_ } @a, @b), "\n";},
      'each call its own' ],
    [ q{my @l; for my $i (1..2) { my $x = $i; my $r = \$x; $$r += 10; push @l, $x } print "@l\n";},
      'written through its reference, read by its name' ],
    # (the outer pass's variable, referred to in an inner loop: that loop's
    # pass made a cell of its own, never stored -- ",,," for "1,1,2,2")
    [ q{my @r; for my $i (1..2) { my $x = $i; for my $j (1..2) { push @r, \$x } } print join(",", map { $$_ } @r), "\n";},
      'the outer pass\'s, from an inner loop' ],
    # (a range's iterator is made anew each pass too: audit 4, X1)
    [ q{my @r; for my $i (1..3) { push @r, \$i } print join(",", map { $$_ } @r), "\n";},
      'a range iterator' ],
    [ q{my @r; for my $i (1..2) { for my $j (1..2) { push @r, \$i } } print join(",", map { $$_ } @r), "\n";},
      'a range iterator, from an inner loop' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

my @refused = (
    [ q{my @l; for my $i (1..2) { if ($i) { my $x = $i; push @l, \$x } } print join(",", map { $$_ } @l), "\n";},
      'its `my` in an arm of the body' ],
);

for my $case (@refused) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "$name: never a wrong answer" or diag explain $r;
    like $r->{why} // '', qr/T2: out of its slices/, "$name: refused by name" if $r->{verdict} eq 'REFUSED';
}

done_testing;
