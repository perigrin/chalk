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
    # An Int bound to a Str-stamped parameter would be stringified, and a
    # later numeric read of it would not give the Int back past 2**53.
    [ q{sub f { my ($s, $n) = @_; return "$s=$n" } print f("x", 4), "\n";}, "x=4\n", 'an Int argument read as a Str' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, $want, "$name: perl's answer") }
    else { like($@, qr/^(?:load|lower): .*GAP/, "$name: refused, naming why") or diag $@ }
}

done_testing;
