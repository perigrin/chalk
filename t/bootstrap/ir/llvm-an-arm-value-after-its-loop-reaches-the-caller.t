# ABOUTME: A sub whose early return leaves the rest of it as an else arm returns what that
# ABOUTME: arm made after a loop in it: B::SoN -> chalk -> lli == perl.
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

# `if ($op) { return "early" } for (...) { push @chain, ... } return "@chain"`
# -- B::SoN makes the rest of the sub the else arm, so the loop and the
# join after it are in that arm, and the join reads the loop's exit memory
# Phi. A Phi of a Region a Loop heads, in an arm, is lowered with that loop
# in that arm: it was refused as "an inlined sub's value is made inside one
# of its arms" (pvm 069).
for my $case (
    [ q{sub walk { my ($op) = @_; my @chain; if ($op) { return "early" } for my $item (1, 2) { push @chain, $item } return "@chain"; } print walk(1), " | ", walk(0), "\n";}, "early | 1 2\n", 'a loop in the else arm' ],
    [ q{sub walk { my ($op, $items) = @_; my @chain; if ($op eq "If" || $op eq "S") { push @chain, $op; return "stopped at @chain" if $op eq "If"; } for my $item (@$items) { push @chain, $item } return "@chain"; } print walk("If", [1]), " | ", walk("S", [2, 3]), " | ", walk("X", [4]), "\n";}, "stopped at If | S 2 3 | 4\n", 'pvm 069' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
