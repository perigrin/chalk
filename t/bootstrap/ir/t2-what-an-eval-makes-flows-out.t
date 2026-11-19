# ABOUTME: What an eval's (or a try's) body made, seen after it: a variable it stored,
# ABOUTME: the try's own value nothing reads, an eval's value in list context -- as perl, through T2.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Harness::T2Case;
use File::Temp qw(tempfile);

sub perl_says ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return scalar qx($^X $pl 2>/dev/null);
}

my $G = q{use v5.42; no warnings; sub g { die "no\n" if $_[0] == 3; return $_[0] * 2 } };
for my $src (
    # a variable the try stored, read after it (its read in the body was
    # made again at a later store: "a value an eval made, read past its end")
    $G . q{my $c; try { $c = g(1) } catch ($e) { print "c\n" } print "$c\n";},
    $G . q{my $c = 7; try { $c = g(3) } catch ($e) { print "caught $e" } print "$c\n";},
    # in a loop, the catch leaving it, or going on
    $G . q{sub f { my @out; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { last } push @out, $c } return "@out" } print f(1, 2, 3, 4), "\n";},
    $G . q{my $c; try { $c = g(2) } catch ($e) { print "x" } try { $c .= g(3) } catch ($e) { print "y $e" } print "$c\n";},
    # AN EVAL IN LIST CONTEXT: its body's list, or the empty list on a die
    q{my @r = eval { sort { die "boom\n" if $a == 2; $a <=> $b } 3, 1, 2 }; print scalar(@r), "[@r] $@";},
    q{my @r = eval { sort { $a <=> $b } 3, 1, 2 }; print scalar(@r), "[@r] [$@]\n";},
    q{sub g { die "g\n" if $_[0]; return (1, 2) } my @r = eval { g(1) }; my @s = eval { g(0) }; print scalar(@r), " ", scalar(@s), " [@s] $@";},
    # ... and in the caller's: a sub's eval, called for a list and a scalar
    q{sub w { return eval { die "x\n" if $_[0]; 5 } } my @r = w(1); my $s = w(1); print scalar(@r), " ", defined $s ? "d" : "u", " ", w(0), "\n";},
    # (scalar: undef on a die)
    q{sub w { my $v = eval { die "x\n" if $_[0]; 5 }; return $v } my @r = w(1); print scalar(@r), " ", defined $r[0] ? "d" : "u", "\n";},
) {
    my $r = Chalk::CodeGen::Harness::T2Case::run_case({ src => $src, want => perl_says($src) });
    is($r->{verdict}, 'SAME', $src) or diag( $r->{why} // "got: $r->{got}" );
}

# Perl's answer, or refused by name -- never another answer.
for my $src (
    # the try's own value (its last statement's), merged with the catch's
    # where the catch falls through: the body's value does not reach that
    # merge past a die (T2 refuses it: a value an eval made, read past its end)
    $G . q{sub f { my @out; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { print "x" } push @out, $c } return "@out" } print f(1, 2, 3, 4), "\n";},
    # a list-context eval B::SoN types a scalar (Maybe[Int]): its die's empty
    # list is no element of @r
    q{my @r = eval { die "boom\n" if @ARGV == 0; 7 }; print scalar(@r), " $@";},
    q{my @r = eval { die "boom\n" if @ARGV; 7 }; print scalar(@r), " [@r]\n";},
    # a caller's-context eval whose body leaves a list of two (B::SoN skips w)
    q{sub w { return eval { die "x\n" if $_[0]; (5, 6) } } my @r = w(1); my @t = w(0); my $s = w(0); print scalar(@r), " [@t] $s\n";},
) {
    my $r = Chalk::CodeGen::Harness::T2Case::run_case({ src => $src, want => perl_says($src) });
    ok($r->{verdict} eq 'SAME' || $r->{verdict} eq 'REFUSED', $src) or diag( $r->{why} // "got: $r->{got}" );
}

done_testing;
