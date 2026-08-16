#!/usr/bin/env perl
# ABOUTME: A post-merge read must not be emitted inside a branch arm.
# ABOUTME: Pins the mod-elem miscompile end-to-end, from real producer output.

use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use File::Temp qw(tempfile);

use Chalk::CodeGen::Harness::ProgramRunner;

# ---------------------------------------------------------------------------
# THE MISCOMPILE, measured 2026-08-16 on chalk a1338ec4:
#
#   my @a = (1);
#   my $c = 0;
#   if (1) { $a[0] = 9 if $c; }
#   print $a[0], "\n";
#
#     perl : stdout "1\n"  exit 0
#     chalk: stdout ""     exit 0     <- the print is DROPPED, silently
#
# Exit status matches and no GAP is raised, so nothing flags it.
#
# The producer graph is CORRECT -- verified by walking it:
#   Return#10 -> Print#9 -> Region#7,  and Print#9.control_in = Region#7.
# The Print hangs off the MERGE region, exactly where it belongs.
#
# The backend drops it. _collect_branch_body(Proj) reaches the post-merge
# Subscript through DATA edges (the store's memory Phi), sweeps it into the
# taken arm, and the whole read + Stringify + Print expansion is emitted
# starting inside `if.then.1`. With the guard false, control goes to
# `if.else.2` and none of it runs.
#
# WHY THIS TEST DRIVES THE REAL PRODUCER rather than building the graph by
# hand: a hand-built approximation of this shape does NOT reproduce the bug.
# The first draft of this file constructed what looked like the same graph and
# the read landed in `entry` -- a false GREEN. The defect depends on how the
# producer actually wires the memory Phi and the arm's Region, which is a
# detail the reconstruction got wrong. Behaviour against perl is the contract
# that matters, so that is what is asserted.
#
# BILATERAL BY CONSTRUCTION: both polarities are checked. The $c = 1 case
# PASSES today; only the pair discriminates. A single-polarity test would show
# green while the miscompile stands.
# ---------------------------------------------------------------------------

my %CASES = (
    'guard FALSE (the miscompile)' => <<'PERL',
my @a = (1);
my $c = 0;
if (1) { $a[0] = 9 if $c; }
print $a[0], "\n";
PERL
    'guard TRUE (passes today; the polarity that hides it)' => <<'PERL',
my @a = (1);
my $c = 1;
if (1) { $a[0] = 9 if $c; }
print $a[0], "\n";
PERL
);

for my $name (sort keys %CASES) {
    subtest $name => sub {
        my ($fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
        print $fh $CASES{$name};
        close $fh;

        my $r = Chalk::CodeGen::Harness::ProgramRunner->run_file($path);

        # A SKIP would mean the producer stopped emitting this shape. That is
        # not a pass: this test exists to pin a miscompile, and a case that no
        # longer compiles cannot demonstrate the fix.
        isnt $r->{verdict}, 'SKIP',
            'the case still compiles (a GAP here would make this test vacuous)'
            or diag 'skip_reason: ' . ($r->{skip_reason} // '?');

        is $r->{verdict}, 'PASS',
            'stdout and exit status both match perl'
            or diag sprintf("perl: %s (exit %s)\nchalk: %s (exit %s)",
                _show($r->{perl_stdout}), $r->{perl_exit} // '?',
                _show($r->{lli_stdout}),  $r->{lli_exit}  // '?');
    };
}

sub _show ($s) {
    my $t = $s // '';
    $t =~ s/\n/\\n/g;
    return "'$t'";
}

done_testing;
