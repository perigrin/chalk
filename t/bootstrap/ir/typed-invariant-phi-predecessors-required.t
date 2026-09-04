#!/usr/bin/env perl
# ABOUTME: A merge Phi over Proj arms must RECORD which arm each value came from.
# ABOUTME: The pairing half of the Phi/Region contract, which arity cannot check.

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
# typed-invariant-phi-region-arity.t checks that a Phi's value count equals its
# Region's control-input count, and says plainly that arity is only HALF the
# contract: it cannot catch a SWAPPED pairing of equal length, which is what all
# three of Chalk's phi miscompiles actually were (44d1fa8c, 9ce43cdd).
#
# The pairing half needs the Phi to RECORD its predecessors rather than have the
# consumer search for them. That field now exists (Node/Phi.pm `predecessors`)
# and the producer populates it at all four merge sites. Nothing REQUIRES it, so
# a producer that forgets is indistinguishable from a graph that legitimately
# has none.
#
# THE TRIGGER IS NARROW, ON PURPOSE. Predecessors are required only when the
# Region's control inputs RESOLVE TO PROJS -- i.e. there are genuinely named
# arms to point at. Measured across chalk's 32 merge-Phi construction sites, 20
# have >=2 Projs in scope and 12 build a bare Region with no branch at all
# (scope-trivial-phi.t unit-tests operand triviality on `Region(controls=>[])`).
# Requiring predecessors there would mean inventing an If/Proj skeleton the test
# does not care about -- fiction added to satisfy an invariant.
#
# So: a Region whose inputs are Projs is a real branch merge and must say which
# arm is which. A Region with no Proj inputs is exempt, and the exemption is
# structural rather than a carve-out -- there is nothing to name.
# ---------------------------------------------------------------------------

# A real branch merge: If -> two Projs -> Region. $with_preds decides whether
# the Phi records the arms it merges.
sub branch_graph ($with_preds) {
    my $f     = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');

    my $zero = $f->make('Constant', value => 0, const_type => 'integer');
    $zero->set_stamp('Int');
    my $one = $f->make('Constant', value => 1, const_type => 'integer');
    $one->set_stamp('Int');
    my $two = $f->make('Constant', value => 2, const_type => 'integer');
    $two->set_stamp('Int');

    my $cond = $f->make('NumGt', inputs => [$two, $one]);
    $cond->set_stamp('Boolean');

    my $if   = $f->make('If',   inputs => [$start, $cond]);
    my $then = $f->make('Proj', index => 0, inputs => [$if]);
    my $else = $f->make('Proj', index => 1, inputs => [$if]);

    my $region = $f->make('Region', inputs => [[$then, $else]]);
    $if->set_region($region);

    my $phi = $f->make('Phi',
        region => $region,
        values => [$one, $zero],
        ($with_preds ? (predecessors => [$then, $else]) : ()),
    );
    $phi->set_stamp('Int');

    my $ret = $f->make('Return', inputs => [$phi]);
    $ret->set_control_in($region);

    my $g = Chalk::IR::Graph->new;
    $g->merge($ret);
    return $g;
}

# check() returns a RESULT OBJECT ({ ok, violations }), not a flat list.
sub predecessor_violations ($g) {
    my ($result) = Chalk::IR::Graph::TypedInvariant->check($g);
    return grep { ($_->{message} // '') =~ /predecessor/i }
           (($result->{violations} // [])->@*);
}

subtest 'a merge Phi that records its arms passes' => sub {
    my @v = predecessor_violations(branch_graph(1));
    is_deeply \@v, [], 'no predecessor violation when the arms are recorded'
        or diag explain \@v;
};

subtest 'a merge Phi over Proj arms that records NOTHING is reported' => sub {
    my @v = predecessor_violations(branch_graph(0));

    ok scalar(@v), 'the missing predecessors are reported'
        or diag 'no predecessor violation raised';

    like +($v[0]{message} // ''), qr/Proj/,
        'the message says WHY it is required (the Region inputs are Projs)';
};

subtest 'a Phi on a branchless Region is exempt' => sub {
    # scope-trivial-phi.t's shape: a bare Region built to unit-test operand
    # triviality. No If, no Projs, nothing to name.
    my $f      = Chalk::IR::NodeFactory->new;
    my $region = $f->make('Region', controls => []);
    my $c1 = $f->make('Constant', value => 1, const_type => 'integer');
    my $c2 = $f->make('Constant', value => 2, const_type => 'integer');
    $_->set_stamp('Int') for $c1, $c2;

    my $phi = $f->make('Phi', region => $region, values => [$c1, $c2]);
    $phi->set_stamp('Int');

    my ($result) = Chalk::IR::Graph::TypedInvariant->check_nodes([$phi, $region, $c1, $c2]);
    my @v = grep { ($_->{message} // '') =~ /predecessor/i }
            (($result->{violations} // [])->@*);

    is_deeply \@v, [], 'a Region with no Proj inputs demands no predecessors'
        or diag explain \@v;
};

subtest 'a loop Phi is exempt' => sub {
    # A loop Phi's `region` is the Loop itself and its values are
    # [init, backedge] -- they pair with entry/back edges, not merge arms.
    my $f     = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');
    my $init  = $f->make('Constant', value => 0, const_type => 'integer');
    $init->set_stamp('Int');

    my $loop = $f->make_cfg('Loop', inputs => [$start]);
    my $phi  = $f->make('Phi', region => $loop, values => [$init]);
    $phi->set_stamp('Int');

    my ($result) = Chalk::IR::Graph::TypedInvariant->check_nodes([$phi, $loop, $init, $start]);
    my @v = grep { ($_->{message} // '') =~ /predecessor/i }
            (($result->{violations} // [])->@*);

    is_deeply \@v, [], 'a loop Phi demands no predecessors'
        or diag explain \@v;
};

done_testing;
