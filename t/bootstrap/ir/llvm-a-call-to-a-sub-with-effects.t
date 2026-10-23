# ABOUTME: A direct call to a sub whose body branches, loops or stores is inlined whole:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or refused for a narrower reason.
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

# THE INLINER TOOK A STRAIGHT LINE OF PRINTS AND NOTHING ELSE. A callee with
# an if, a loop or a store on its control chain was refused -- 106 pvm corpus
# cases ("callee has effect(s) on its control chain"). The callee's control
# structure is lowered in place, as a method body's is.
my $EFFECT_GAP = qr/callee has effect\(s\) on its control/;

# THESE MUST GIVE PERL'S ANSWER -- a refusal is a regression, so none is
# accepted here.
for my $case (
    [ q{sub f { my $n = shift; if ($n > 1) { print "big " } print "$n\n"; return 0 } f(1); f(2);}, "1\nbig 2\n", 'an effect in an if arm' ],
    [ q{sub f { my $n = shift; for my $i (1 .. $n) { print $i } print "\n"; return 0 } f(2); f(3);}, "12\n123\n", 'an effect in a loop' ],
    [ q{sub f { my $n = shift; my $m = $n; $m = $m * 2; return $m } print f(2) + f(5), "\n";}, "14\n", 'a store, the value used' ],
    # A shift read only by an if's condition: Graph::nodes never held it, and
    # the call was refused for reading 0 arguments.
    [ q{sub f { my $n = shift; if ($n) { print "y" } else { print "n" } return 1 } f(1); f(0); f(1); print "\n";}, "yny\n", 'three calls in sequence' ],
    # ONE GRAPH'S NODES ARE ITS OWN (review of 4e1e9969). The coercion passes
    # minted every graph's Coerce from one factory, so f's Coerce(shift) and
    # main's Coerce(g(5)) hashed to one node: f tested g's value, and printed
    # F for perl's nothing -- or called itself "recursive".
    [ q{sub f { my $n = shift; if ($n > 1) { print "F" } return 0 } sub g { my $n = shift; return $n } my $x = g(5) + 1; f(1); print "$x\n";}, "6\n", 'a callee beside another call' ],
    [ q{sub h { my $k = shift; foreach my $i (1) { print "h" } return $k } sub f { my $n = shift; if ($n > 1) { print "b" } return $n } print h(1) + f(2), "\n";}, "hb3\n", 'two callees in one expression' ],
    [ q{sub f { my $n = shift; if ($n > 2) { print "b" } return $n } print f(2) + f(3), "\n";}, "b5\n", 'one callee twice in an expression' ],
    # A CALL IS LOWERED ONCE. A straight-line callee drove its effects under a
    # fresh cache and lowered its value under the caller's, so a call reached
    # from both ran twice.
    [ q{sub f { if ($_[0]) { print "x\n" } return 1 } sub g { return 5 + f(1) } print g(), "\n";}, "x\n6\n", 'a branching callee under a straight-line one' ],
    [ q{sub h { print "H"; return 1 } sub g { my @l = (5, 6); return $l[h()] + $_[0] } print g(1), "\n";}, "H7\n", 'an effectful call in a straight-line value' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# THESE MAY BE REFUSED, by name, for what they are -- never for having
# effects, and never answered wrongly.
for my $case (
    [ q{sub g { my $n = shift; if ($n > 2) { print "g" } return $n + 1 } sub f { my $n = shift; print "f"; return g($n) * 2 } print f(1), " ", f(5), "\n";}, "f4 gf12\n", 'nested calls' ],
    [ q{sub classify { return "zero" if $_[0] == 0; return "negative" if $_[0] < 0; return "positive"; } print classify(0), " ", classify(-5), " ", classify(7), "\n";}, "zero negative positive\n", 'early returns (pvm arguments.md)' ],
    [ q{sub big { my ($k) = @_; return "big" if $k > 1 } print "[", big(5), "]\n";}, "[big]\n", 'an early return with no else (pvm chalk-found-gaps.md)' ],
    # A VALUE NOTHING TYPED IS NOT AN EMPTY STRING. The rebind folds to a
    # ternary stamped Unknown, and stringifying Unknown printed "" for 9.
    [ q{sub f { my $n = shift; my $y = $n; if ($n) { $y = 9 } return $y } print f(1), "\n";}, "9\n", 'a rebind under a branch, returned' ],
    # AN IF AS THE LAST STATEMENT IS THE SUB'S VALUE, and its arm's print was
    # served past the merge: lli rejected the module.
    [ q{sub f { my $n = shift; if ($n) { print "x" } } f(1); print "\n";}, "x\n", 'an if as the last statement' ],
    [ q{sub f { my $n = shift; if ($n) { print "x" } else { print "y" } } f(1); f(0); print "\n";}, "xy\n", 'an if/else as the last statement' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, $want, "$name: perl's answer") }
    else {
        like($@, qr/^(?:load|lower): .*(?:GAP|LLVM backend:)/, "$name: refused, naming why") or diag $@;
        unlike($@, $EFFECT_GAP, "$name: not refused for having effects") or diag $@;
    }
}

done_testing;
