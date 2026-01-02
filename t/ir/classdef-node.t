# ABOUTME: Tests for ClassDef IR node
# ABOUTME: Verifies ClassDef node for class structure organization (Chapter 23)

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Scalar::Util 'blessed', 'refaddr';

subtest 'ClassDef module loads' => sub {
    use_ok('Chalk::IR::Node::ClassDef');
};

subtest 'ClassDef creation with class_name' => sub {
    require Chalk::IR::Node::ClassDef;

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Counter',
    );

    ok(defined($classdef), 'ClassDef node is defined');
    ok(blessed($classdef), 'ClassDef node is blessed');
    is($classdef->class_name, 'Counter', 'class_name accessor works');
    is($classdef->op, 'ClassDef', 'op returns ClassDef');
};

subtest 'ClassDef interface methods' => sub {
    require Chalk::IR::Node::ClassDef;

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Test',
    );

    ok($classdef->can('id'), 'has id() method');
    ok($classdef->can('op'), 'has op() method');
    ok($classdef->can('inputs'), 'has inputs() method');
    ok($classdef->can('to_hash'), 'has to_hash() method');
    ok(defined($classdef->id), 'id() returns a value');
};

subtest 'ClassDef with fields' => sub {
    require Chalk::IR::Node::ClassDef;
    require Chalk::IR::Node::Field;

    my $field1 = Chalk::IR::Node::Field->new(name => '$count', index => 0);
    my $field2 = Chalk::IR::Node::Field->new(name => '$name', index => 1);

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Counter',
        fields     => [$field1, $field2],
    );

    is(scalar($classdef->fields->@*), 2, 'has two fields');
    is($classdef->field_index('$count'), 0, 'field_index finds $count at 0');
    is($classdef->field_index('$name'), 1, 'field_index finds $name at 1');
    is($classdef->field_index('$unknown'), undef, 'unknown field returns undef');
};

subtest 'ClassDef with methods' => sub {
    require Chalk::IR::Node::ClassDef;
    require Chalk::IR::Node::FunctionDef;

    my $method = Chalk::IR::Node::FunctionDef->new(
        inputs     => [],  # Required by Base class
        name       => 'inc',
        parameters => ['$self'],
        body_node  => undef,
    );

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Counter',
        methods    => [$method],
    );

    is(scalar($classdef->methods->@*), 1, 'has one method');
    is($classdef->methods->[0]->name, 'inc', 'method has correct name');
};

subtest 'ClassDef with parent_class' => sub {
    require Chalk::IR::Node::ClassDef;

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name   => 'SpecialCounter',
        parent_class => 'Counter',
    );

    is($classdef->parent_class, 'Counter', 'parent_class accessor works');
};

subtest 'ClassDef inputs() includes fields and methods' => sub {
    require Chalk::IR::Node::ClassDef;
    require Chalk::IR::Node::Field;
    require Chalk::IR::Node::FunctionDef;

    my $field = Chalk::IR::Node::Field->new(name => '$count', index => 0);
    my $method = Chalk::IR::Node::FunctionDef->new(
        inputs     => [],  # Required by Base class
        name       => 'inc',
        parameters => ['$self'],
        body_node  => undef,
    );

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Counter',
        fields     => [$field],
        methods    => [$method],
    );

    my $inputs = $classdef->inputs;
    is(scalar(@$inputs), 2, 'inputs has 2 elements (field + method)');
    ok((grep { $_ eq $field->id } @$inputs), 'inputs contains field id');
    ok((grep { $_ eq $method->id } @$inputs), 'inputs contains method id');
};

subtest 'ClassDef to_hash' => sub {
    require Chalk::IR::Node::ClassDef;
    require Chalk::IR::Node::Field;

    my $field = Chalk::IR::Node::Field->new(name => '$count', index => 0);

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name   => 'Counter',
        fields       => [$field],
        parent_class => 'Base',
    );

    my $hash = $classdef->to_hash;
    is($hash->{op}, 'ClassDef', 'to_hash op is ClassDef');
    is($hash->{id}, $classdef->id, 'to_hash id matches');
    is($hash->{attributes}{class_name}, 'Counter', 'attributes has class_name');
    is($hash->{attributes}{parent_class}, 'Base', 'attributes has parent_class');
    is($hash->{attributes}{field_count}, 1, 'attributes has field_count');
};

subtest 'ClassDef with overload_mappings' => sub {
    require Chalk::IR::Node::ClassDef;

    my $overload_map = {
        '""'  => 'value',
        'eq'  => '_string_eq',
        'cmp' => '_string_cmp',
    };

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name        => 'Token',
        overload_mappings => $overload_map,
    );

    ok(defined($classdef), 'ClassDef with overload_mappings is defined');
    is(ref($classdef->overload_mappings), 'HASH', 'overload_mappings returns hash');
    is_deeply($classdef->overload_mappings, $overload_map, 'overload_mappings accessor works');
};

subtest 'ClassDef overload_mappings defaults to empty hash' => sub {
    require Chalk::IR::Node::ClassDef;

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Simple',
    );

    is(ref($classdef->overload_mappings), 'HASH', 'overload_mappings defaults to hash');
    is(scalar(keys %{$classdef->overload_mappings}), 0, 'default overload_mappings is empty');
};

done_testing();
