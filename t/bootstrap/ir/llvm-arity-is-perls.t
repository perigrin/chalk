# ABOUTME: A call may pass fewer or more arguments than its callee reads: a missing one
# ABOUTME: is undef, or its signature default; extras are ignored -- B::SoN -> chalk -> lli.
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

# ARITY IS PERL'S, NOT AN EXACT MATCH. A sub reading more arguments than
# the call passes sees undef for the rest; one reading fewer ignores the
# rest; a signature's `$b = 3` supplies its default. All were refused as an
# "arity mismatch" (5 pvm cases). A signature called with too few or too
# many dies in perl, and is refused by name here.
for my $case (
    [ q{use v5.36; sub add_up ($a, $b = 3) { $a + $b } print add_up(1), " ", add_up(1, 10), "\n";}, "4 11\n", 'a signature default' ],
    [ q{use v5.36; sub g ($k, $x) { $k ? 1 : 2 } print g(1, "X"), g(0, "Y"), "\n";}, "12\n", 'a parameter never read' ],
    [ q{sub f { my ($a, $b) = @_; defined $b ? "d" : "u" } print f(1), "\n";}, "u\n", 'a list assignment short of arguments' ],
    [ q{sub f { my $a = shift; my $b = shift; return defined $b ? "d$b" : "u" } print f(1), f(1, 2), "\n";}, "ud2\n", 'a shift with nothing left' ],
    [ q{sub f { $_[0] + 1 } print f(1, 2, 3), "\n";}, "2\n", 'extras ignored' ],
    [ q{use v5.42; my $g = sub ($x, $y) { $x + $y }; print $g->(2, 1), "\n";}, "3\n", 'the signature of an anonymous sub, whose declared list is not on the wire' ],
    [ q{sub f { my ($s, @r) = @_; return scalar(@r) . ":" . join(",", @r) . ":" . ($r[1] // "u") } print f(1), "|", f(1, 2, 3), "\n";}, "0::u|2:2,3:3\n", 'a slurpy array takes the rest' ],
    [ q{use v5.36; package Optimizer { sub collapse ($, $phi) { return "c$phi" } } print Optimizer->collapse("x"), "\n";}, "cx\n", 'an unnamed signature parameter (pvm)' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

for my $case (
    [ q{use v5.36; sub g ($k) { $k } print g(1, 2), "\n";}, 'too many for a signature' ],
    [ q{use v5.36; sub g ($k, $j) { $k } print g(1), "\n";}, 'too few for a signature' ],
) {
    my ($src, $name) = @$case;
    my $err = do { local $@; eval { through_llvm($src) }; $@ };
    like($err, qr/GAP: .*signature/, "$name: refused by name (perl dies)");
}

# `&name` WITH NO PARENS SHARES THE CALLER'S @_ (the wire says shares_args).
# Taken for a call passing nothing, it answered "[]" where perl says "[1 2]"
# (pvm subroutines.md). It is the inlined caller's arguments.
my $amp = q{sub answer { "[@_]" } sub outer { print &answer, "\n" } outer(1, 2);};
is(eval { through_llvm($amp) }, "[1 2]\n", '&name shares its caller\'s @_') or diag $@;

done_testing;
