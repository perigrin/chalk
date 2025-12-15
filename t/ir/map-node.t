# ABOUTME: Tests for Map IR node
# ABOUTME: Verifies Map node structure, inputs, and serialization

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::Map;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Int;
use Scalar::Util 'blessed';

# Create fresh graph for tests
my $graph = Chalk::IR::Graph->new();

# Create a mock block and list for testing
my $mock_block = Chalk::IR::Node::Constant->new(
    value => 'block_placeholder',
    type => Chalk::Grammar::Chalk::Type::Str->new()
);

my $mock_list = Chalk::IR::Node::Constant->new(
    value => 'list_placeholder',
    type => Chalk::Grammar::Chalk::Type::Str->new()
);

subtest 'Map node basic structure' => sub {
    my $map = Chalk::IR::Node::Map->new(
        block => $mock_block,
        list  => $mock_list,
    );

    ok(defined($map), 'Map node is defined');
    ok(blessed($map), 'Map node is blessed');
    ok($map->isa('Chalk::IR::Node::Map'), 'Map node has correct type');
};

subtest 'Map node op method' => sub {
    my $map = Chalk::IR::Node::Map->new(
        block => $mock_block,
        list  => $mock_list,
    );

    is($map->op(), 'Map', 'op() returns Map');
};

subtest 'Map node accessors' => sub {
    my $map = Chalk::IR::Node::Map->new(
        block => $mock_block,
        list  => $mock_list,
    );

    ok(defined($map->block), 'block accessor works');
    ok(defined($map->list), 'list accessor works');
    is($map->block->id, $mock_block->id, 'block is correct');
    is($map->list->id, $mock_list->id, 'list is correct');
};

subtest 'Map node to_hash' => sub {
    my $map = Chalk::IR::Node::Map->new(
        block => $mock_block,
        list  => $mock_list,
    );

    my $hash = $map->to_hash();
    is($hash->{op}, 'Map', 'to_hash op is Map');
    is($hash->{id}, $map->id, 'to_hash id matches');
    ok(defined($hash->{attributes}), 'to_hash has attributes');
    is($hash->{attributes}{block_id}, $mock_block->id, 'attributes has block_id');
    is($hash->{attributes}{list_id}, $mock_list->id, 'attributes has list_id');
};

subtest 'Map node inputs' => sub {
    my $map = Chalk::IR::Node::Map->new(
        block => $mock_block,
        list  => $mock_list,
    );

    my $inputs = $map->inputs();
    ok(ref($inputs) eq 'ARRAY', 'inputs returns arrayref');
    is(scalar(@$inputs), 2, 'inputs has 2 elements');
    is($inputs->[0], $mock_block->id, 'First input is block id');
    is($inputs->[1], $mock_list->id, 'Second input is list id');
};

done_testing();
