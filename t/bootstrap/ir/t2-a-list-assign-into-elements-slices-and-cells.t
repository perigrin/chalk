# ABOUTME: A placed list assign whose targets are elements, slices or captured variables, through
# ABOUTME: T2: the list made first, then each place stored, in order. Perl's answer, or refused by name.
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

# B::SoN PLACES THE ASSIGN (its `placement`: by where each target lives) and
# names each target by the node that is its place: a Subscript, a Slice, a
# captured variable's cell. Perl makes the whole list, then stores.
my %same = (
    # elements
    'a swap of two elements (swap1)'          => 'my @a = (1,2); ($a[0], $a[1]) = ($a[1], $a[0]); print "@a\n";',
    'a swap of two hash elements (swap3)'     => 'my %h = (a=>1, b=>2); ($h{a}, $h{b}) = ($h{b}, $h{a}); print "$h{a} $h{b}\n";',
    'elements through a reference (la2)'      => 'my $r = [0,0]; ($r->[0], $r->[1]) = (3,4); print "@$r\n";',
    'elements of a package array (la3)'       => 'our @g = (0,0); ($g[0], $g[1]) = (3,4); print "@g\n";',
    'one element, its count taken (la4)'      => 'my @a = (0); my $n = (($a[0]) = (5,6,7)); print "$a[0] $n\n";',
    'a hash element by a key in a variable (la5)' => 'my %h; my ($k, $v) = ("a", 1); ($h{$k}) = ($v); print "$h{a}\n";',
    'indices that count up (la6)'             => 'my @a = (0,0); my $i = 0; ($a[$i++], $a[$i++]) = (8,9); print "@a $i\n";',
    'an element and a scalar (m4)'            => 'my %h; my $c; ($h{k}, $c) = (9, 10); print "$h{k} $c\n";',
    'an element and a scalar (la33)'          => 'my @a=(0); my $c; ($a[0], $c) = (5,6); print "$a[0] $c\n";',
    'fewer values than elements'              => 'my @a = (1,2,3); ($a[0], $a[1], $a[2]) = (7); print defined $a[1] ? "d" : "u", " $a[0] ", scalar(@a), "\n";',
    'an element past the end'                 => 'my @a = (1); ($a[3], $a[1]) = (7, 8); print scalar(@a), " $a[1] $a[3]\n";',
    'in an arm not taken (wa21)'              => 'my @a = (1,2,3); my $x = $a[0] + $a[1]; ($a[0], $a[1]) = (10, 20) if @ARGV; $a[2] = $x; print "@a\n";',
    'in an arm taken'                         => 'my @a = (1,2,3); my $x = $a[0] + $a[1]; ($a[0], $a[1]) = (10, 20) unless @ARGV; $a[2] = $x; print "@a\n";',
    'in a loop'                               => 'my @a = (1,2); for my $i (1 .. 3) { ($a[0], $a[1]) = ($a[1], $a[0] + $i) } print "@a\n";',
    'an element then the rest'                => 'my @a = (0); my @r; ($a[0], @r) = (1, 2, 3); print "$a[0]|@r\n";',
    # slices
    'a hash slice (slice1)'                   => 'my %h; @h{qw(a b)} = (1,2); print "$h{a} $h{b}\n";',
    'an array slice (slice2)'                 => 'my @a = (0,0,0); @a[0,1] = (5,6); print "@a\n";',
    'a slice swapped through scalars (wa18)'  => 'my @a = (1,2,3); my ($x, $y) = @a[0,1]; @a[0,1] = ($y, $x); print "@a\n";',
    'a slice from itself'                     => 'my @a = (1,2,3); @a[0,1] = @a[1,0]; print "@a\n";',
    'a scalar then a slice'                   => 'my @a = (0,0); my $z; ($z, @a[0,1]) = (1, 2, 3); print "@a $z\n";',
    'two scalars captured, declared together' => 'my ($x, $y) = (1, 2); my $g = sub { "$x$y" }; print $g->(), "\n";',
    'a slice of fewer values'                 => 'my %h = (a => 1, b => 2); @h{qw(a b)} = (9); print "$h{a} ", defined $h{b} ? "d" : "u", "\n";',
    # captured variables
    'a captured scalar (cl1)'                 => 'my $x = 1; my $g = sub { $x }; ($x) = (7); print $g->(), "\n";',
    'a captured scalar from an array (cl2)'   => 'my $x = 1; my $g = sub { $x }; my @l = (7, 8); ($x) = @l; print $g->(), "\n";',
    'two captured scalars swapped (cl11)'     => 'my ($x, $y) = (1, 2); my $g = sub { "$x$y" }; ($x, $y) = ($y, $x); print $g->(), "\n";',
    'a hash a closure reads (cl15)'           => 'my %h = (a => 1); my $g = sub { join ",", map { "$_$h{$_}" } sort keys %h }; $h{b} = 2; ($h{c}) = (3); print $g->(), "\n";',
    'a captured scalar and an array (cl21)'   => 'my $x = 1; my $g = sub { $x }; ($x, my @rest) = (5, 6); print $g->(), "\n";',
    'a captured scalar from a choice (cl25)'  => 'my $x = 5; my $g = sub { $x }; my $s = "v=5"; ($x) = $s =~ /(\d)/ ? 6 : 0; print $g->(), "\n";',
    'a captured scalar read after'            => 'my $x = 1; my $g = sub { $x * 2 }; ($x) = (7); print "$x ", $g->(), "\n";',
);

# WHAT T2 DOES NOT STORE YET is refused, each by its own name.
my %refused = (
    # (B::SoN binds $z to the 2: a slice is one place to it, two to perl)
    'a slice then a scalar'                     => [ 'my @a = (0,0); my $z; (@a[0,1], $z) = (1, 2, 3); print "@a $z\n";',
        qr/a list assignment to a slice and then another target/ ],
    'a slice by keys made at run time (slice3)' => [ 'my %h = (a=>0); my @k = ("a","b"); @h{@k} = (7,8); print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";',
        qr/a list assignment to a slice whose indices are a list made at run time/ ],
    'a slice by a range'                        => [ 'my @a = (0,0,0); my $n = @ARGV + 1; @a[0 .. $n] = (5,6); print "@a\n";',
        qr/a list assignment to a slice whose indices are a list made at run time/ ],
);

for my $name (sort keys %same) {
    my $r = tap("$same{$name}\n");
    is $r->{verdict}, 'SAME', "as perl through T2: $name" or diag $r->{why} // explain $r;
}
for my $name (sort keys %refused) {
    my ( $src, $why ) = $refused{$name}->@*;
    my $r = tap("$src\n");
    ok $r->{verdict} eq 'SAME' || $r->{verdict} eq 'REFUSED' && ( $r->{why} // '' ) =~ $why, "as perl, or refused by name: $name" or diag explain $r;
}

done_testing;
