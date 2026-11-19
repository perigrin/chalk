# ABOUTME: A read that cannot die -- of a `my` array however its versions merge, a
# ABOUTME: list's element, a fresh {...} -- may wait across a store: made before it, not refused.
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
    # A `my` ARRAY MERGED AT AN ARM (a Phi of its versions) is still
    # the sub's own array: no reference there to be wrong.
    [ q{sub f { my @l; push @l, "a", "b"; if ($_[0]) { my @n; for my $x (@l) { push @n, uc $x } @l = @n } if ($_[1]) { my @n; for my $x (@l) { push @n, "$x$x" } @l = @n } my $s = ""; for my $x (@l) { $s .= $x } return $s } print f(1, 0), f(0, 1), f(1, 1), f(0, 0), "\n";},
      'a `my` array merged at two arms, read across a push' ],
    [ q{sub emit { print "$_[0]\n" } sub f { my @t = map { "L$_" } 0 .. 2; for my $i (0 .. $#t) { my $n = $i < $#t ? $t[$i+1] : 'u'; emit($t[$i]); emit("br $n") } my @u = qw(a b); my $s = ''; for my $i (0 .. $#u) { my $v = $u[$i]; emit($u[$i]); $s .= "$v$u[$i] " } return $s } print f(), "\n";},
      'a list a map built, read across a call' ],
    # A LIST'S ELEMENT (foreach over a sort's list) is no reference read.
    [ q{package N { sub new { bless { i => $_[1] }, $_[0] } sub id { $_[0]{i} } } sub f { my %c = (a => N->new(1), b => N->new(2)); my %m; my @f = values %c; $m{ $_->id } = $_ for @f; my $s = ""; sub g { $_ } $s .= g() for sort keys %m; return $s } print f(), "\n";},
      'an element of a sorted list, read across a call' ],
    # A FRESH {...} (B::SoN folds `my $h = {...}` to it) is a hash reference.
    [ q{sub f { my $h = {a => 1}; my $k = join ",", sort keys %$h; $h->{b} = 2; return $k } print f(), "\n";},
      'the keys of a fresh {...}, read across a store into it' ],
) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

# A LIST'S ELEMENT WRITTEN -- grep's $_ over an array slice is the array's
# own element -- is no copy's: refused, never stored into a copy of it.
for my $src (q{my @a = (1, 2, 3); my @g = grep { $_ = 9 } @a[0, 1]; print "@a|@g\n";}) {
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "a write through grep's \$_ over a slice: no wrong answer" or diag explain $r;
}

done_testing;
