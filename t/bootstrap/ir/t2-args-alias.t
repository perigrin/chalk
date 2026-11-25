# ABOUTME: @_ aliases the caller's arguments, as perl's: a write to $_[N] is the caller's
# ABOUTME: variable or element, a read of @_ sees it now -- through T2 alone, against perl.
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

# Each program T2 lowers alone and runs as perl does (out, err, exit).
for my $src (
    # A `my` scalar: $_[N] is the variable itself.
    q{sub bump { $_[0]++ } my $x = 1; bump($x); print "$x\n";},
    q{sub bump_alias { $_[0]++ } sub bump_copy { my ($n) = @_; $n++ } my ($a, $u) = (1, 1); bump_alias($a); bump_copy($u); print "$a $u\n";},
    q{sub two { $_[1] = "b" } my ($p, $q) = ("x", "y"); two($p, $q); print "$p$q\n";},
    # A temporary is a fresh value the callee may write; the caller's is untouched.
    q{sub g { $_[0] = 9; return $_[0] + 1 } my $x = 1; print g($x + 1), " $x\n";},
    # An element: of a `my` array, of a `my` hash, through a reference.
    q{sub g { $_[0] = 5 } my @a = (1, 2); g($a[1]); my %h = (k => 1); g($h{k}); print "@a $h{k}\n";},
    q{sub g { $_[0] = 5 } my $r = { k => 1 }; g($r->{k}); g($r->{n}); print join(",", map {"$_=$r->{$_}"} sort keys %$r), "\n";},
    q{sub g { $_[0] .= "!" } my $r = [1, 2]; g($r->[0]); print "@$r\n";},
    # A package scalar.
    q{our $g = 1; sub b { $_[0] += 10 } b($g); print "$g\n";},
    # A foreach alias handed on, and $_ over an array.
    q{sub bump { $_[0]++ } my @a = (1, 2); for my $x (@a) { bump($x) } print "@a\n";},
    q{sub g { $_[0] = $_[0] * 10 } my @n = (1, 2); g($_) for @n; print "@n\n";},
    # An array passed whole: each element aliased.
    q{sub dbl { $_[$_] *= 2 for 0 .. $#_ } my @a = (1, 2, 3); dbl(@a); print "@a\n";},
    q{sub dbl { my $i = 0; while ($i < @_) { $_[$i] *= 2; $i++ } } my @a = (1, 2); my $r = [5]; dbl(@a, @$r); print "@a @$r\n";},
    q{sub z { $_[1] = 0 } my @a = (1, 2, 3); my $s = 7; z($s, @a); print "$s @a\n";},
    # A slice, and a list written out: each element its item's own.
    q{sub g { $_[0] = 5 } my @n = (1, 2, 3); g($n[0]); g($_) for @n[1 .. 2]; print "@n\n";},
    q{sub g { $_[0] .= "!" } my %h = (a => 1, b => 2); g($_) for @h{qw(a b)}; print "$h{a} $h{b}\n";},
    q{sub g { $_[1] = 0 } my @n = (1, 2, 3); g($n[2]); g(@n[0, 1]); print "@n\n";},
    # A named array made from a list is its own (`my @n = sort ...`).
    q{package O { sub m { $_[1] = uc $_[1] if $_[1] eq "b" } } my @n = sort qw(c b a); for my $x (@n) { O->m($x) } print "@n\n";},
    # `&f;` shares the caller's @_: at the top, an empty one; read by no
    # one, nothing. $_[N] handed to a sub with a signature: its copy.
    q{sub answer { 42 } sub n { scalar(@_) } print &answer, &n, "\n";},
    q{use v5.36; sub bump { $_[0]++ } sub pick ($n) { "<$n>" } my $f = sub { pick($_[0]) . &pick($_[1]) }; my $s = 0; bump($s); print $f->(5, 6), $s, "\n";},
    # A method call: the invocant is $_[0], the rest the caller's.
    q{package O { sub new { bless {}, shift } sub m { $_[1] = 9 } } my $o = O->new; my $x = 1; $o->m($x); print "$x\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

# A READ OF @_ AFTER THE CALLEE STORED THE VARIABLE IT WAS HANDED: B::SoN's
# wire carries the argument as a value read before the call, and T2 read it
# again by its own rule -- right, against what the wire says. The loader
# holds the wire to L11 (SoN::Verify's V12) now and refuses it by name (third
# final audit, risk 5): it was SAME here.
{
    my $src = q{our $g = 1; sub f { $g = 2; return "@_" } print f($g), "\n";};
    my $r = tap("$src\n");
    is $r->{verdict}, 'REFUSED', "$src: refused" or diag $r->{why} // explain $r;
    like $r->{why} // '', qr/wire invariant L11/, '...by L11';
}

# NEVER A WRONG ANSWER: an array B::SoN folds to what it was made with (a
# slice of it handed to a call versions nothing), where a sub writes @_.
for my $src (
    q{sub g { $_[0] = 5 } my @n = (1, 2, 3); g($_) for @n[1 .. 2]; print "@n\n";},
    q{sub g { $_[1] = 0 } my @n = (1, 2, 3); g(@n[0, 1]); print "@n\n";},
) {
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "$src: no wrong answer" or diag explain $r;
}

# A LITERAL IS READ-ONLY: perl dies, and so does the program, before the
# print. (B::SoN gives an element store no site yet: the message is perl's
# without its " at FILE line N".)
{
    my $r = tap(qq{sub g { \$_[0] = 5 } g(3); print "x\\n";\n});
    ok $r->{llvm}, 'a store into a literal: lowered by T2' or diag $r->{why};
    is $r->{llvm}{out}, $r->{perl}{out}, 'a store into a literal: nothing printed after';
    is $r->{llvm}{exit}, $r->{perl}{exit}, "a store into a literal: perl's exit";
    like $r->{llvm}{err}, qr/\AModification of a read-only value attempted\b/, "a store into a literal: perl's message";
}

done_testing;
