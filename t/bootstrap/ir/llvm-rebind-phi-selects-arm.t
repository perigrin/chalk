#!/usr/bin/env perl
# ABOUTME: A value-Phi over a scope REBIND must select the arm's value, not the base.
# ABOUTME: Pins the defect the producer's 2b-3 refusal has been covering.

use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::Target::LLVM;

# ---------------------------------------------------------------------------
# THE DEFECT, measured 2026-08-17 (docs/plans/2026-08-17-step4-measured-2b3-is-
# load-bearing.md). With void-branch construction made unconditional and the
# producer's 2b-3 refusal disabled:
#
#     my $n = 5; my $x = 0;
#     $x = 1 if $n > 0;
#     print $x, "\n";
#
#     perl : "1\n"
#     chalk: "0\n"        <- the rebind does not take effect
#
# The Phi is PLACED correctly (chalk f2971b5f fixed that) and then selects the
# WRONG INCOMING VALUE: the base binding rather than the arm's.
#
# WHY THE EXISTING DIAMOND TEST DOES NOT CATCH IT.
# t/bootstrap/ir/llvm-empty-diamond-collapses.t builds a diamond whose arms are
# two INDEPENDENT constants, and its select assertion passes. This case differs
# in exactly one way that matters: the arm REBINDS A SLOT THAT ALREADY HAD A
# BINDING, so the two incoming values are base-vs-arm rather than
# constant-vs-constant. A fixture built from independent constants cannot
# discriminate a base/arm mix-up, because there is no base.
#
# This test is backend-only by necessity: reproducing it through the producer
# needs two probes that are deliberately not landing (unconditional
# construction, and the 2b-3 refusal disabled), so the durable form is a
# hand-built graph.
# ---------------------------------------------------------------------------

# Build the shape unconditional construction produces for `$x = 1 if $n > 0`:
#
#   $x is bound to 0 BEFORE the branch (the base).
#   The guarded arm rebinds it to 1.
#   The merge Phi selects [arm, base] by the guard.
#
# NOTE the arm order. The If's Proj(index 0) is the TAKEN arm, and the Phi's
# incoming values line up with the Region's control inputs. Getting that
# correspondence wrong is precisely the defect under test, so the fixture wires
# it the way the producer does and lets the backend prove it agrees.
sub build_rebind_diamond ($guard_value) {
    my $f     = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');

    my $zero = $f->make('Constant', value => 0, const_type => 'integer');
    $zero->set_stamp('Int');
    my $one = $f->make('Constant', value => 1, const_type => 'integer');
    $one->set_stamp('Int');

    # The BASE binding: $x = 0, established before the branch.
    my $xn = $f->make('Constant', value => '$x', const_type => 'string');
    my $base = $f->make('VarDecl', inputs => [$xn, $zero]);
    $base->set_stamp('Int');
    $base->set_control_in($start);

    # The guard. A runtime value, so nothing can constant-fold the branch away.
    my $g = $f->make('Constant', value => $guard_value, const_type => 'integer');
    $g->set_stamp('Int');
    my $cond = $f->make('NumGt', inputs => [$g, $zero]);
    $cond->set_stamp('Boolean');

    my $if   = $f->make('If',   inputs => [$base, $cond]);
    my $then = $f->make('Proj', index => 0, inputs => [$if]);
    my $else = $f->make('Proj', index => 1, inputs => [$if]);

    my $region = $f->make('Region', inputs => [[$then, $else]]);
    $if->set_region($region);

    # THE MERGE. Arm 0 (taken) contributes the rebound 1; arm 1 the base 0.
    my $phi = $f->make('Phi', region => $region, values => [$one, $zero]);
    $phi->set_stamp('Int');

    my $nl = $f->make('Constant', value => "\n", const_type => 'string');
    $nl->set_stamp('Str');
    my $co = $f->make('Coerce', inputs => [$phi],
                      from_repr => 'Int', to_repr => 'Str');
    $co->set_stamp('Str');

    my $print = $f->make('Print', inputs => [$co, $nl]);
    $print->set_control_in($region);

    my $undef = $f->make('Constant', value => 'undef', const_type => 'undef');
    $undef->set_stamp('Undef');
    my $ret = $f->make('Return', inputs => [$undef]);
    $ret->set_control_in($print);

    my $graph = Chalk::IR::Graph->new;
    $graph->merge($ret);
    return ($graph, $ret);
}

# Lower, assemble and RUN, comparing what the program prints. Emitted-IR
# inspection would not catch a wrong-arm select: the IR is well-formed either
# way, and only the value differs.
sub run_ll ($ret) {
    require File::Temp;
    my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    return (undef, $@) unless defined $ll;

    my ($fh, $path) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;

    my $lli = '/usr/lib/llvm-15/bin/lli';
    my $out = `$lli $path 2>&1`;
    return ($out, undef, $ll);
}

subtest 'guard TAKEN: the merge selects the ARM value, not the base' => sub {
    my ($graph, $ret) = build_rebind_diamond(5);   # 5 > 0, guard is true
    my ($out, $err, $ll) = run_ll($ret);
    ok defined $out, 'the graph lowers and runs' or do { diag $err; return };

    is $out, "1\n",
        'prints the rebound value 1 (perl prints 1)'
        or diag "got: " . ($out =~ s/\n/\\n/gr) . "\n$ll";
};

subtest 'guard NOT taken: the merge selects the BASE value' => sub {
    # The bilateral partner. Without it a fixture that always returns the base
    # would pass the half that matters and hide the defect -- the same
    # vacuous-polarity trap recorded throughout this arc.
    my ($graph, $ret) = build_rebind_diamond(0);   # 0 > 0 is false
    my ($out, $err, $ll) = run_ll($ret);
    ok defined $out, 'the graph lowers and runs' or do { diag $err; return };

    is $out, "0\n",
        'prints the base value 0 (perl prints 0)'
        or diag "got: " . ($out =~ s/\n/\\n/gr) . "\n$ll";
};

done_testing;
