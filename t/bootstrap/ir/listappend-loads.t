# ABOUTME: Tests that the producer's ListAppend node (map/grep block lowering) loads.
# ABOUTME: Covers grep's 3-input predicate shape, map's 2-input shape, and arity 1.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;

use lib 'lib';
use Chalk::IR::Serialize::JSON ();

# perl5-son lowers `map`/`grep` with a block into a counted loop whose
# accumulator is a loop Phi; each iteration's contribution is a ListAppend
# taking that Phi as inputs[0]. Measured from the pinned producer:
#   grep { $_ > 1 } (3,1,2)  ->  ListAppend(phi, element, predicate)   3 inputs
#   map  { $_ * 2 } (1,2)    ->  ListAppend(phi, value)               2 inputs
#   map  { ($_, $_) } (1,2)  ->  ListAppend(phi, value, value)        3 inputs
# Arity is VARIABLE, so a class that hardcodes one shape passes a
# single-shape test and mishandles the others. Each shape is asserted here.

# Build a loop-shaped graph whose accumulator Phi feeds a ListAppend of the
# given extra inputs. Node ids are fixed; @extra are ids of already-built nodes.
sub graph_with_listappend (@extra) {
    return {
        start   => 0,
        returns => [10],
        nodes   => [
            { id => 0, op => 'Start', cfg => JSON::PP::true, inputs => [] },
            { id => 1, op => 'Loop', cfg => JSON::PP::true, inputs => [0], control_in => 0 },
            { id => 2, op => 'Region', cfg => JSON::PP::true, inputs => [1], head => 1 },
            { id => 3, op => 'ArrayLiteral', inputs => [], stamp => 'Array' },
            { id => 4, op => 'Constant', inputs => [], stamp => 'Int',
              fields => { value => 7, const_type => 'integer' } },
            { id => 5, op => 'Constant', inputs => [], stamp => 'Boolean',
              fields => { value => 1, const_type => 'integer' } },
            # Loop Phi: inputs[1] is the forward backedge to the ListAppend --
            # the one input index the loader is allowed to resolve forward.
            { id => 6, op => 'Phi', inputs => [3, 7], stamp => 'Array',
              fields => { region => 1 } },
            { id => 7, op => 'ListAppend', inputs => [6, @extra], stamp => 'Array' },
            # The accumulator needs a reader, or the append is unreachable from
            # nodes() -- the real graphs reach it via `say(scalar(@g))`.
            { id => 8, op => 'Count', inputs => [6], stamp => 'Int' },
            { id => 9, op => 'Return', cfg => JSON::PP::true, inputs => [8], control_in => 2 },
            { id => 10, op => 'Return', cfg => JSON::PP::true, inputs => [8], control_in => 2 },
        ],
    };
}

sub load_one ($name, @extra) {
    my $json = JSON::PP->new->encode({
        version => 1,
        source  => 'listappend-test',
        methods => { 'main::f' => graph_with_listappend(@extra) },
    });
    my $graphs;
    my $ok = eval { $graphs = Chalk::IR::Serialize::JSON::from_json($json); 1 };
    ok($ok, "$name: from_json succeeds") or diag($@);
    return $graphs;
}

sub listappend_of ($graphs) {
    my ($la) = grep { $_->operation() eq 'ListAppend' }
               $graphs->{'main::f'}->nodes()->@*;
    return $la;
}

# --- grep: 3 inputs, last is the Boolean predicate gating the append -----
{
    my $graphs = load_one('grep shape', 4, 5);
    my $la = listappend_of($graphs);
    ok($la, 'grep shape: ListAppend node is present in the loaded graph');
    is(scalar $la->inputs()->@*, 3, 'grep shape: all 3 inputs survive the load');
    is($la->inputs()->[0]->operation(), 'Phi', 'grep shape: inputs[0] is the accumulator Phi');
    is($la->inputs()->[2]->operation(), 'Constant', 'grep shape: the predicate is inputs[2]');
}

# --- map: 2 inputs, no predicate ----------------------------------------
{
    my $graphs = load_one('map shape', 4);
    my $la = listappend_of($graphs);
    is(scalar $la->inputs()->@*, 2, 'map shape: 2 inputs survive the load');
    is($la->inputs()->[1]->operation(), 'Constant', 'map shape: the contribution is inputs[1]');
}

# --- arity 1: the iteration contributes nothing (`map { () }`) -----------
{
    my $graphs = load_one('empty contribution');
    my $la = listappend_of($graphs);
    is(scalar $la->inputs()->@*, 1, 'arity 1: the bare accumulator loads');
    is($la->inputs()->[0]->operation(), 'Phi', 'arity 1: inputs[0] is still the Phi');
}

# --- identity: two ListAppends in one graph must NOT merge --------------
# ListAppend declares per_call identity, so two appends never collapse into
# one regardless of what their inputs hash to.
#
# The two appends here share ONE accumulator and one contribution, so they
# are content-identical: `op|inputs` cannot tell them apart. This is the
# shape that discriminates. Giving each its own Phi would NOT: Phi is itself
# per-call, so its unique id would separate the two hashes and the test would
# pass under hash_consed as well -- a vacuous green. Under the current
# producer inputs[0] is always a distinct loop Phi, which is exactly why
# hash-consing happens to be safe today and why relying on it would be
# borrowing correctness from Phi's identity rather than stating this node's.
{
    my $json = JSON::PP->new->encode({
        version => 1, source => 'listappend-dup',
        methods => { 'main::f' => {
            start => 0, returns => [9],
            nodes => [
                { id => 0, op => 'Start', cfg => JSON::PP::true, inputs => [] },
                { id => 1, op => 'Loop', cfg => JSON::PP::true, inputs => [0], control_in => 0 },
                { id => 2, op => 'Region', cfg => JSON::PP::true, inputs => [1], head => 1 },
                { id => 3, op => 'ArrayLiteral', inputs => [], stamp => 'Array' },
                { id => 4, op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 7, const_type => 'integer' } },
                { id => 5, op => 'Phi', inputs => [3, 6], stamp => 'Array',
                  fields => { region => 1 } },
                { id => 6, op => 'ListAppend', inputs => [5, 4], stamp => 'Array' },
                # SAME accumulator, SAME contribution: byte-identical content.
                # Two appends of 7 onto one list is a list two elements longer,
                # so merging these would silently drop an element.
                { id => 7, op => 'ListAppend', inputs => [5, 4], stamp => 'Array' },
                { id => 8, op => 'Count', inputs => [7], stamp => 'Int' },
                { id => 9, op => 'Return', cfg => JSON::PP::true, inputs => [8], control_in => 2 },
            ],
        } },
    });
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my @las = grep { $_->operation() eq 'ListAppend' } $graphs->{'main::f'}->nodes()->@*;
    is(scalar @las, 2, 'two content-identical appends stay two distinct nodes');
    isnt($las[0]->id(), $las[1]->id(), 'the two appends have distinct ids');
}

done_testing();
