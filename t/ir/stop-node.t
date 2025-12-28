# ABOUTME: Tests for Stop IR node class_defs field
# ABOUTME: Verifies Stop node can store and expose ClassDef nodes

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Scalar::Util 'blessed';
use Chalk::IR::Node::Stop;
use Chalk::IR::Node::ClassDef;
use Chalk::IR::Node::Field;

subtest 'Stop has class_defs field' => sub {
    my $stop = Chalk::IR::Node::Stop->new(inputs => []);
    ok(defined $stop, 'Stop node created');
    ok($stop->can('class_defs'), 'Stop has class_defs method');
    is_deeply($stop->class_defs, [], 'class_defs defaults to empty array');
};

subtest 'Stop class_defs via constructor' => sub {
    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Counter',
        fields     => [],
        methods    => [],
    );

    my $stop = Chalk::IR::Node::Stop->new(
        inputs     => [],
        class_defs => [$classdef],
    );

    is(scalar($stop->class_defs->@*), 1, 'class_defs has one element');
    is($stop->class_defs->[0]->class_name, 'Counter', 'ClassDef accessible');
};

subtest 'Stop add_class method' => sub {
    my $stop = Chalk::IR::Node::Stop->new(inputs => []);

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Point',
        fields     => [],
        methods    => [],
    );

    $stop->add_class($classdef);

    is(scalar($stop->class_defs->@*), 1, 'class added');
    is($stop->class_defs->[0]->class_name, 'Point', 'class name correct');
};

subtest 'Stop to_hash includes class_defs' => sub {
    my $field = Chalk::IR::Node::Field->new(
        name       => '$x',
        index      => 0,
        field_type => 'Int',
    );

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Point',
        fields     => [$field],
        methods    => [],
    );

    my $stop = Chalk::IR::Node::Stop->new(
        inputs     => [],
        class_defs => [$classdef],
    );

    my $hash = $stop->to_hash;
    ok(exists $hash->{attributes}{class_defs}, 'to_hash has class_defs in attributes');
    is(scalar($hash->{attributes}{class_defs}->@*), 1, 'class_defs has one id');
    is($hash->{attributes}{class_defs}[0], $classdef->id, 'class id correct');
};

subtest 'Stop clone_with_inputs preserves class_defs' => sub {
    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Widget',
        fields     => [],
        methods    => [],
    );

    my $stop = Chalk::IR::Node::Stop->new(
        inputs     => [],
        class_defs => [$classdef],
    );

    my $cloned = $stop->clone_with_inputs([], {});

    is(scalar($cloned->class_defs->@*), 1, 'cloned has class_defs');
    is($cloned->class_defs->[0]->class_name, 'Widget', 'class preserved');
};

done_testing();
