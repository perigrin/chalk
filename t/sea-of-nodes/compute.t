# ABOUTME: Unit tests for compute() method on IR nodes
# ABOUTME: Tests type inference for constant folding optimization

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(refaddr);

# Load type system
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::TypeInteger;

# Test 1: Base node compute() returns TOP (default behavior)
use_ok('Chalk::IR::Node::Base');

subtest 'Base node compute() returns TOP' => sub {
    # Create a minimal concrete subclass for testing
    # Since Base is abstract, we test that compute() method exists and returns TOP
    my $base = Chalk::IR::Node::Base->new(inputs => []);

    ok($base->can('compute'), 'Base node has compute() method');
    my $type = $base->compute();
    ok($type isa Chalk::IR::Type::Top, 'compute() returns Top type');
    is(refaddr($type), refaddr(Chalk::IR::Type::Top->TOP), 'compute() returns TOP singleton');
};

done_testing();
