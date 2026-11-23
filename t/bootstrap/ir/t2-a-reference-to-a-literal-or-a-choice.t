# ABOUTME: `\"lit"`, `\(c ? $v : 0)`: a reference to a literal is to a read-only cell (a store
# ABOUTME: through it dies as perl's); to a choice, the taken arm's; `\(c ? ($x, $y) : ())` one to each item.
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
    [ q{package N { sub new { bless { v => $_[1] }, $_[0] } sub val { $_[0]{v} } } sub f { my ($n) = @_; my $v = $n->val; return "v=${\(defined $v ? $v : q{u})}" } sub g { my ($c) = @_; my $v = 7; my $r = \($c ? $v : 0); $$r = 9 if $c; my $s = 5; my $t = 6; my @r = \($c ? ($s, $t) : ()); ${$r[1]} = 0 if $c; return "$v $s $t" } print f(N->new(5)), f(N->new(undef)), " ", g(1), " ", g(0), "\n";},
      'references to choices, stored through' ],
    [ q{sub h { my $k = $_[0]; my $r = \($k ? 1 : 0); $$r = 5; "no" } print eval { h(0) } // "died: $@";},
      'a store through a reference to a literal dies' ],
    [ q{sub g { my ($c) = @_; my $s = 5; my $t = 6; my @r = \($c ? ($s, $t) : ()); ${$r[1]} = 0 if $c; return scalar(@r) . " $s $t" } print g(1), "|", g(0), "\n";},
      'one to each item, or none' ],
    [ q{sub g { my ($c) = @_; my $s = 5; my @r = \($c ? ($s, 4) : 3); ${$r[0]} = 1; eval { ${$r[-1]} = 2 }; print $@ ? "ro\n" : "rw\n"; return "@{[scalar @r]} $s" } print g(1), "|", g(0), "\n";},
      'a literal among the items: read-only' ],
    [ q{my @l; for my $i (1..2) { my $x; if ($i) { $x = $i } push @l, \$x } print join(",", map { $$_ } @l), "\n";},
      'a body `my` referenced after an arm stored it' ],
    [ q{sub f { my ($c) = @_; my @l; if ($c) { my $x = $c; push @l, \$x } return @l } my @a = (f(1), f(2)); print join(",", map { $$_ } @a), "\n";},
      'a reference made in an arm, to its `my`' ],
    [ q{my $x = 1; my @l; for (1..2) { push @l, \$x; $x++ } print join(",", map { $$_ } @l), "\n";},
      'one variable referenced each pass' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

my @refused = (
    [ q{my @l = map { my $x = $_; \$x } 1..2; print join(",", map { $$_ } @l), "\n";},
      'a map body\'s `my` referenced' ],
    [ q{sub g { my ($k) = @_; my @a = (1); my @q = \($k ? @a : ()); return scalar(@q) . ref($q[0]) } print g(1), "\n";},
      'a reference to a choice of an array' ],
);

for my $case (@refused) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "$name: never a wrong answer" or diag explain $r;
    # (B::SoN's refusal of a sub the program calls is on the wire now, and the
    # loader names it: re-audit 2026-11-23, section 3 H)
    like $r->{why} // '', qr/T2: out of its slices|which the program calls, is refused in its module: GAP:/, "$name: refused by name" if $r->{verdict} eq 'REFUSED';
}

done_testing;
