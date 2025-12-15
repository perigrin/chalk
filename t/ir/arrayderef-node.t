# ABOUTME: Tests for ArrayDeref IR node
# ABOUTME: Verifies ArrayDeref node for array reference dereferencing (@$ref)

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::ArrayDeref;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Int;
use Scalar::Util 'blessed', 'refaddr';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

subtest 'ArrayDeref node basic structure' => sub {
    my $ref_node = Chalk::IR::Node::Constant->new(
        value => 12345,  # Mock ref ID
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $deref = Chalk::IR::Node::ArrayDeref->new(
        ref_id => $ref_node->id,
    );

    ok(defined($deref), 'ArrayDeref node is defined');
    ok(blessed($deref), 'ArrayDeref node is blessed');
    ok($deref->isa('Chalk::IR::Node::ArrayDeref'), 'ArrayDeref node has correct type');
};

subtest 'ArrayDeref node op method' => sub {
    my $deref = Chalk::IR::Node::ArrayDeref->new(
        ref_id => 12345,
    );

    is($deref->op, 'ArrayDeref', 'op() returns ArrayDeref');
};

subtest 'ArrayDeref node accessors' => sub {
    my $deref = Chalk::IR::Node::ArrayDeref->new(
        ref_id => 67890,
    );

    is($deref->ref_id, 67890, 'ref_id accessor works');
};

subtest 'ArrayDeref node to_hash' => sub {
    my $deref = Chalk::IR::Node::ArrayDeref->new(
        ref_id => 11111,
    );

    my $hash = $deref->to_hash;
    is($hash->{op}, 'ArrayDeref', 'to_hash op is ArrayDeref');
    is($hash->{id}, $deref->id, 'to_hash id matches');
    ok(exists $hash->{attributes}, 'to_hash has attributes');
    is($hash->{attributes}{ref_id}, 11111, 'attributes has ref_id');
};

done_testing();
