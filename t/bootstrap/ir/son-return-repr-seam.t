# ABOUTME: Tests the B::SoN -> Chalk JSON seam for Return shape and representation (Phase 4b-3).
# ABOUTME: B::SoN emits Return(control, value) + stamps; Chalk needs Return(value)+control_in + representation.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;

use lib 'lib';
use Chalk::IR::Serialize::JSON ();

# B::SoN serializes a Return as inputs=[control, value] (control token first) and
# carries type info as a `stamp` field. Chalk's contract is different: Return
# inputs[0] IS the value (control lives in control_in), and the LLVM backend
# requires an explicit `representation`. The loader must reconcile both, or the
# producible-now slice cannot lower (it GAPs on op=Start at inputs[0], and on
# missing representation).
#
# This is a minimal B::SoN-shaped graph for `1 + 2` (perl constant-folds it to
# Constant(3)): Start, Constant(3) stamped Int, Return(Start, Constant).

my $bson_json = JSON::PP->new->encode({
    version => 1,
    source  => 'seam-test',
    methods => {
        'main::f' => {
            start   => 0,
            returns => [2],
            nodes   => [
                { id => 0, op => 'Start',  cfg => JSON::PP::true, inputs => [] },
                { id => 1, op => 'Constant', inputs => [],
                  fields => { value => 3, const_type => 'integer' },
                  stamp  => 'Int' },
                { id => 2, op => 'Return', cfg => JSON::PP::true, inputs => [0, 1] },
            ],
        },
    },
});

my $graphs = Chalk::IR::Serialize::JSON::from_json($bson_json);
my $g = $graphs->{'main::f'};
ok(defined $g, 'graph loaded');

my $ret = $g->returns->[0];
is($ret->operation, 'Return', 'got the Return node');

# Contract 1: Return.inputs[0] must be the VALUE (the Constant), not control (Start).
my $value = $ret->inputs->[0];
ok(defined $value, 'Return has a value input');
is($value->operation, 'Constant', 'Return inputs[0] is the value (Constant), not Start');

# Contract 2: control is carried via control_in, not in inputs.
ok(defined $ret->control_in, 'Return control_in is set');
is(defined $ret->control_in ? $ret->control_in->operation : undef,
    'Start', 'Return control_in is the Start node');

# Contract 3: the value node carries a representation mapped from its stamp.
is($value->representation, 'Int',
    'Constant representation set to Int from the B::SoN stamp');

done_testing();
