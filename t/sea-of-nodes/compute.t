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

# Task 6: Constant node compute() returns TypeInteger
use_ok('Chalk::IR::Node::Constant');

subtest 'Constant node compute() returns TypeInteger' => sub {
    my $const42 = Chalk::IR::Node::Constant->new(value => 42, type => 'Integer');
    my $const0 = Chalk::IR::Node::Constant->new(value => 0, type => 'Integer');

    ok($const42->can('compute'), 'Constant node has compute() method');

    my $type42 = $const42->compute();
    ok($type42 isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger for integer constant');
    is($type42->is_constant, 1, 'TypeInteger is constant');
    is($type42->value, 42, 'TypeInteger has correct value');

    my $type0 = $const0->compute();
    ok($type0 isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger for zero');
    is($type0->value, 0, 'TypeInteger has value 0');
};

done_testing();
