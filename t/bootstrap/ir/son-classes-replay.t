# ABOUTME: Tests the 4c-2 MOP replay: from_json consumes a B::SoN classes section.
# ABOUTME: A declarative classes JSON section is replayed via declare_*/seal into a sealed MOP.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;

use lib 'lib';
use Chalk::IR::Serialize::JSON ();

# B::SoN emits a `classes` section alongside the per-method graphs (4c-1a).
# from_json replays it through Chalk::MOP declare_class/field/method + seal,
# returning ($graphs, $mop) in list context (scalar context stays \%graphs for
# the existing callers).

my $json = JSON::PP->new->encode({
    version => 1,
    source  => 'classes-test',
    methods => {
        'Counter::val' => {
            start   => 0,
            returns => [2],
            nodes   => [
                { id => 0, op => 'Start',  cfg => JSON::PP::true, inputs => [] },
                # STAMPED, because every Value node carries a type after T1
                # (_assert_value_nodes_are_typed). This fixture predates that
                # invariant and left the read untyped, which a real wire never
                # does -- the producer stamps a field read from the field's
                # declared type.
                { id => 1, op => 'FieldAccess', stamp => 'Int', inputs => [],
                  fields => { field_index => 0, field_stash => 'Counter' } },
                { id => 2, op => 'Return', cfg => JSON::PP::true, inputs => [0, 1] },
            ],
        },
    },
    classes => {
        Counter => {
            name    => 'Counter',
            parent  => undef,
            fields  => [
                # `type` matches the stamp on the FieldAccess above: the field
                # IS the thing being read, so a document where they disagree is
                # malformed rather than merely underspecified.
                { name => '$n', fieldix => 0, is_param => JSON::PP::true,
                  param_name => 'n', type => 'Int' },
            ],
            methods => { val => 'Counter::val' },
        },
    },
});

subtest 'scalar context stays backward-compatible (\%graphs)' => sub {
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    is(ref $graphs, 'HASH', 'scalar context returns a hashref of graphs');
    ok(exists $graphs->{'Counter::val'}, 'the method graph is present');
};

subtest 'list context returns a sealed MOP with the class' => sub {
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $mop = (values %$graphs)[0]->mop;
    ok(defined $mop, 'got a MOP in list context');
    ok($mop->is_sealed, 'the MOP is sealed');

    my $cls = $mop->for_class('Counter');
    ok(defined $cls, 'Counter class is in the MOP');
    is($cls->name, 'Counter', 'class name');
};

subtest 'the field is declared with its :param attribute' => sub {
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $mop = (values %$graphs)[0]->mop;
    my $cls = $mop->for_class('Counter');
    my ($field) = $cls->fields;
    ok(defined $field, 'class has a field');
    is($field->name, '$n', 'field name');
    is($field->fieldix, 0, 'field index');
    ok($field->is_param, 'field is :param');
    is($field->param_name, 'n', 'param name');
};

subtest 'the method is declared with its loaded graph' => sub {
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $mop = (values %$graphs)[0]->mop;
    my $cls = $mop->for_class('Counter');
    my ($method) = grep { $_->name eq 'val' } $cls->methods;
    ok(defined $method, 'method val is declared');
    is($method->graph, $graphs->{'Counter::val'},
        'the method graph is the same object as the loaded method graph');
};

done_testing();
