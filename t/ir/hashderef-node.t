# ABOUTME: Tests for HashDeref IR node
# ABOUTME: Verifies HashDeref node for hash reference dereferencing (%$ref)

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::HashDeref;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Int;
use Scalar::Util 'blessed', 'refaddr';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

subtest 'HashDeref node basic structure' => sub {
    my $ref_node = Chalk::IR::Node::Constant->new(
        value => 12345,  # Mock ref ID
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $deref = Chalk::IR::Node::HashDeref->new(
        ref_id => $ref_node->id,
    );

    ok(defined($deref), 'HashDeref node is defined');
    ok(blessed($deref), 'HashDeref node is blessed');
    ok($deref->isa('Chalk::IR::Node::HashDeref'), 'HashDeref node has correct type');
};

subtest 'HashDeref node op method' => sub {
    my $deref = Chalk::IR::Node::HashDeref->new(
        ref_id => 12345,
    );

    is($deref->op, 'HashDeref', 'op() returns HashDeref');
};

subtest 'HashDeref node accessors' => sub {
    my $deref = Chalk::IR::Node::HashDeref->new(
        ref_id => 67890,
    );

    is($deref->ref_id, 67890, 'ref_id accessor works');
};

subtest 'HashDeref node to_hash' => sub {
    my $deref = Chalk::IR::Node::HashDeref->new(
        ref_id => 11111,
    );

    my $hash = $deref->to_hash;
    is($hash->{op}, 'HashDeref', 'to_hash op is HashDeref');
    is($hash->{id}, $deref->id, 'to_hash id matches');
    ok(exists $hash->{attributes}, 'to_hash has attributes');
    is($hash->{attributes}{ref_id}, 11111, 'attributes has ref_id');
};

done_testing();
