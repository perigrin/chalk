# ABOUTME: Tests the loader wires Region.head + reshapes Region-controlled Returns (RC2).
# ABOUTME: B::SoN emits control-flow bodies as If/Proj/Region/Phi/Return(Region,value).
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;

use lib 'lib';
use Chalk::IR::Serialize::JSON ();

# A control-flow body (and/or, if with a merge) loads as
# If -> Proj,Proj -> Region -> Phi, and Return(Region, value). Two loader jobs:
#  1. Return leading with a CFG control node (here Region, not just Start) has
#     that control split into control_in, value kept as inputs[0].
#  2. Region.head is wired to the owning If (a Proj input's input), which the
#     backend's control-chain walk needs to emit the enclosing structure.

my $json = JSON::PP->new->encode({
    version => 1,
    source  => 'region-head',
    methods => {
        'main::f' => {
            start   => 0,
            returns => [8],
            nodes   => [
                { id => 0, op => 'Start',  cfg => JSON::PP::true, inputs => [] },
                { id => 1, op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 3, const_type => 'integer' } },
                { id => 2, op => 'If',     cfg => JSON::PP::true, inputs => [0, 1] },
                { id => 3, op => 'Proj',   cfg => JSON::PP::true, inputs => [2],
                  fields => { index => 0 } },
                { id => 4, op => 'Proj',   cfg => JSON::PP::true, inputs => [2],
                  fields => { index => 1 } },
                { id => 5, op => 'Region', cfg => JSON::PP::true, inputs => [3, 4] },
                { id => 6, op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 7, const_type => 'integer' } },
                { id => 7, op => 'Phi',    inputs => [6, 6], fields => { region => 5 } },
                { id => 8, op => 'Return', cfg => JSON::PP::true, inputs => [5, 7] },
            ],
        },
    },
});

my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
my $g = $graphs->{'main::f'};
my $ret = $g->returns->[0];

subtest 'Region-controlled Return splits control into control_in' => sub {
    is($ret->inputs->[0]->operation, 'Phi',
        'Return inputs[0] is the value (Phi), not the Region control');
    ok(defined $ret->control_in, 'Return control_in is set');
    is($ret->control_in->operation, 'Region', 'control_in is the Region');
};

subtest 'Region.head is wired to the owning If' => sub {
    my $region = $ret->control_in;
    ok(defined $region->head, 'Region has a head');
    is($region->head->operation, 'If', 'Region.head is the owning If');
};

done_testing();
