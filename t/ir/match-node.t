# ABOUTME: Tests for Match IR node
# ABOUTME: Verifies Match node structure for =~ regex matching

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::Match;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Scalar::Util 'blessed';

# Create fresh graph for tests
my $graph = Chalk::IR::Graph->new();

# Create mock left and right operands
my $mock_left = Chalk::IR::Node::Constant->new(
    value => 'string_to_match',
    type => Chalk::Grammar::Chalk::Type::Str->new()
);

my $mock_right = Chalk::IR::Node::Constant->new(
    value => '/pattern/',
    type => Chalk::Grammar::Chalk::Type::Str->new()
);

subtest 'Match node basic structure' => sub {
    my $match = Chalk::IR::Node::Match->new(
        left  => $mock_left,
        right => $mock_right,
    );

    ok(defined($match), 'Match node is defined');
    ok(blessed($match), 'Match node is blessed');
    ok($match->isa('Chalk::IR::Node::Match'), 'Match node has correct type');
};

subtest 'Match node op method' => sub {
    my $match = Chalk::IR::Node::Match->new(
        left  => $mock_left,
        right => $mock_right,
    );

    is($match->op(), 'Match', 'op() returns Match');
};

subtest 'Match node accessors' => sub {
    my $match = Chalk::IR::Node::Match->new(
        left  => $mock_left,
        right => $mock_right,
    );

    ok(defined($match->left), 'left accessor works');
    ok(defined($match->right), 'right accessor works');
    is($match->left->id, $mock_left->id, 'left is correct');
    is($match->right->id, $mock_right->id, 'right is correct');
};

subtest 'Match node to_hash' => sub {
    my $match = Chalk::IR::Node::Match->new(
        left  => $mock_left,
        right => $mock_right,
    );

    my $hash = $match->to_hash();
    is($hash->{op}, 'Match', 'to_hash op is Match');
    is($hash->{id}, $match->id, 'to_hash id matches');
    ok(defined($hash->{attributes}), 'to_hash has attributes');
    is($hash->{attributes}{left_id}, $mock_left->id, 'attributes has left_id');
    is($hash->{attributes}{right_id}, $mock_right->id, 'attributes has right_id');
};

subtest 'Match node inputs' => sub {
    my $match = Chalk::IR::Node::Match->new(
        left  => $mock_left,
        right => $mock_right,
    );

    my $inputs = $match->inputs();
    ok(ref($inputs) eq 'ARRAY', 'inputs returns arrayref');
    is(scalar(@$inputs), 2, 'inputs has 2 elements');
    is($inputs->[0], $mock_left->id, 'First input is left id');
    is($inputs->[1], $mock_right->id, 'Second input is right id');
};

done_testing();
