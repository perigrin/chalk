# ABOUTME: Tests for Any IR node
# ABOUTME: Verifies Any node structure, inputs, and serialization

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::Any;
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

subtest 'Any node basic structure' => sub {
    my $any = Chalk::IR::Node::Any->new(
        block => $mock_block,
        list  => $mock_list,
    );

    ok(defined($any), 'Any node is defined');
    ok(blessed($any), 'Any node is blessed');
    ok($any->isa('Chalk::IR::Node::Any'), 'Any node has correct type');
};

subtest 'Any node op method' => sub {
    my $any = Chalk::IR::Node::Any->new(
        block => $mock_block,
        list  => $mock_list,
    );

    is($any->op(), 'Any', 'op() returns Any');
};

subtest 'Any node accessors' => sub {
    my $any = Chalk::IR::Node::Any->new(
        block => $mock_block,
        list  => $mock_list,
    );

    ok(defined($any->block), 'block accessor works');
    ok(defined($any->list), 'list accessor works');
    is($any->block->id, $mock_block->id, 'block is correct');
    is($any->list->id, $mock_list->id, 'list is correct');
};

subtest 'Any node to_hash' => sub {
    my $any = Chalk::IR::Node::Any->new(
        block => $mock_block,
        list  => $mock_list,
    );

    my $hash = $any->to_hash();
    is($hash->{op}, 'Any', 'to_hash op is Any');
    is($hash->{id}, $any->id, 'to_hash id matches');
    ok(defined($hash->{attributes}), 'to_hash has attributes');
    is($hash->{attributes}{block_id}, $mock_block->id, 'attributes has block_id');
    is($hash->{attributes}{list_id}, $mock_list->id, 'attributes has list_id');
};

subtest 'Any node inputs' => sub {
    my $any = Chalk::IR::Node::Any->new(
        block => $mock_block,
        list  => $mock_list,
    );

    my $inputs = $any->inputs();
    ok(ref($inputs) eq 'ARRAY', 'inputs returns arrayref');
    is(scalar(@$inputs), 2, 'inputs has 2 elements');
    is($inputs->[0], $mock_block->id, 'First input is block id');
    is($inputs->[1], $mock_list->id, 'Second input is list id');
};

done_testing();
