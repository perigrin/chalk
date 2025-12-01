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
    is(refaddr($type), refaddr(Chalk::IR::Type::Top->top()), 'compute() returns TOP singleton');
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

# TypeBool tests for Constant node
use_ok('Chalk::IR::Type::TypeBool');
use builtin qw(true false is_bool);

subtest 'Constant node compute() returns TypeBool for Bool type' => sub {
    my $const_true = Chalk::IR::Node::Constant->new(value => true, type => 'Bool');
    my $const_false = Chalk::IR::Node::Constant->new(value => false, type => 'Bool');

    my $type_true = $const_true->compute();
    ok($type_true isa Chalk::IR::Type::TypeBool, 'compute() returns TypeBool for Bool constant');
    is($type_true->is_constant, 1, 'TypeBool is constant');
    ok(is_bool($type_true->value), 'TypeBool value is native bool');
    ok($type_true->value, 'TypeBool TRUE value is truthy');

    my $type_false = $const_false->compute();
    ok($type_false isa Chalk::IR::Type::TypeBool, 'compute() returns TypeBool for false');
    ok(!$type_false->value, 'TypeBool FALSE value is falsy');
};

# Task 7: Add node compute() - returns sum if both inputs are constant
use_ok('Chalk::IR::Node::Add');

subtest 'Add node compute() with constant inputs' => sub {
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $const5 = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $add = Chalk::IR::Node::Add->new(left => $const3, right => $const5);

    ok($add->can('compute'), 'Add node has compute() method');

    my $type = $add->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger for constant addition');
    is($type->is_constant, 1, 'Result is constant');
    is($type->value, 8, '3 + 5 = 8');
};

subtest 'Add node compute() with non-constant input returns TOP' => sub {
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    # Use Base node as a non-constant input (its compute() returns TOP)
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $add = Chalk::IR::Node::Add->new(left => $const3, right => $unknown);

    my $type = $add->compute();
    # After TypeInteger lattice enhancement, adding integer to unknown returns IntTop
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when one operand is integer');
};

subtest 'Add node compute() with unknown integer returns IntTop' => sub {
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);
    my $add = Chalk::IR::Node::Add->new(left => $const3, right => $unknown);

    my $type = $add->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when one input is unknown');
    ok($type->is_top, 'Result is IntTop (unknown integer)');
    ok(!$type->is_constant, 'Result is not constant');
};

# Task 8: peephole() uses compute() to fold constants
subtest 'Add peephole() folds constant addition' => sub {
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $const5 = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $add = Chalk::IR::Node::Add->new(left => $const3, right => $const5);

    # Peephole should return a Constant node, not the Add node
    my $result = $add->peephole(undef);

    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant node for constant addition');
    is($result->value, 8, 'Constant node has folded value 3 + 5 = 8');
};

subtest 'Add peephole() returns self when not constant-foldable' => sub {
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $add = Chalk::IR::Node::Add->new(left => $const3, right => $unknown);

    my $result = $add->peephole(undef);

    is(refaddr($result), refaddr($add), 'peephole() returns self when inputs not constant');
};

# Task 9: Subtract node compute() and peephole()
use_ok('Chalk::IR::Node::Subtract');

subtest 'Subtract node compute() with constant inputs' => sub {
    my $const10 = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');

    my $sub = Chalk::IR::Node::Subtract->new(left => $const10, right => $const3);

    ok($sub->can('compute'), 'Subtract node has compute() method');

    my $type = $sub->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger for constant subtraction');
    is($type->is_constant, 1, 'Result is constant');
    is($type->value, 7, '10 - 3 = 7');
};

subtest 'Subtract node compute() with non-constant input returns TypeInteger' => sub {
    my $const10 = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $sub = Chalk::IR::Node::Subtract->new(left => $const10, right => $unknown);

    my $type = $sub->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when one operand is integer');
};

subtest 'Subtract peephole() folds constant subtraction' => sub {
    my $const10 = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');

    my $sub = Chalk::IR::Node::Subtract->new(left => $const10, right => $const3);

    my $result = $sub->peephole(undef);

    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant node for constant subtraction');
    is($result->value, 7, 'Constant node has folded value 10 - 3 = 7');
};

subtest 'Subtract peephole() returns self when not constant-foldable' => sub {
    my $const10 = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $sub = Chalk::IR::Node::Subtract->new(left => $const10, right => $unknown);

    my $result = $sub->peephole(undef);

    is(refaddr($result), refaddr($sub), 'peephole() returns self when inputs not constant');
};

subtest 'Subtract node compute() with unknown integer returns IntTop' => sub {
    my $const10 = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);
    my $sub = Chalk::IR::Node::Subtract->new(left => $const10, right => $unknown);

    my $type = $sub->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when one input is unknown');
    ok($type->is_top, 'Result is IntTop (unknown integer)');
};

# Task 10: Multiply node compute() and peephole()
use_ok('Chalk::IR::Node::Multiply');

subtest 'Multiply node compute() with constant inputs' => sub {
    my $const6 = Chalk::IR::Node::Constant->new(value => 6, type => 'Integer');
    my $const7 = Chalk::IR::Node::Constant->new(value => 7, type => 'Integer');

    my $mul = Chalk::IR::Node::Multiply->new(left => $const6, right => $const7);

    ok($mul->can('compute'), 'Multiply node has compute() method');

    my $type = $mul->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger for constant multiplication');
    is($type->is_constant, 1, 'Result is constant');
    is($type->value, 42, '6 * 7 = 42');
};

subtest 'Multiply node compute() with non-constant input returns TypeInteger' => sub {
    my $const6 = Chalk::IR::Node::Constant->new(value => 6, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $mul = Chalk::IR::Node::Multiply->new(left => $const6, right => $unknown);

    my $type = $mul->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when input is non-constant');
};

subtest 'Multiply peephole() folds constant multiplication' => sub {
    my $const6 = Chalk::IR::Node::Constant->new(value => 6, type => 'Integer');
    my $const7 = Chalk::IR::Node::Constant->new(value => 7, type => 'Integer');

    my $mul = Chalk::IR::Node::Multiply->new(left => $const6, right => $const7);

    my $result = $mul->peephole(undef);

    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant node for constant multiplication');
    is($result->value, 42, 'Constant node has folded value 6 * 7 = 42');
};

subtest 'Multiply peephole() returns self when not constant-foldable' => sub {
    my $const6 = Chalk::IR::Node::Constant->new(value => 6, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $mul = Chalk::IR::Node::Multiply->new(left => $const6, right => $unknown);

    my $result = $mul->peephole(undef);

    is(refaddr($result), refaddr($mul), 'peephole() returns self when inputs not constant');
};

subtest 'Multiply node compute() with unknown integer returns IntTop' => sub {
    my $const6 = Chalk::IR::Node::Constant->new(value => 6, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);
    my $mul = Chalk::IR::Node::Multiply->new(left => $const6, right => $unknown);

    my $type = $mul->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when one input is unknown');
    ok($type->is_top, 'Result is IntTop (unknown integer)');
};

# Task 11: Divide node compute() and peephole()
use_ok('Chalk::IR::Node::Divide');

subtest 'Divide node compute() with constant inputs' => sub {
    my $const20 = Chalk::IR::Node::Constant->new(value => 20, type => 'Integer');
    my $const4 = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');

    my $div = Chalk::IR::Node::Divide->new(left => $const20, right => $const4);

    ok($div->can('compute'), 'Divide node has compute() method');

    my $type = $div->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger for constant division');
    is($type->is_constant, 1, 'Result is constant');
    is($type->value, 5, '20 / 4 = 5');
};

subtest 'Divide node compute() with non-constant input returns TOP' => sub {
    my $const20 = Chalk::IR::Node::Constant->new(value => 20, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $div = Chalk::IR::Node::Divide->new(left => $const20, right => $unknown);

    my $type = $div->compute();
    ok($type isa Chalk::IR::Type::Top, 'compute() returns TOP when input is non-constant');
};

subtest 'Divide peephole() folds constant division' => sub {
    my $const20 = Chalk::IR::Node::Constant->new(value => 20, type => 'Integer');
    my $const4 = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');

    my $div = Chalk::IR::Node::Divide->new(left => $const20, right => $const4);

    my $result = $div->peephole(undef);

    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant node for constant division');
    is($result->value, 5, 'Constant node has folded value 20 / 4 = 5');
};

subtest 'Divide peephole() returns self when not constant-foldable' => sub {
    my $const20 = Chalk::IR::Node::Constant->new(value => 20, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $div = Chalk::IR::Node::Divide->new(left => $const20, right => $unknown);

    my $result = $div->peephole(undef);

    is(refaddr($result), refaddr($div), 'peephole() returns self when inputs not constant');
};

# Task 12: Negate node compute() and peephole()
use_ok('Chalk::IR::Node::Negate');

subtest 'Negate node compute() with constant input' => sub {
    my $const42 = Chalk::IR::Node::Constant->new(value => 42, type => 'Integer');

    my $neg = Chalk::IR::Node::Negate->new(operand => $const42);

    ok($neg->can('compute'), 'Negate node has compute() method');

    my $type = $neg->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger for constant negation');
    is($type->is_constant, 1, 'Result is constant');
    is($type->value, -42, '-42');
};

subtest 'Negate node compute() with non-constant input returns TOP' => sub {
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $neg = Chalk::IR::Node::Negate->new(operand => $unknown);

    my $type = $neg->compute();
    ok($type isa Chalk::IR::Type::Top, 'compute() returns TOP when input is non-constant');
};

subtest 'Negate peephole() folds constant negation' => sub {
    my $const42 = Chalk::IR::Node::Constant->new(value => 42, type => 'Integer');

    my $neg = Chalk::IR::Node::Negate->new(operand => $const42);

    my $result = $neg->peephole(undef);

    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant node for constant negation');
    is($result->value, -42, 'Constant node has folded value -42');
};

subtest 'Negate peephole() returns self when not constant-foldable' => sub {
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);

    my $neg = Chalk::IR::Node::Negate->new(operand => $unknown);

    my $result = $neg->peephole(undef);

    is(refaddr($result), refaddr($neg), 'peephole() returns self when input not constant');
};

done_testing();
