# ABOUTME: Tests for Field IR node
# ABOUTME: Verifies Field node for class field definitions (Chapter 23)

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::Field;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Int;
use Scalar::Util 'blessed', 'refaddr';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

subtest 'Field node basic structure' => sub {
    my $field = Chalk::IR::Node::Field->new(
        inputs => [],
        name => 'my_field',
        index => 0,
    );

    ok(defined($field), 'Field node is defined');
    ok(blessed($field), 'Field node is blessed');
    ok($field->isa('Chalk::IR::Node::Field'), 'Field node has correct type');
    ok($field->isa('Chalk::IR::Node::Base'), 'Field node inherits from Base');
};

subtest 'Field node op method' => sub {
    my $field = Chalk::IR::Node::Field->new(
        inputs => [],
        name => 'test_field',
        index => 0,
    );

    is($field->op, 'Field', 'op() returns Field');
};

subtest 'Field node accessors' => sub {
    my $field = Chalk::IR::Node::Field->new(
        inputs => [],
        name => 'my_field',
        index => 2,
        field_type => Chalk::Grammar::Chalk::Type::Int->new(),
        field_attributes => { readonly => 1 },
    );

    is($field->name, 'my_field', 'name accessor works');
    is($field->index, 2, 'index accessor works');
    ok(defined($field->field_type), 'field_type accessor works');
    ok($field->field_type->isa('Chalk::Grammar::Chalk::Type::Int'), 'field_type is correct type');
    is_deeply($field->attributes, { readonly => 1 }, 'attributes accessor works');
};

subtest 'Field node with default value' => sub {
    my $default = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $field = Chalk::IR::Node::Field->new(
        inputs => [$default->id],
        name => 'counter',
        index => 0,
        field_type => Chalk::Grammar::Chalk::Type::Int->new(),
        default => $default,
    );

    is($field->default, $default, 'default accessor works');
};

subtest 'Field node inputs() with no default' => sub {
    my $field = Chalk::IR::Node::Field->new(
        inputs => [],
        name => 'simple_field',
        index => 0,
    );

    my $inputs = $field->inputs();
    is_deeply($inputs, [], 'inputs() returns empty array when no default');
};

subtest 'Field node inputs() with default value' => sub {
    my $default = Chalk::IR::Node::Constant->new(
        value => 'hello',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $field = Chalk::IR::Node::Field->new(
        inputs => [$default->id],
        name => 'greeting',
        index => 1,
        default => $default,
    );

    my $inputs = $field->inputs();
    is(scalar(@$inputs), 1, 'inputs() returns array with one element');
    is($inputs->[0], $default->id, 'inputs() contains default node id');
};

subtest 'Field node is_param() method' => sub {
    my $param_field = Chalk::IR::Node::Field->new(
        inputs => [],
        name => 'param_field',
        index => 0,
        field_attributes => { param => 1 },
    );

    my $non_param_field = Chalk::IR::Node::Field->new(
        inputs => [],
        name => 'normal_field',
        index => 1,
    );

    ok($param_field->is_param(), 'is_param() returns true for param field');
    ok(!$non_param_field->is_param(), 'is_param() returns false for normal field');
};

subtest 'Field node is_reader() method' => sub {
    my $reader_field = Chalk::IR::Node::Field->new(
        inputs => [],
        name => 'reader_field',
        index => 0,
        field_attributes => { reader => 1 },
    );

    my $non_reader_field = Chalk::IR::Node::Field->new(
        inputs => [],
        name => 'private_field',
        index => 1,
    );

    ok($reader_field->is_reader(), 'is_reader() returns true for reader field');
    ok(!$non_reader_field->is_reader(), 'is_reader() returns false for private field');
};

subtest 'Field node to_hash' => sub {
    my $default = Chalk::IR::Node::Constant->new(
        value => 100,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $field = Chalk::IR::Node::Field->new(
        inputs => [$default->id],
        name => 'value',
        index => 3,
        field_type => Chalk::Grammar::Chalk::Type::Int->new(),
        default => $default,
        field_attributes => { readonly => 1, param => 1 },
    );

    my $hash = $field->to_hash;
    is($hash->{op}, 'Field', 'to_hash op is Field');
    is($hash->{id}, $field->id, 'to_hash id matches');
    ok(exists $hash->{attributes}, 'to_hash has attributes');
    is($hash->{attributes}{name}, 'value', 'attributes has name');
    is($hash->{attributes}{index}, 3, 'attributes has index');
    ok(defined($hash->{attributes}{field_type}), 'attributes has field_type');
    is($hash->{attributes}{default_id}, $default->id, 'attributes has default_id');
    is_deeply($hash->{attributes}{field_attributes}, { readonly => 1, param => 1 },
        'attributes has field_attributes');
};

subtest 'Field node to_hash without optional fields' => sub {
    my $field = Chalk::IR::Node::Field->new(
        inputs => [],
        name => 'simple',
        index => 0,
    );

    my $hash = $field->to_hash;
    is($hash->{op}, 'Field', 'to_hash op is Field');
    is($hash->{attributes}{name}, 'simple', 'attributes has name');
    is($hash->{attributes}{index}, 0, 'attributes has index');
    ok(!exists $hash->{attributes}{default_id}, 'attributes does not have default_id when no default');
    ok(!exists $hash->{attributes}{field_type}, 'attributes does not have field_type when undefined');
};

done_testing();
