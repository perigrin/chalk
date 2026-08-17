#!/usr/bin/env perl
# ABOUTME: A diamond whose arms hold no fixed nodes lowers as a select, not a branch.
# ABOUTME: The structural collapse test — Graal's, not a scan of what the arms contain.

use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::Target::LLVM;

# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# The producer decides whether to build control flow for a void branch by
# SCANNING the arm for effect kinds (_arm_has_element_store /
# _arm_has_void_call / _arm_has_die). That question cannot be answered there:
# the predicates miss nested branches, making them descend recurses forever on
# a loop back-edge, and measured across 117 arm shapes they overlap on 101 with
# first-caller-wins semantics. See
# docs/research/2026-08-13-branch-merge-prior-art.md.
#
# The prior art's answer is to build control flow UNCONDITIONALLY and collapse
# an empty diamond back to a select in a LATER pass. Chalk cannot take that
# step yet for one measured reason: without a collapse pass, a diamond built
# for a pure rebind (`$x = 1 if $c`) STAYS a diamond, and
# t/from-optree-postfix-modifier.t pins the select form. Measured: making
# construction unconditional breaks 4 of its 7 subtests.
#
# So the collapse pass is the PREREQUISITE for deleting the arm scans, not
# cleanup afterwards. This test pins it.
#
# THE TEST IS STRUCTURAL, deliberately. It asks "are both arms empty of fixed
# nodes?" — which `is_fixed` (a node-TYPE property, landed 20e31d5d) makes
# answerable — and never asks what KIND of thing an arm contains. That is the
# distinction the whole arc turns on.
# ---------------------------------------------------------------------------

# Build: if (cond) { x = 1 } else { x = 0 }  with NO effects in either arm.
# The arms only produce values, so the whole diamond is a select.
sub build_pure_diamond () {
    my $f     = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');

    my $zero = $f->make('Constant', value => 0, const_type => 'integer');
    $zero->set_representation('Int');
    my $one = $f->make('Constant', value => 1, const_type => 'integer');
    $one->set_representation('Int');
    my $two = $f->make('Constant', value => 2, const_type => 'integer');
    $two->set_representation('Int');

    my $cond = $f->make('NumGt', inputs => [$two, $one],
                        left => $two, right => $one);
    $cond->set_representation('Bool');

    my $if   = $f->make('If',   inputs => [$start, $cond]);
    my $then = $f->make('Proj', index => 0, inputs => [$if]);
    my $else = $f->make('Proj', index => 1, inputs => [$if]);

    # Both arms are PURE: they contribute a value and nothing else.
    my $region = $f->make('Region', inputs => [[$then, $else]]);
    # set_region wires BOTH directions: If->region (read by phi placement) and
    # Region->head (read by the control-chain walk, and by the phi-before-region
    # recovery). A hand-built graph that omits it leaves head=undef.
    $if->set_region($region);
    my $phi = $f->make('Phi', region => $region, values => [$one, $zero]);
    $phi->set_representation('Int');

    my $nl = $f->make('Constant', value => "\n", const_type => 'string');
    $nl->set_representation('Str');
    my $co = $f->make('Coerce', inputs => [$phi],
                      from_repr => 'Int', to_repr => 'Str');
    $co->set_representation('Str');

    my $print = $f->make('Print', inputs => [$co, $nl]);
    $print->set_control_in($region);

    my $undef = $f->make('Constant', value => 'undef', const_type => 'undef');
    $undef->set_representation('Undef');
    my $ret = $f->make('Return', inputs => [$undef]);
    $ret->set_control_in($print);

    my $g = Chalk::IR::Graph->new;
    $g->merge($ret);
    return ($g, $ret);
}

# Build the same diamond but with a real EFFECT in one arm: a Print pinned to
# the then-Proj. This one must KEEP its control flow.
sub build_effectful_diamond () {
    my $f     = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');

    my $one = $f->make('Constant', value => 1, const_type => 'integer');
    $one->set_representation('Int');
    my $two = $f->make('Constant', value => 2, const_type => 'integer');
    $two->set_representation('Int');

    my $cond = $f->make('NumGt', inputs => [$two, $one],
                        left => $two, right => $one);
    $cond->set_representation('Bool');

    my $if   = $f->make('If',   inputs => [$start, $cond]);
    my $then = $f->make('Proj', index => 0, inputs => [$if]);
    my $else = $f->make('Proj', index => 1, inputs => [$if]);

    my $msg = $f->make('Constant', value => "in\n", const_type => 'string');
    $msg->set_representation('Str');
    my $guarded = $f->make('Print', inputs => [$msg]);
    $guarded->set_control_in($then);          # <-- a FIXED node inside the arm

    my $region = $f->make('Region', inputs => [[$else, $guarded]]);
    $if->set_region($region);

    my $done = $f->make('Constant', value => "done\n", const_type => 'string');
    $done->set_representation('Str');
    my $print = $f->make('Print', inputs => [$done]);
    $print->set_control_in($region);

    my $undef = $f->make('Constant', value => 'undef', const_type => 'undef');
    $undef->set_representation('Undef');
    my $ret = $f->make('Return', inputs => [$undef]);
    $ret->set_control_in($print);

    my $g = Chalk::IR::Graph->new;
    $g->merge($ret);
    return ($g, $ret);
}

subtest 'a diamond with no fixed nodes in either arm becomes a select' => sub {
    my ($g, $ret) = build_pure_diamond();
    my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok defined $ll, 'the graph lowers' or do { diag $@; return };

    # The merge ALREADY lowers as a select -- that half works today.
    like $ll, qr/\bselect\b/,
        'the merge lowered as a select';

    # STEP 5, NOT YET BUILT. The backend emits the select AND the (now dead)
    # arm blocks. That is wasted code, not a wrong answer, which is why this is
    # a TODO rather than a failure: the collapse pass is what removes them, and
    # it is only reachable now that Phi-before-Region is fixed.
    TODO: {
        local $TODO = 'collapse pass (step 5) not built: dead arm blocks remain';
        unlike $ll, qr/^if\.(then|else)\.\d+:/m,
            'no branch arm blocks were emitted';
    }
};

subtest 'a diamond with a fixed node in an arm KEEPS its control flow' => sub {
    # The safety half. A collapse that fires here would hoist a guarded effect
    # and run it unconditionally -- the miscompile this whole arc is about.
    my ($g, $ret) = build_effectful_diamond();
    my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok defined $ll, 'the graph lowers' or do { diag $@; return };

    like $ll, qr/^if\.(then|else)\.\d+:/m,
        'the branch arms are still emitted'
        or diag "no arms in:\n$ll";
};

done_testing;
