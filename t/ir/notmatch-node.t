# ABOUTME: Tests for NotMatch IR node
# ABOUTME: Verifies NotMatch node structure for !~ regex non-matching

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::NotMatch;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Scalar::Util 'blessed';

# Create fresh graph for tests
my $graph = Chalk::IR::Graph->new();

# Create mock left and right operands
my $mock_left = Chalk::IR::Node::Constant->new(
    value => 'string_to_test',
    type => Chalk::Grammar::Chalk::Type::Str->new()
);

my $mock_right = Chalk::IR::Node::Constant->new(
    value => '/pattern/',
    type => Chalk::Grammar::Chalk::Type::Str->new()
);

subtest 'NotMatch node basic structure' => sub {
    my $notmatch = Chalk::IR::Node::NotMatch->new(
        left  => $mock_left,
        right => $mock_right,
    );

    ok(defined($notmatch), 'NotMatch node is defined');
    ok(blessed($notmatch), 'NotMatch node is blessed');
    ok($notmatch->isa('Chalk::IR::Node::NotMatch'), 'NotMatch node has correct type');
};

subtest 'NotMatch node op method' => sub {
    my $notmatch = Chalk::IR::Node::NotMatch->new(
        left  => $mock_left,
        right => $mock_right,
    );

    is($notmatch->op(), 'NotMatch', 'op() returns NotMatch');
};

subtest 'NotMatch node accessors' => sub {
    my $notmatch = Chalk::IR::Node::NotMatch->new(
        left  => $mock_left,
        right => $mock_right,
    );

    ok(defined($notmatch->left), 'left accessor works');
    ok(defined($notmatch->right), 'right accessor works');
    is($notmatch->left->id, $mock_left->id, 'left is correct');
    is($notmatch->right->id, $mock_right->id, 'right is correct');
};

subtest 'NotMatch node to_hash' => sub {
    my $notmatch = Chalk::IR::Node::NotMatch->new(
        left  => $mock_left,
        right => $mock_right,
    );

    my $hash = $notmatch->to_hash();
    is($hash->{op}, 'NotMatch', 'to_hash op is NotMatch');
    is($hash->{id}, $notmatch->id, 'to_hash id matches');
    ok(defined($hash->{attributes}), 'to_hash has attributes');
    is($hash->{attributes}{left_id}, $mock_left->id, 'attributes has left_id');
    is($hash->{attributes}{right_id}, $mock_right->id, 'attributes has right_id');
};

subtest 'NotMatch node inputs' => sub {
    my $notmatch = Chalk::IR::Node::NotMatch->new(
        left  => $mock_left,
        right => $mock_right,
    );

    my $inputs = $notmatch->inputs();
    ok(ref($inputs) eq 'ARRAY', 'inputs returns arrayref');
    is(scalar(@$inputs), 2, 'inputs has 2 elements');
    is($inputs->[0], $mock_left->id, 'First input is left id');
    is($inputs->[1], $mock_right->id, 'Second input is right id');
};

done_testing();
