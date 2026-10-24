# ABOUTME: An array in a list flattens into it: each element its own slot, in order, a
# ABOUTME: reference staying one element -- B::SoN -> chalk -> lli == perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# A LIST FLATTENS ITS ARRAYS. `(0, @a, 3)` is four elements, not three with
# an array in the middle; building it boxed each input as one slot and
# refused an Array ("ArrayRef elem[N] has repr=Array", 9 pvm cases). It is
# appended instead, @a's elements one by one. A reference is a scalar and
# stays one element.
for my $case (
    [ q{my @a = (1, 2); my @b = (0, @a, 3); print scalar(@b), " @b\n";}, "4 0 1 2 3\n", 'an array between scalars' ],
    [ q{my @a = (1, 2); my @e = (); my @c = (@e, @a, @e, @a); print scalar(@c), " @c\n";}, "4 1 2 1 2\n", 'empty arrays, and one twice' ],
    [ q{my @a = ("x"); my $r = [9]; my @d = (@a, $r); print scalar(@d), " $d[0] ", ref($d[1]), "\n";}, "2 x ARRAY\n", 'a reference is one element' ],
    [ q{my %h = (a => 1); my @k = (sort(keys %h), "z"); print "@k\n";}, "a z\n", 'a sorted list in a list' ],
    [ q{my %h = (a => 1, b => 2); my @k = (sort(keys %h), "z"); print scalar(@k), " $k[1]\n";}, "3 b\n", 'counted and indexed' ],
    [ q{sub f { my ($h) = @_; my %p = %$h; for my $k (sort keys %p) { my $v = $p{$k}; $h->{$k} = $v + 10; print "$v $p{$k};" } return "" } print f({a=>1, b=>2}), "\n";}, "1 1;2 2;\n", 'a copy taken at entry, in a sub whose body is a loop (pvm)' ],
    [ q{use feature 'class'; no warnings 'experimental::class'; class Node { method parts { my @p; push @p, "a", "b"; return @p } method hash { return join("|", "op", $self->parts) } } print Node->new->hash, "\n";}, "op|a|b\n", 'a method joins a list holding what a call returns (pvm)' ],
    [ q{sub two { return (1, 2) } my @a = (0, two(), 3); print scalar(@a), " @a\n";}, "4 0 1 2 3\n", 'the list a sub returns' ],
    [ q{sub arr { my @p = ("x", "y"); return @p } sub one { return "z" } my @a = (arr(), one(), arr()); print "@a\n";}, "x y z x y\n", 'the array one sub returns and the scalar another does' ],
    [ q{sub f { (1,2,3) } sub g { () } my $c = () = f(); my $d = () = g(); print "$c $d\n";}, "3 0\n", 'an empty list returned is no element (pvm)' ],
    [ q{sub a { return } sub b { return undef } my @x = (a(), b(), a()); print scalar(@x), "\n";}, "1\n", 'a bare return is nothing, return undef is one' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
