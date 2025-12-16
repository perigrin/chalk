# ABOUTME: Tests for Filter IR node
# ABOUTME: Verifies Filter node structure, inputs, and serialization

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::Filter;
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

subtest 'Filter node basic structure' => sub {
    my $filter = Chalk::IR::Node::Filter->new(
        block => $mock_block,
        list  => $mock_list,
    );

    ok(defined($filter), 'Filter node is defined');
    ok(blessed($filter), 'Filter node is blessed');
    ok($filter->isa('Chalk::IR::Node::Filter'), 'Filter node has correct type');
};

subtest 'Filter node op method' => sub {
    my $filter = Chalk::IR::Node::Filter->new(
        block => $mock_block,
        list  => $mock_list,
    );

    is($filter->op(), 'Filter', 'op() returns Filter');
};

subtest 'Filter node accessors' => sub {
    my $filter = Chalk::IR::Node::Filter->new(
        block => $mock_block,
        list  => $mock_list,
    );

    ok(defined($filter->block), 'block accessor works');
    ok(defined($filter->list), 'list accessor works');
    is($filter->block->id, $mock_block->id, 'block is correct');
    is($filter->list->id, $mock_list->id, 'list is correct');
};

subtest 'Filter node to_hash' => sub {
    my $filter = Chalk::IR::Node::Filter->new(
        block => $mock_block,
        list  => $mock_list,
    );

    my $hash = $filter->to_hash();
    is($hash->{op}, 'Filter', 'to_hash op is Filter');
    is($hash->{id}, $filter->id, 'to_hash id matches');
    ok(defined($hash->{attributes}), 'to_hash has attributes');
    is($hash->{attributes}{block_id}, $mock_block->id, 'attributes has block_id');
    is($hash->{attributes}{list_id}, $mock_list->id, 'attributes has list_id');
};

subtest 'Filter node inputs' => sub {
    my $filter = Chalk::IR::Node::Filter->new(
        block => $mock_block,
        list  => $mock_list,
    );

    my $inputs = $filter->inputs();
    ok(ref($inputs) eq 'ARRAY', 'inputs returns arrayref');
    is(scalar(@$inputs), 2, 'inputs has 2 elements');
    is($inputs->[0], $mock_block->id, 'First input is block id');
    is($inputs->[1], $mock_list->id, 'Second input is list id');
};

done_testing();
