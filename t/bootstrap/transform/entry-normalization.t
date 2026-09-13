# ABOUTME: A Value node arriving stamp-less is Unknown after entry
# ABOUTME: normalization, and is COUNTED as arrived-absent either way.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Value ();

# T1 spec §4: ABSENT and `Unknown` are DIFFERENT and must not be conflated.
# `Unknown` is the lattice top -- a real type meaning "inference did not
# determine this". An ABSENCE is a node nobody ever stamped, and it forces
# every downstream consumer to invent its own meaning for undef.
#
# Entry normalization makes the distinction survive: T1 replaces an absence
# with `Unknown` at its entry, so no pass downstream sees undef -- AND records
# that it arrived absent, so the frontend defect stays measurable. Both halves
# are required. Normalizing without counting hides the frontend bug; counting
# without normalizing leaves undef in the graph.
#
# Measured baseline, 247 corpus cases, post-load Value nodes:
#   ABSENT = 17, Unknown = 0, total = 2020
# The Unknown=0 IS the symptom spec §4 names: %LOWERABLE_STAMP nulls every
# wire `Unknown` into an absence before inference runs, so at this boundary
# the two are already indistinguishable.

my $T1 = 'Chalk::IR::Transform::TypeInference';

subtest 'the transform exists and normalizes at entry' => sub {
    eval "require $T1; 1" or do { fail("$T1 does not load: $@"); return };

    my $f = Chalk::IR::NodeFactory->new;
    my $bare = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'x', inputs => []);
    is($bare->stamp, undef, 'the node arrives stamp-less');

    my $t1 = $T1->new;
    $t1->run(TestGraph->new([$bare]));

    is($bare->stamp, 'Unknown',
       'a stamp-less Value is Unknown after entry normalization');
};

subtest 'the absence is COUNTED, whether or not T1 later types it' => sub {
    eval "require $T1; 1" or do { plan skip_all => "$T1 does not load" };

    my $f = Chalk::IR::NodeFactory->new;
    my $bare = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'y', inputs => []);
    my $t1 = $T1->new;
    $t1->run(TestGraph->new([$bare]));
    my $r = $t1->report;

    ok(defined $r, 'T1 carries a report') or return;
    is($r->{arrived_absent}, 1, 'the arrived-absent count sees the node');
};

subtest 'a node that ARRIVES Unknown is not counted as absent' => sub {
    # The distinction spec §4 protects: Unknown is an ANSWER, absence is not.
    # A frontend that says Unknown did its job; one that says nothing did not.
    eval "require $T1; 1" or do { plan skip_all => "$T1 does not load" };

    my $f = Chalk::IR::NodeFactory->new;
    my $stamped = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'z', inputs => []);
    $stamped->set_stamp('Unknown');
    my $t1 = $T1->new;
    $t1->run(TestGraph->new([$stamped]));
    my $r = $t1->report;

    ok(defined $r, 'T1 carries a report') or return;
    is($r->{arrived_absent}, 0, 'an explicit Unknown is not an absence');
};

package TestGraph {
    sub new { my ($c,$n)=@_; return bless { nodes => $n }, $c }
    sub nodes { $_[0]{nodes} }
    sub mop   { undef }
}

done_testing;
