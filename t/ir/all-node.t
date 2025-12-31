# ABOUTME: Tests for All IR node
# ABOUTME: Verifies All node structure, inputs, and serialization

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::All;
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

subtest 'All node basic structure' => sub {
    my $all = Chalk::IR::Node::All->new(
        block => $mock_block,
        list  => $mock_list,
    );

    ok(defined($all), 'All node is defined');
    ok(blessed($all), 'All node is blessed');
    ok($all->isa('Chalk::IR::Node::All'), 'All node has correct type');
};

subtest 'All node op method' => sub {
    my $all = Chalk::IR::Node::All->new(
        block => $mock_block,
        list  => $mock_list,
    );

    is($all->op(), 'All', 'op() returns All');
};

subtest 'All node accessors' => sub {
    my $all = Chalk::IR::Node::All->new(
        block => $mock_block,
        list  => $mock_list,
    );

    ok(defined($all->block), 'block accessor works');
    ok(defined($all->list), 'list accessor works');
    is($all->block->id, $mock_block->id, 'block is correct');
    is($all->list->id, $mock_list->id, 'list is correct');
};

subtest 'All node to_hash' => sub {
    my $all = Chalk::IR::Node::All->new(
        block => $mock_block,
        list  => $mock_list,
    );

    my $hash = $all->to_hash();
    is($hash->{op}, 'All', 'to_hash op is All');
    is($hash->{id}, $all->id, 'to_hash id matches');
    ok(defined($hash->{attributes}), 'to_hash has attributes');
    is($hash->{attributes}{block_id}, $mock_block->id, 'attributes has block_id');
    is($hash->{attributes}{list_id}, $mock_list->id, 'attributes has list_id');
};

subtest 'All node inputs' => sub {
    my $all = Chalk::IR::Node::All->new(
        block => $mock_block,
        list  => $mock_list,
    );

    my $inputs = $all->inputs();
    ok(ref($inputs) eq 'ARRAY', 'inputs returns arrayref');
    is(scalar(@$inputs), 2, 'inputs has 2 elements');
    is($inputs->[0], $mock_block->id, 'First input is block id');
    is($inputs->[1], $mock_list->id, 'Second input is list id');
};

done_testing();
