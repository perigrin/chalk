# ABOUTME: `my ($f, @rest) = LIST`, `my ($k, %h) = LIST` through T2: the scalars by place,
# ABOUTME: the array or hash the rest. One B::SoN leaves off the chain is refused by name.
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
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# ON THE CHAIN (B::SoN pins the assign and makes it the memory its reads take):
# as perl.
my %same = (
    'from a call'            => 'sub f { return (1, 2, 3) } my ($f, @rest) = f(); print "$f|@rest\n";',
    'a call doing work'      => 'sub g { my $n = shift; return ($n, $n * 2, $n * 3) } my ($x, @r) = g(2); print "$x|@r\n";',
    'fewer values'           => 'sub g { return (1) } my ($a, $b, @r) = g(); print defined $b ? "d" : "u", "|", scalar(@r), "|@r\n";',
    'more values'            => 'sub g { return (1, 2, 3, 4, 5) } my ($a, $b, @r) = g(); print "$a $b|@r\n";',
    'a target after it'      => 'sub g { return (1, 2, 3) } my ($x, @r, $z) = g(); print "$x|@r|", defined $z ? "d" : "u", "\n";',
    'a hash from a call'     => 'sub g { return ("x", "a", 1) } my ($k, %h) = g(); print "$k $h{a}\n";',
    'from a slice'           => 'my @s = (7, 8, 9, 10); my ($x, @r) = @s[1 .. 3]; print "$x|@r\n";',
    'in a loop'              => 'for my $i (1 .. 3) { my ($x, @r) = ($i, $i + 1, $i + 2); print "$x|@r\n"; }',
    'written after'          => 'sub g { return (1, 2, 3) } my ($x, @r) = g(); push @r, 9; print "$x|@r|", scalar(@r), "\n";',
    'elements read'          => 'sub g { return (1, 2, 3) } my ($x, @r) = g(); print "$r[0] $r[1] $#r\n";',
    'in scalar context'      => 'sub g { return (1, 2, 3) } my $n = (my ($x, @r) = g()); print "$n $x @r\n";',
    'in a branch, by a call' => 'sub g { return (1, 2, 3) } if (!@ARGV) { my ($x, @r) = g(); print "$x|@r\n" } else { print "no\n" }',
    'an odd list into a hash' => 'sub g { return ("x", "a", 1, "b") } my ($k, %h) = g(); print "$k $h{a} ", defined $h{b} ? "d" : "u", exists $h{b} ? "e" : "n", "\n";',
    'an even one, warnings on' => 'use warnings; sub g { return ("x", "a", 1, "b", 2) } my ($k, %h) = g(); print "$k $h{a} $h{b}\n";',
    'the hash then read whole' => 'sub g { return ("x", "a", 1, "b", 2) } my ($k, %h) = g(); delete $h{a}; print join(",", sort keys %h), " ", scalar(keys %h), "\n";',
    'a list with a call in it' => 'sub g { return (1, 2) } my ($x, @r) = (g(), 9); print "$x|@r\n";',
    'a hash after two scalars, an array after it' => 'sub g { return (1, 2) } my ($x, $y, %h, @z) = (g(), "k", "v"); print "$x $y $h{k} ", scalar(@z), "\n";',
    'one array alone'        => 'my (@a) = ($ENV{A} // 1, 2, 3); print "@a\n";',
);

# WHERE B::SoN LEAVES IT OFF THE CHAIN (a list of known places: 2026-11-18) the
# array was never filled -- "1|" for "1|2 3". As perl once B::SoN places it;
# until then refused by name, never a wrong answer.
my %placed_or_refused = (
    'a literal list'         => 'my ($f, @rest) = ($ENV{F} // 1, 2, 3); print "$f|@rest\n";',
    'a hash, a literal list' => 'my ($k, %h) = ("x", a => $ENV{F} // 1); print "$k $h{a}\n";',
    'from an array'          => 'my @s = ($ENV{F} // 7, 8, 9); my ($x, @r) = @s; print "$x|@r\n";',
    'more values, literal'   => 'my ($a, $b, @r) = ($ENV{F} // 1, 2, 3, 4, 5); print "$a $b|@r\n";',
    'in a branch'            => 'if (!@ARGV) { my ($x, @r) = ($ENV{F} // 1, 2, 3); print "$x|@r\n" } else { print "no\n" }',
    'declared earlier'       => 'sub g { return (1, 2, 3) } my ($x, @r); ($x, @r) = g(); print "$x|@r\n"; ($x, @r) = (4, 5); print "$x|@r\n";',
    # (its reads stayed the first list's: "9 9")
    'a variable bound as a value' => 'sub g { return (1, 2, 3) } my @r = (9, 9); my $x; ($x, @r) = g(); print "@r\n";',
    # (B::SoN binds the first scalar to the array itself: "2 " for "2 3", and
    # the count after a pop -- wrong before this file, with no array target)
    'scalars from an array in memory' => 'my @r; push @r, 2, 3; my ($f) = @r; my $l = pop @r; print "$f $l\n";',
    'scalars from one, in a loop' => 'my @r; push @r, 2, 3; for my $i (1) { my ($f, $s) = @r; print "$f $s\n" }',
    'scalars from a filled one' => 'sub g { return (1, 2, 3) } my ($x, @r) = g(); my ($f, $s) = @r; print "$f $s\n";',
    'scalar context, literal' => 'my $n = (my ($x, @r) = ($ENV{F} // 1, 2, 3)); print "$n $x @r\n";',
);

for my $name (sort keys %same) {
    my $r = tap("$same{$name}\n");
    is $r->{verdict}, 'SAME', "as perl through T2: $name" or diag $r->{why} // explain $r;
}
for my $name (sort keys %placed_or_refused) {
    my $r = tap("$placed_or_refused{$name}\n");
    ok $r->{verdict} eq 'SAME'
        || $r->{verdict} eq 'REFUSED' && ( $r->{why} // '' ) =~ /a list assignment (?:to an array or hash|into scalars from an array or hash kept in memory)/,
        "as perl, or refused by name: $name" or diag explain $r;
}

# AN ODD LIST INTO A HASH WHERE WARNINGS ARE ON: perl warns (and gives undef);
# chalk raises none of perl's warnings, so it stops there, saying so.
{
    my $r = tap(qq{use warnings;\nsub g { return ("x", "a", 1, "b") }\nmy (\$k, %h) = g();\nprint "\$k\\n";\n});
    like $r->{perl}{err}, qr/\AOdd number of elements in hash assignment/, 'perl warns of an odd list into a hash';
    like $r->{llvm}{err} // $r->{why}, qr/an odd number of elements in a hash assignment \(perl warns\): stopped/, '... T2 stops there, by name';
    is $r->{llvm}{out} // '', '', '... printing nothing after it';
}

# A REFERENCE TO THE ARRAY KEPT PAST A LOOP'S PASS: perl's `my` is a new array
# each pass, which the wire does not say -- refused, not one array for all.
{
    my $r = tap('sub g { my $n = shift; return ($n, $n * 2) } my @all; for my $i (1 .. 3) { my ($x, @r) = g($i); push @all, \@r } print "$all[0][0] $all[2][0]\n";' . "\n");
    ok $r->{verdict} eq 'SAME' || $r->{verdict} eq 'REFUSED' && $r->{why} =~ /a list assignment to an array or hash a reference is taken of, in a loop/,
        'a reference to a loop body\'s array: as perl, or refused by name' or diag explain $r;
}

done_testing;
