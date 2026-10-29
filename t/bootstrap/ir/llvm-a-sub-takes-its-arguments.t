# ABOUTME: An inlined sub binds every argument it reads -- by shift, by $_[N], by my (...) = @_:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or refused by name.
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

# THE INLINER BOUND ONE ARGUMENT. Two shifts were said to hash-cons and lose
# their order -- they do not: each is threaded on the one before through its
# memory input, which IS their order. `my (...) = @_` was refused outright
# (56 pvm corpus cases, "callee accesses @_ as an aggregate").
for my $case (
    [ q{sub f { my $a = shift; my $b = shift; return $a - $b } print f(10, 3), "\n";}, "7\n", 'two shifts' ],
    [ q{sub f { my $a = shift; my $b = shift; my $c = shift; return $a * 100 + $b * 10 + $c } print f(1, 2, 3), "\n";}, "123\n", 'three shifts' ],
    [ q{sub f { my ($a, $b) = @_; return $a - $b } print f(10, 3), "\n";}, "7\n", 'my ($a, $b) = @_' ],
    [ q{sub f { my ($s, $n) = @_; return "$s=$n" } print f("x", "4"), " ", f("y", "5"), "\n";}, "x=4 y=5\n", 'my (...) = @_, twice, strings' ],
    [ q{sub f { return $_[0] - $_[1] } print f(10, 3), "\n";}, "7\n", '$_[0] and $_[1]' ],
    [ q{sub f { my ($a, $b) = @_; if ($a > $b) { print "gt " } return $a + $b } print f(5, 2), "\n";}, "gt 7\n", 'my (...) = @_ in a branching callee' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A SLURPY TARGET OR A HOLE IS NOT A POSITION, and is refused by name.
for my $case (
    [ q{sub f { my ($a, @rest) = @_; return $a + scalar(@rest) } print f(1, 2, 3), "\n";}, "3\n", 'a slurpy array target' ],
    [ q{sub f { return $_[1] } print f(1, 2), "\n";}, "2\n", 'a $_[1] with no $_[0]' ],
    # AN ARRAY, A HASH OR A LIST PASSED FLATTENS into @_: read by position,
    # bound as one argument, the later positions were undef (1 for perl's 3).
    [ q{sub f { my ($c, $a) = @_; return $a + 1 } my @x = (1, 2, 3); print f(@x), "\n";}, "3\n", 'an array passed, read by my (...) = @_' ],
    [ q{sub g { return (1, 2, 3) } sub f { my ($c, $a) = @_; return $a + 1 } print f(g()), "\n";}, "3\n", 'a list a call returns, passed' ],
    [ q{sub f { return $_[1] + 1 } my %h = (a => 1); my @x = (1, 2, 3); print f(@x), f(%h), "\n";}, "32\n", 'an array and a hash passed, read by $_[N]' ],
    # An Int bound to a Str-stamped parameter would be stringified, and a
    # later numeric read of it would not give the Int back past 2**53.
    [ q{sub f { my ($s, $n) = @_; return "$s=$n" } print f("x", 4), "\n";}, "x=4\n", 'an Int argument read as a Str' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, $want, "$name: perl's answer") }
    else { like($@, qr/^(?:load|lower): .*GAP/, "$name: refused, naming why") or diag $@ }
}

# A slurpy hash takes the pairs after the scalars (pvm 068 127): lowered.
# ...and @_ read only as a list is the arguments flattened: an array passed
# is its elements (pvm 112, whose map aliases $_ to them and only reads it).
for my $case (
    [ q{sub n { return scalar(@_) } my @a = (1, 2, 3); print n(@a, 9), "\n";}, "4\n", '@_ counted, an array passed' ],
    [ q{sub j { return join ",", @_ } my @a = ("x", "y"); print j(0, @a), "\n";}, "0,x,y\n", '@_ joined, an array passed' ],
    [ q{use v5.36; my sub c ($s) { $s =~ s/1/9/; "[$s]" } sub e { join ",", map { c($_) } @_ } my @a = ("a1", "b1"); print e(@a), " @a\n";}, "[a9],[b9] a1 b1\n", 'a map over @_ that only reads its $_' ],
    [ q{sub f { my ($c, %o) = @_; return "$c:$o{ix}:" . join(",", sort keys %o) } print f("m", ix => 3, k => 4), "\n";}, "m:3:ix,k\n", 'a slurpy hash target' ],
    [ q{sub new { my ($c, %o) = @_; return $o{ix} } my @a = (1, 2, 3); print main->new(ix => scalar(@a)), "\n";}, "3\n", 'a slurpy hash in a class method' ],
    # A package new's blessed hash, passed on as $self: an Object to B::SoN,
    # the hash reference it is (pvm 208 224).
    [ q{package C; sub new { bless {}, shift } sub g { "g$_[1]" } sub f { my ($self, $x) = @_; return $self->g($x) } package main; print C->new->f(7), "\n";}, "g7\n", 'a blessed hash passed as $self' ],
    # A hash passed to a sub that never reads @_: nothing to flatten into.
    [ q{sub g { 1 } my %h = (a => 1); g(%h); print "$h{a}\n";}, "1\n", 'a hash passed to a sub reading no arguments' ],
) {
    my ($src, $want, $name) = @$case;
    is(eval { through_llvm($src) }, $want, "$name: perl's answer") or diag $@;
}

done_testing;
