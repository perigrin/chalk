#!/usr/bin/env perl
# ABOUTME: A Phi records WHICH predecessor each incoming value arrives from.
# ABOUTME: Makes arm identity a field read instead of a backward control-chain search.

use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;

# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# A Phi's incoming values pair with its Region's control inputs by POSITION,
# and nothing recorded which predecessor a given value came from. Recovering
# it took three successive backend fixes, each a wider search:
#
#   1. assume slot 0 is the then-arm            -- wrong: the producer builds
#                                                  Region inputs continuing-first
#   2. scan Region inputs for a Proj with index -- wrong: a Region input is the
#                                                  arm's LAST EFFECT, not its Proj
#   3. walk back along control_in to find one   -- correct, and a search
#
# Defect 2 shipped an INVERTED merge in both polarities before it was caught
# (docs/plans/2026-08-18-the-2b3-refusal-still-earns-its-keep.md).
#
# LLVM stores the predecessor block explicitly per incoming value
# (`addIncoming(Value*, BasicBlock*)`) precisely because predecessor ORDER is
# not stable. Chalk is in that situation: two producers build Regions
# differently -- the hand-written frontend passes Projs
# (Actions.pm:2600, :2727) while perl5-son passes each arm's current control.
# See docs/research/2026-08-18-phi-pairing-should-not-be-a-search.md and its
# amendment 2026-08-18-region-input-carries-two-jobs.md, which rules out
# "make the Region hold Projs" -- that input is ALSO the control-chain link,
# and substituting the Proj severs the effects behind it.
#
# So: record the predecessor ON THE PHI, alongside the value. It does not
# disturb the Region's control-chain role, and it makes arm identity a lookup.
# ---------------------------------------------------------------------------

sub build ($with_preds) {
    my $f     = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');

    my $one = $f->make('Constant', value => 1, const_type => 'integer');
    $one->set_stamp('Int');
    my $zero = $f->make('Constant', value => 0, const_type => 'integer');
    $zero->set_stamp('Int');

    my $if   = $f->make('If',   inputs => [$start, $one]);
    my $then = $f->make('Proj', index => 0, inputs => [$if]);
    my $else = $f->make('Proj', index => 1, inputs => [$if]);

    # The arm carries an effect, so the Region's control input for it is the
    # PRINT, not the Proj -- the shape that broke the search.
    my $msg = $f->make('Constant', value => "in\n", const_type => 'string');
    $msg->set_stamp('Str');
    my $guarded = $f->make('Print', inputs => [$msg]);
    $guarded->set_control_in($then);

    my $region = $f->make('Region', inputs => [[$else, $guarded]]);
    $if->set_region($region);

    # Values in Region-input order: slot 0 <- else arm, slot 1 <- then arm.
    my %extra = $with_preds ? (predecessors => [$else, $then]) : ();
    my $phi = $f->make('Phi',
        region => $region,
        values => [$zero, $one],
        %extra,
    );
    $phi->set_stamp('Int');

    return ($f, $if, $then, $else, $region, $phi);
}

subtest 'a Phi can record the predecessor of each incoming value' => sub {
    my (undef, undef, $then, $else, undef, $phi) = build(1);

    can_ok $phi, 'predecessors';
    my $preds = $phi->predecessors;
    is ref($preds), 'ARRAY', 'predecessors is an arrayref';
    is scalar($preds->@*), 2, 'one predecessor per incoming value';

    is $preds->[0]->id, $else->id, 'slot 0 came from the else arm';
    is $preds->[1]->id, $then->id, 'slot 1 came from the then arm';
};

subtest 'arm identity is a FIELD READ, not a search' => sub {
    # The payoff. With the predecessor recorded, "which slot is the then arm?"
    # is answered without touching control_in at all -- which is what removes
    # the backward walk.
    my (undef, undef, $then, undef, undef, $phi) = build(1);

    my $preds = $phi->predecessors;
    my ($then_slot) = grep {
        $preds->[$_]->can('index') && $preds->[$_]->index == 0
    } 0 .. $preds->$#*;

    is $then_slot, 1, 'the then arm is slot 1, read straight off the Phi';
    is $phi->inputs->[$then_slot]->value, 1, 'and its value is the arm value';
};

subtest 'predecessors is OPTIONAL — a Phi without them still builds' => sub {
    # Both producers must be migrated before anything can depend on this, and
    # loop Phis pair with entry/backedge rather than a predecessor list. An
    # absent list must therefore stay legal, and read as "not recorded".
    my (undef, undef, undef, undef, undef, $phi) = build(0);

    my $preds = $phi->predecessors;
    ok !defined($preds) || !scalar($preds->@*),
        'a Phi built without predecessors reports none';
    is scalar($phi->inputs->@*), 2, 'and its values are unaffected';
};

done_testing;
