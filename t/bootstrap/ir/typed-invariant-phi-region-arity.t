#!/usr/bin/env perl
# ABOUTME: A Phi's incoming count must equal its Region's control-input count.
# ABOUTME: The assertion every production SoN IR has and Chalk did not.

use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::IR::Graph::TypedInvariant;

# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# A Phi's incoming values pair POSITIONALLY with its Region's control inputs:
# slot i comes from the predecessor at Region input i. Nothing checked that
# the two even had the same LENGTH, and nothing checked the pairing at all.
#
# Chalk had THREE phi-pairing miscompiles in one arc, and no assertion would
# have caught any of them:
#
#   1. the backend assumed slot 0 was the then-arm, while the producer builds
#      Region inputs continuing-path-first  (fixed 44d1fa8c)
#   2. a Region input is the arm's LAST EFFECT, not its Proj, so scanning for
#      a Proj failed and fell back to slot 0 -- inverted arms in both
#      polarities  (fixed 9ce43cdd)
#   3. `my $n=5; my $x=0; $x = 1 if $n>0` selected the base over the arm
#      (fixed 44d1fa8c, same root)
#
# Every system surveyed asserts this: C2's "broken Phi/Region subgraph",
# Graal's `phiPredecessorCount() == valueCount()`, TurboFan's
# `CHECK_EQ(value_count, control->op()->ControlInputCount())`. See
# docs/research/2026-08-18-phi-pairing-should-not-be-a-search.md.
#
# ARITY IS NOT THE WHOLE CONTRACT -- it does not catch a SWAPPED pairing of
# equal length, which is what defects 1-3 actually were. It is the half that
# is checkable from the graph alone, and it makes a length divergence loud
# instead of silent. The pairing half needs the structural change that
# research doc discusses (store the Proj per value, or add an end-of-arm
# carrier); this is deliberately the cheap half, landed now.
# ---------------------------------------------------------------------------

sub build_graph ($phi_value_count) {
    my $f     = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');

    my $zero = $f->make('Constant', value => 0, const_type => 'integer');
    $zero->set_representation('Int');
    my $one = $f->make('Constant', value => 1, const_type => 'integer');
    $one->set_representation('Int');
    my $two = $f->make('Constant', value => 2, const_type => 'integer');
    $two->set_representation('Int');

    my $cond = $f->make('NumGt', inputs => [$two, $one]);
    $cond->set_representation('Boolean');

    my $if   = $f->make('If',   inputs => [$start, $cond]);
    my $then = $f->make('Proj', index => 0, inputs => [$if]);
    my $else = $f->make('Proj', index => 1, inputs => [$if]);

    my $region = $f->make('Region', inputs => [[$then, $else]]);
    $if->set_region($region);

    # The variable: 1 value for a deliberately-broken graph, 2 for a sound one.
    my @values = $phi_value_count == 1 ? ($one) : ($one, $zero);
    # Record the arms. This graph is a real branch merge, so the pairing
    # invariant (typed-invariant-phi-predecessors-required.t) demands it; the
    # ARITY defect under test here is independent of whether arms are recorded.
    my $phi = $f->make('Phi', region => $region, values => \@values,
                       predecessors => [$then, $else]);
    $phi->set_representation('Int');

    my $ret = $f->make('Return', inputs => [$phi]);
    $ret->set_control_in($region);

    my $g = Chalk::IR::Graph->new;
    $g->merge($ret);
    return $g;
}

# check() returns a RESULT OBJECT ({ ok, violations }), not a flat list.
sub violations_for ($g) {
    my ($result) = Chalk::IR::Graph::TypedInvariant->check($g);
    return (($result->{violations} // [])->@*);
}

subtest 'a Phi whose arity matches its Region passes' => sub {
    my $g = build_graph(2);
    my @v = violations_for($g);
    my @phi_v = grep { ($_->{message} // '') =~ /Phi/ } @v;
    is_deeply \@phi_v, [], 'no Phi/Region violation on a sound graph'
        or diag explain \@phi_v;
};

subtest 'a Phi with FEWER values than its Region has controls is reported' => sub {
    # The graph a length divergence produces. Today it lowers into an invalid
    # phi or a wrong-arm select depending on where it is read; either way
    # nothing says so.
    my $g = build_graph(1);
    my @v = violations_for($g);
    my @phi_v = grep { ($_->{message} // '') =~ /Phi/ } @v;

    ok scalar(@phi_v), 'the arity mismatch is reported'
        or diag 'no Phi violation among: ' . join('; ', map { $_->{message} } @v);

    like +($phi_v[0]{message} // ''), qr/Region/,
        'the message names the Region it disagrees with';
};

done_testing;
