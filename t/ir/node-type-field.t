# ABOUTME: Test that IR nodes have a type field with proper default
# ABOUTME: Validates type field infrastructure for type system integration

use v5.42;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Test::More;

use Chalk::IR::Node;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Integer;

# Test 1: Node has type field defaulting to Top
subtest 'Node type field defaults to Top' => sub {
    my $node = Chalk::IR::Node->new(
        id => 'test_1',
        op => 'TestOp',
        inputs => [],
        attributes => {},
    );

    ok($node->can('type'), 'Node has type accessor');
    my $type = $node->type;
    ok($type isa Chalk::IR::Type::Top, 'Default type is Top');
};

# Test 2: Node accepts explicit type parameter
subtest 'Node accepts type parameter' => sub {
    my $int_type = Chalk::IR::Type::Integer->TOP();
    my $node = Chalk::IR::Node->new(
        id => 'test_2',
        op => 'TestOp',
        inputs => [],
        attributes => {},
        type => $int_type,
    );

    my $type = $node->type;
    ok($type isa Chalk::IR::Type::Integer, 'Explicit type preserved');
};

# Test 3: compute_type returns cached type by default
subtest 'compute_type returns cached type' => sub {
    my $int_type = Chalk::IR::Type::Integer->constant(42);
    my $node = Chalk::IR::Node->new(
        id => 'test_3',
        op => 'TestOp',
        inputs => [],
        attributes => {},
        type => $int_type,
    );

    ok($node->can('compute_type'), 'Node has compute_type method');
    my $computed = $node->compute_type;
    is($computed, $int_type, 'compute_type returns cached type');
};

done_testing();
